/* zuxml: the immutable document tree.
 *
 * An ordinary consumer of the event seam (design section 3): it registers
 * zux_handlers and has no privileged access to Expat, which is what will let
 * a second producer -- an HTML tokenizer -- reuse it later.
 *
 * Layout is three growable arrays plus one string buffer, everything
 * addressed by index or offset (design section 5). Nothing here recurses:
 * construction is driven by events, and teardown is a handful of free()
 * calls, so hostile nesting cannot exhaust the stack.
 */

#include <stdlib.h>
#include <string.h>

#include "zux.h"

typedef struct {
  zux_id parent, first_child, last_child, next_sibling;
  zux_id name;
  uint32_t str_off, str_len;
  uint32_t attr_start, attr_count;
  uint8_t kind;
} zux_node;

typedef struct {
  uint32_t uri_off, uri_len;
  uint32_t local_off, local_len;
  uint32_t prefix_off, prefix_len;
} zux_qname;

typedef struct {
  zux_id name;
  uint32_t val_off, val_len;
} zux_attr_slot;

struct zux_document {
  zux_node *nodes;
  uint32_t n_nodes, cap_nodes;

  zux_attr_slot *attrs;
  uint32_t n_attrs, cap_attrs;

  zux_qname *names;
  uint32_t n_names, cap_names;

  char *strings;
  size_t n_strings, cap_strings;

  uint32_t *hash; /* open addressing: slot holds name id + 1, 0 = empty */
  uint32_t hash_cap;

  size_t mem;
  size_t max_memory;

  uint32_t version_off, version_len;
  uint32_t encoding_off, encoding_len;
  int standalone;

  zux_status status;
};

/* Build state threaded through the handlers. */
typedef struct {
  zux_document *d;
  zux_id cur;
} zux_build;

static const zux_str ZUX_EMPTY_STR = {"", 0};

/* ---- allocation ------------------------------------------------------- */

static int
charge(zux_document *d, size_t delta) {
  if (delta > d->max_memory - d->mem) {
    d->status = ZUX_ERR_MEMORY_LIMIT;
    return 0;
  }
  d->mem += delta;
  return 1;
}

static int
grow_strings(zux_document *d, size_t need) {
  size_t cap = d->cap_strings ? d->cap_strings : 1024;
  char *p;
  if (need <= d->cap_strings)
    return 1;
  while (cap < need)
    cap *= 2;
  if (! charge(d, cap - d->cap_strings))
    return 0;
  p = (char *)realloc(d->strings, cap);
  if (p == NULL) {
    d->status = ZUX_ERR_MEMORY;
    return 0;
  }
  d->strings = p;
  d->cap_strings = cap;
  return 1;
}

/* Copy bytes into the document's string buffer, NUL-terminated. NUL is not a
 * legal XML character, so termination is unambiguous and C consumers get a
 * plain string while the explicit length is still carried everywhere. */
static uint32_t
str_add(zux_document *d, const char *p, size_t len, int *ok) {
  uint32_t off;
  if (! grow_strings(d, d->n_strings + len + 1)) {
    *ok = 0;
    return 0;
  }
  off = (uint32_t)d->n_strings;
  if (len > 0)
    memcpy(d->strings + off, p, len);
  d->strings[off + len] = '\0';
  d->n_strings += len + 1;
  *ok = 1;
  return off;
}

static int
grow_nodes(zux_document *d) {
  uint32_t cap;
  zux_node *p;
  if (d->n_nodes < d->cap_nodes)
    return 1;
  cap = d->cap_nodes ? d->cap_nodes * 2 : 64;
  if (! charge(d, (size_t)(cap - d->cap_nodes) * sizeof(zux_node)))
    return 0;
  p = (zux_node *)realloc(d->nodes, (size_t)cap * sizeof(zux_node));
  if (p == NULL) {
    d->status = ZUX_ERR_MEMORY;
    return 0;
  }
  d->nodes = p;
  d->cap_nodes = cap;
  return 1;
}

static int
grow_attrs(zux_document *d, uint32_t need) {
  uint32_t cap = d->cap_attrs ? d->cap_attrs : 32;
  zux_attr_slot *p;
  if (need <= d->cap_attrs)
    return 1;
  while (cap < need)
    cap *= 2;
  if (! charge(d, (size_t)(cap - d->cap_attrs) * sizeof(zux_attr_slot)))
    return 0;
  p = (zux_attr_slot *)realloc(d->attrs, (size_t)cap * sizeof(zux_attr_slot));
  if (p == NULL) {
    d->status = ZUX_ERR_MEMORY;
    return 0;
  }
  d->attrs = p;
  d->cap_attrs = cap;
  return 1;
}

/* ---- name interning ---------------------------------------------------- */

static uint32_t
hash_str(const char *p, size_t len, uint32_t h) {
  size_t i;
  for (i = 0; i < len; i++) {
    h ^= (unsigned char)p[i];
    h *= 16777619u;
  }
  return h;
}

static uint32_t
name_hash(const zux_name *n) {
  uint32_t h = 2166136261u;
  h = hash_str(n->uri.ptr, n->uri.len, h);
  h = hash_str("\x01", 1, h);
  h = hash_str(n->local.ptr, n->local.len, h);
  h = hash_str("\x01", 1, h);
  h = hash_str(n->prefix.ptr, n->prefix.len, h);
  return h;
}

static int
name_eq(const zux_document *d, const zux_qname *q, const zux_name *n) {
  return q->uri_len == n->uri.len && q->local_len == n->local.len
         && q->prefix_len == n->prefix.len
         && memcmp(d->strings + q->uri_off, n->uri.ptr, n->uri.len) == 0
         && memcmp(d->strings + q->local_off, n->local.ptr, n->local.len) == 0
         && memcmp(d->strings + q->prefix_off, n->prefix.ptr, n->prefix.len)
                == 0;
}

static int
rehash(zux_document *d, uint32_t cap) {
  uint32_t *h;
  uint32_t i;
  if (! charge(d, (size_t)(cap - d->hash_cap) * sizeof(uint32_t)))
    return 0;
  h = (uint32_t *)calloc(cap, sizeof(uint32_t));
  if (h == NULL) {
    d->status = ZUX_ERR_MEMORY;
    return 0;
  }
  for (i = 0; i < d->n_names; i++) {
    zux_name tmp;
    uint32_t slot;
    zux_qname *q = &d->names[i];
    tmp.uri.ptr = d->strings + q->uri_off;
    tmp.uri.len = q->uri_len;
    tmp.local.ptr = d->strings + q->local_off;
    tmp.local.len = q->local_len;
    tmp.prefix.ptr = d->strings + q->prefix_off;
    tmp.prefix.len = q->prefix_len;
    slot = name_hash(&tmp) & (cap - 1);
    while (h[slot] != 0)
      slot = (slot + 1) & (cap - 1);
    h[slot] = i + 1;
  }
  free(d->hash);
  d->hash = h;
  d->hash_cap = cap;
  return 1;
}

/* Element names, attribute names and namespace URIs repeat heavily in real
 * XML; interning them is the single largest memory win available and costs
 * one small open-addressed table. Text and attribute values are not
 * interned -- they rarely repeat and hashing them would cost more than it
 * saves. */
static zux_id
intern_name(zux_document *d, const zux_name *n, int *ok) {
  uint32_t slot, h;
  zux_qname q;
  int sub_ok = 1;

  *ok = 1;
  if (d->hash_cap == 0 && ! rehash(d, 64)) {
    *ok = 0;
    return ZUX_NONE;
  }
  if ((d->n_names + 1) * 10u >= d->hash_cap * 7u
      && ! rehash(d, d->hash_cap * 2)) {
    *ok = 0;
    return ZUX_NONE;
  }

  h = name_hash(n);
  slot = h & (d->hash_cap - 1);
  while (d->hash[slot] != 0) {
    uint32_t id = d->hash[slot] - 1;
    if (name_eq(d, &d->names[id], n))
      return id;
    slot = (slot + 1) & (d->hash_cap - 1);
  }

  if (d->n_names >= d->cap_names) {
    uint32_t cap = d->cap_names ? d->cap_names * 2 : 32;
    zux_qname *p;
    if (! charge(d, (size_t)(cap - d->cap_names) * sizeof(zux_qname))) {
      *ok = 0;
      return ZUX_NONE;
    }
    p = (zux_qname *)realloc(d->names, (size_t)cap * sizeof(zux_qname));
    if (p == NULL) {
      d->status = ZUX_ERR_MEMORY;
      *ok = 0;
      return ZUX_NONE;
    }
    d->names = p;
    d->cap_names = cap;
  }

  q.uri_off = str_add(d, n->uri.ptr, n->uri.len, &sub_ok);
  q.uri_len = (uint32_t)n->uri.len;
  if (sub_ok)
    q.local_off = str_add(d, n->local.ptr, n->local.len, &sub_ok);
  q.local_len = (uint32_t)n->local.len;
  if (sub_ok)
    q.prefix_off = str_add(d, n->prefix.ptr, n->prefix.len, &sub_ok);
  q.prefix_len = (uint32_t)n->prefix.len;
  if (! sub_ok) {
    *ok = 0;
    return ZUX_NONE;
  }

  d->names[d->n_names] = q;
  d->hash[slot] = d->n_names + 1;
  return d->n_names++;
}

/* ---- node construction ------------------------------------------------- */

static zux_id
node_add(zux_document *d, zux_build *b, uint8_t kind, int *ok) {
  zux_id id;
  zux_node *n;

  if (! grow_nodes(d)) {
    *ok = 0;
    return ZUX_NONE;
  }
  id = d->n_nodes++;
  n = &d->nodes[id];
  memset(n, 0, sizeof(*n));
  n->kind = kind;
  n->parent = n->first_child = n->last_child = n->next_sibling = ZUX_NONE;
  n->name = ZUX_NONE;

  if (b != NULL && b->cur != ZUX_NONE) {
    zux_node *p = &d->nodes[b->cur];
    n->parent = b->cur;
    if (p->last_child == ZUX_NONE) {
      p->first_child = p->last_child = id;
    } else {
      d->nodes[p->last_child].next_sibling = id;
      p->last_child = id;
    }
  }
  *ok = 1;
  return id;
}

/* ---- handlers ---------------------------------------------------------- */

static zux_status
t_start(void *ctx, const zux_name *name, const zux_attr *attrs,
        size_t n_attrs) {
  zux_build *b = (zux_build *)ctx;
  zux_document *d = b->d;
  zux_id id;
  int ok = 1;
  size_t i;

  id = node_add(d, b, ZUX_ELEMENT, &ok);
  if (! ok)
    return d->status;

  d->nodes[id].name = intern_name(d, name, &ok);
  if (! ok)
    return d->status;

  if (n_attrs > 0) {
    if (! grow_attrs(d, d->n_attrs + (uint32_t)n_attrs))
      return d->status;
    d->nodes[id].attr_start = d->n_attrs;
    d->nodes[id].attr_count = (uint32_t)n_attrs;
    for (i = 0; i < n_attrs; i++) {
      zux_attr_slot *s = &d->attrs[d->n_attrs + i];
      zux_id nm = intern_name(d, &attrs[i].name, &ok);
      if (! ok)
        return d->status;
      s->name = nm;
      s->val_off = str_add(d, attrs[i].value.ptr, attrs[i].value.len, &ok);
      s->val_len = (uint32_t)attrs[i].value.len;
      if (! ok)
        return d->status;
    }
    d->n_attrs += (uint32_t)n_attrs;
  }

  b->cur = id;
  return ZUX_OK;
}

static zux_status
t_end(void *ctx, const zux_name *name) {
  zux_build *b = (zux_build *)ctx;
  (void)name;
  if (b->cur != ZUX_NONE)
    b->cur = b->d->nodes[b->cur].parent;
  return ZUX_OK;
}

static zux_status
t_leaf(zux_build *b, uint8_t kind, zux_str text) {
  zux_document *d = b->d;
  int ok = 1;
  zux_id id = node_add(d, b, kind, &ok);
  if (! ok)
    return d->status;
  d->nodes[id].str_off = str_add(d, text.ptr, text.len, &ok);
  d->nodes[id].str_len = (uint32_t)text.len;
  if (! ok)
    return d->status;
  return ZUX_OK;
}

static zux_status
t_text(void *ctx, zux_str t) {
  return t_leaf((zux_build *)ctx, ZUX_TEXT, t);
}

static zux_status
t_comment(void *ctx, zux_str t) {
  return t_leaf((zux_build *)ctx, ZUX_COMMENT, t);
}

static zux_status
t_pi(void *ctx, zux_str target, zux_str data) {
  zux_build *b = (zux_build *)ctx;
  zux_document *d = b->d;
  zux_name nm;
  int ok = 1;
  zux_id id = node_add(d, b, ZUX_PI, &ok);
  if (! ok)
    return d->status;
  memset(&nm, 0, sizeof(nm));
  nm.uri = ZUX_EMPTY_STR;
  nm.prefix = ZUX_EMPTY_STR;
  nm.local = target;
  d->nodes[id].name = intern_name(d, &nm, &ok);
  if (! ok)
    return d->status;
  d->nodes[id].str_off = str_add(d, data.ptr, data.len, &ok);
  d->nodes[id].str_len = (uint32_t)data.len;
  if (! ok)
    return d->status;
  return ZUX_OK;
}

static zux_status
t_decl(void *ctx, zux_str version, zux_str encoding, int standalone) {
  zux_build *b = (zux_build *)ctx;
  zux_document *d = b->d;
  int ok = 1;
  d->version_off = str_add(d, version.ptr, version.len, &ok);
  d->version_len = (uint32_t)version.len;
  if (! ok)
    return d->status;
  d->encoding_off = str_add(d, encoding.ptr, encoding.len, &ok);
  d->encoding_len = (uint32_t)encoding.len;
  if (! ok)
    return d->status;
  d->standalone = standalone;
  return ZUX_OK;
}

/* ---- parse ------------------------------------------------------------- */

zux_status
zux_tree_parse(zux_document **out, const void *data, size_t n,
               const zux_options *opt, zux_error *err) {
  zux_document *d;
  zux_build b;
  zux_handlers h;
  zux_parser *p = NULL;
  zux_options defaults;
  zux_status st;
  int ok = 1;

  if (out == NULL)
    return ZUX_ERR_INVALID_ARGUMENT;
  *out = NULL;
  if (opt == NULL) {
    zux_options_init(&defaults);
    opt = &defaults;
  }

  d = (zux_document *)calloc(1, sizeof(*d));
  if (d == NULL)
    return ZUX_ERR_MEMORY;
  d->max_memory = opt->max_memory;
  d->status = ZUX_OK;
  d->standalone = -1;

  b.d = d;
  b.cur = ZUX_NONE;
  /* Node 0 is always the document node, and always exists. */
  (void)node_add(d, &b, ZUX_DOCUMENT, &ok);
  if (! ok) {
    st = d->status;
    zux_document_free(d);
    return st;
  }
  b.cur = 0;

  memset(&h, 0, sizeof(h));
  h.start_element = t_start;
  h.end_element = t_end;
  h.text = t_text;
  h.comment = t_comment;
  h.pi = t_pi;
  h.xml_decl = t_decl;

  st = zux_parser_new(&p, opt, &h, &b);
  if (st != ZUX_OK) {
    zux_document_free(d);
    return st;
  }

  st = zux_parser_feed(p, data, n);
  if (st == ZUX_OK)
    st = zux_parser_finish(p);
  if (err != NULL)
    zux_parser_error(p, err);
  zux_parser_free(p);

  if (st != ZUX_OK && st != ZUX_DONE) {
    zux_document_free(d);
    return st;
  }
  *out = d;
  return ZUX_OK;
}

void
zux_document_free(zux_document *d) {
  if (d == NULL)
    return;
  /* No traversal: the whole tree lives in four allocations. Deep nesting
   * cannot make teardown recurse. */
  free(d->nodes);
  free(d->attrs);
  free(d->names);
  free(d->strings);
  free(d->hash);
  free(d);
}

/* ---- accessors --------------------------------------------------------- */

static const zux_node *
node_at(const zux_document *d, zux_id id) {
  if (d == NULL || id >= d->n_nodes)
    return NULL;
  return &d->nodes[id];
}

zux_id
zux_root(const zux_document *d) {
  const zux_node *doc = node_at(d, 0);
  zux_id c;
  if (doc == NULL)
    return ZUX_NONE;
  for (c = doc->first_child; c != ZUX_NONE; c = d->nodes[c].next_sibling)
    if (d->nodes[c].kind == ZUX_ELEMENT)
      return c;
  return ZUX_NONE;
}

uint32_t zux_node_count(const zux_document *d) { return d ? d->n_nodes : 0u; }
uint32_t zux_name_count(const zux_document *d) { return d ? d->n_names : 0u; }
uint32_t zux_attr_total(const zux_document *d) { return d ? d->n_attrs : 0u; }
size_t zux_document_bytes(const zux_document *d) { return d ? d->mem : 0u; }

int
zux_node_kind(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  return n ? (int)n->kind : -1;
}

zux_id
zux_parent(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  return n ? n->parent : ZUX_NONE;
}

zux_id
zux_first_child(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  return n ? n->first_child : ZUX_NONE;
}

zux_id
zux_next_sibling(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  return n ? n->next_sibling : ZUX_NONE;
}

zux_name
zux_node_name(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  zux_name out;
  const zux_qname *q;
  memset(&out, 0, sizeof(out));
  out.uri = out.local = out.prefix = ZUX_EMPTY_STR;
  if (n == NULL || n->name == ZUX_NONE || n->name >= d->n_names)
    return out;
  q = &d->names[n->name];
  out.uri.ptr = d->strings + q->uri_off;
  out.uri.len = q->uri_len;
  out.local.ptr = d->strings + q->local_off;
  out.local.len = q->local_len;
  out.prefix.ptr = d->strings + q->prefix_off;
  out.prefix.len = q->prefix_len;
  return out;
}

zux_str
zux_node_text(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  zux_str s = ZUX_EMPTY_STR;
  if (n == NULL)
    return s;
  s.ptr = d->strings + n->str_off;
  s.len = n->str_len;
  return s;
}

uint32_t
zux_attr_count(const zux_document *d, zux_id id) {
  const zux_node *n = node_at(d, id);
  return n ? n->attr_count : 0u;
}

zux_attr
zux_attr_at(const zux_document *d, zux_id id, uint32_t i) {
  const zux_node *n = node_at(d, id);
  zux_attr out;
  const zux_attr_slot *s;
  const zux_qname *q;
  memset(&out, 0, sizeof(out));
  out.name.uri = out.name.local = out.name.prefix = out.value = ZUX_EMPTY_STR;
  if (n == NULL || i >= n->attr_count)
    return out;
  s = &d->attrs[n->attr_start + i];
  if (s->name < d->n_names) {
    q = &d->names[s->name];
    out.name.uri.ptr = d->strings + q->uri_off;
    out.name.uri.len = q->uri_len;
    out.name.local.ptr = d->strings + q->local_off;
    out.name.local.len = q->local_len;
    out.name.prefix.ptr = d->strings + q->prefix_off;
    out.name.prefix.len = q->prefix_len;
  }
  out.value.ptr = d->strings + s->val_off;
  out.value.len = s->val_len;
  return out;
}

zux_str
zux_doc_version(const zux_document *d) {
  zux_str s = ZUX_EMPTY_STR;
  if (d == NULL || d->version_len == 0)
    return s;
  s.ptr = d->strings + d->version_off;
  s.len = d->version_len;
  return s;
}

zux_str
zux_doc_encoding(const zux_document *d) {
  zux_str s = ZUX_EMPTY_STR;
  if (d == NULL || d->encoding_len == 0)
    return s;
  s.ptr = d->strings + d->encoding_off;
  s.len = d->encoding_len;
  return s;
}

int
zux_doc_standalone(const zux_document *d) { return d ? d->standalone : -1; }
