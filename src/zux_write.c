/* zuxml: XML serialization.
 *
 * In v1 because it is the round-trip test oracle (design section 13): parse ->
 * serialize -> parse must yield structurally identical trees over the whole
 * corpus, which is worth far more than the code costs.
 *
 * Guarantees element order, attribute order, text order, mixed-content
 * interleaving and namespace semantics. Does NOT preserve quote style,
 * inter-attribute whitespace, CDATA boundaries, entity spelling or
 * empty-element spelling: zuxml is not a lossless source editor.
 *
 * Serialization is iterative, for the same reason construction and teardown
 * are: a hostile 100k-deep document must not be able to recurse the C stack.
 */

#include <stdlib.h>
#include <string.h>

#include "zux.h"

typedef struct {
  char *p;
  size_t n, cap;
  int oom;
} obuf;

static int
ob_reserve(obuf *b, size_t extra) {
  size_t need = b->n + extra;
  if (need <= b->cap)
    return 1;
  {
    size_t cap = b->cap ? b->cap : 256;
    char *q;
    while (cap < need)
      cap *= 2;
    q = (char *)realloc(b->p, cap);
    if (q == NULL) {
      b->oom = 1;
      return 0;
    }
    b->p = q;
    b->cap = cap;
  }
  return 1;
}

static void
ob_put(obuf *b, const char *s, size_t n) {
  if (n == 0 || ! ob_reserve(b, n))
    return;
  memcpy(b->p + b->n, s, n);
  b->n += n;
}

static void
ob_cstr(obuf *b, const char *s) {
  ob_put(b, s, strlen(s));
}

static void
ob_str(obuf *b, zux_str s) {
  ob_put(b, s.ptr, s.len);
}

/* ---- escaping ----------------------------------------------------------
 * Context-correct, not blanket. Escaping more than necessary is legal but
 * makes output noisy and diffs unreadable; escaping less is a correctness
 * bug. See design section 13.
 * ---------------------------------------------------------------------- */

static void
esc_text(obuf *b, zux_str s) {
  size_t i;
  for (i = 0; i < s.len; i++) {
    char c = s.ptr[i];
    if (c == '&')
      ob_cstr(b, "&amp;");
    else if (c == '<')
      ob_cstr(b, "&lt;");
    else if (c == '>' && i >= 2 && s.ptr[i - 1] == ']' && s.ptr[i - 2] == ']')
      /* Only where it would close a CDATA section; a bare '>' is legal text. */
      ob_cstr(b, "&gt;");
    else
      ob_put(b, &c, 1);
  }
}

static void
esc_attr(obuf *b, zux_str s) {
  size_t i;
  for (i = 0; i < s.len; i++) {
    char c = s.ptr[i];
    switch (c) {
    case '&': ob_cstr(b, "&amp;"); break;
    case '<': ob_cstr(b, "&lt;"); break;
    case '"': ob_cstr(b, "&quot;"); break;
    /* Whitespace must become character references: attribute-value
     * normalization would otherwise turn a literal tab or newline into a
     * space on re-parse, silently breaking the round trip. */
    case '\t': ob_cstr(b, "&#9;"); break;
    case '\n': ob_cstr(b, "&#10;"); break;
    case '\r': ob_cstr(b, "&#13;"); break;
    default: ob_put(b, &c, 1); break;
    }
  }
}

/* ---- namespace scope ---------------------------------------------------
 * Declarations are re-emitted from the node's namespace fields at the point
 * they are first needed, since parsing does not retain the original xmlns
 * attributes.
 * ---------------------------------------------------------------------- */

typedef struct {
  zux_str prefix, uri;
} nsbind;

typedef struct {
  nsbind *v;
  size_t n, cap;
} nsscope;

static int
ns_push(nsscope *s, zux_str prefix, zux_str uri) {
  if (s->n == s->cap) {
    size_t cap = s->cap ? s->cap * 2 : 16;
    nsbind *v = (nsbind *)realloc(s->v, cap * sizeof(nsbind));
    if (v == NULL)
      return 0;
    s->v = v;
    s->cap = cap;
  }
  s->v[s->n].prefix = prefix;
  s->v[s->n].uri = uri;
  s->n++;
  return 1;
}

static int
str_eq(zux_str a, zux_str b) {
  return a.len == b.len && (a.len == 0 || memcmp(a.ptr, b.ptr, a.len) == 0);
}

/* Innermost binding for a prefix, or NULL if unbound. */
static const nsbind *
ns_lookup(const nsscope *s, zux_str prefix) {
  size_t i;
  for (i = s->n; i > 0; i--)
    if (str_eq(s->v[i - 1].prefix, prefix))
      return &s->v[i - 1];
  return NULL;
}

static void
emit_decl(obuf *b, zux_str prefix, zux_str uri) {
  if (prefix.len == 0) {
    ob_cstr(b, " xmlns=\"");
  } else {
    ob_cstr(b, " xmlns:");
    ob_str(b, prefix);
    ob_cstr(b, "=\"");
  }
  esc_attr(b, uri);
  ob_cstr(b, "\"");
}

static void
emit_qname(obuf *b, zux_name nm) {
  if (nm.prefix.len) {
    ob_str(b, nm.prefix);
    ob_cstr(b, ":");
  }
  ob_str(b, nm.local);
}

/* ---- serialization ----------------------------------------------------- */

typedef struct {
  zux_id id;
  int closing;    /* 0 = open this node, 1 = emit its end tag */
  size_t ns_mark; /* scope depth to restore when closing */
} frame;

typedef struct {
  frame *v;
  size_t n, cap;
} fstack;

static int
fs_push(fstack *s, zux_id id, int closing, size_t mark) {
  if (s->n == s->cap) {
    size_t cap = s->cap ? s->cap * 2 : 64;
    frame *v = (frame *)realloc(s->v, cap * sizeof(frame));
    if (v == NULL)
      return 0;
    s->v = v;
    s->cap = cap;
  }
  s->v[s->n].id = id;
  s->v[s->n].closing = closing;
  s->v[s->n].ns_mark = mark;
  s->n++;
  return 1;
}

zux_status
zux_serialize(const zux_document *d, zux_id id, char **out, size_t *out_len) {
  obuf b;
  nsscope ns;
  fstack st;
  zux_status rc = ZUX_OK;

  if (d == NULL || out == NULL)
    return ZUX_ERR_INVALID_ARGUMENT;
  *out = NULL;
  if (out_len != NULL)
    *out_len = 0;

  memset(&b, 0, sizeof(b));
  memset(&ns, 0, sizeof(ns));
  memset(&st, 0, sizeof(st));

  if (! fs_push(&st, id, 0, 0)) {
    rc = ZUX_ERR_MEMORY;
    goto done;
  }

  while (st.n > 0) {
    frame f = st.v[--st.n];
    int kind = zux_node_kind(d, f.id);

    if (f.closing) {
      ob_cstr(&b, "</");
      emit_qname(&b, zux_node_name(d, f.id));
      ob_cstr(&b, ">");
      ns.n = f.ns_mark;
      continue;
    }

    switch (kind) {
    case ZUX_TEXT:
      esc_text(&b, zux_node_text(d, f.id));
      break;

    case ZUX_COMMENT: {
      zux_str t = zux_node_text(d, f.id);
      size_t i;
      /* "--" cannot appear in a comment and cannot be escaped. */
      for (i = 1; i < t.len; i++)
        if (t.ptr[i] == '-' && t.ptr[i - 1] == '-') {
          rc = ZUX_ERR_INVALID_XML;
          goto done;
        }
      if (t.len && t.ptr[t.len - 1] == '-') {
        rc = ZUX_ERR_INVALID_XML;
        goto done;
      }
      ob_cstr(&b, "<!--");
      ob_str(&b, t);
      ob_cstr(&b, "-->");
      break;
    }

    case ZUX_PI: {
      zux_str t = zux_node_text(d, f.id);
      size_t i;
      /* "?>" cannot appear in PI data and cannot be escaped. */
      for (i = 1; i < t.len; i++)
        if (t.ptr[i] == '>' && t.ptr[i - 1] == '?') {
          rc = ZUX_ERR_INVALID_XML;
          goto done;
        }
      ob_cstr(&b, "<?");
      ob_str(&b, zux_node_name(d, f.id).local);
      if (t.len) {
        ob_cstr(&b, " ");
        ob_str(&b, t);
      }
      ob_cstr(&b, "?>");
      break;
    }

    case ZUX_DOCUMENT:
    case ZUX_ELEMENT:
    default: {
      size_t mark = ns.n;
      zux_id c;
      zux_id kids[64];
      zux_id *arr = kids;
      zux_id *big = NULL;
      size_t nk = 0, cap = 64, j;

      if (kind == ZUX_ELEMENT) {
        zux_name nm = zux_node_name(d, f.id);
        uint32_t ai, na = zux_attr_count(d, f.id);
        const nsbind *bound;

        ob_cstr(&b, "<");
        emit_qname(&b, nm);

        /* The element's own binding, if the innermost one differs. */
        bound = ns_lookup(&ns, nm.prefix);
        if (nm.uri.len > 0) {
          if (bound == NULL || ! str_eq(bound->uri, nm.uri)) {
            emit_decl(&b, nm.prefix, nm.uri);
            if (! ns_push(&ns, nm.prefix, nm.uri)) { rc = ZUX_ERR_MEMORY; goto done; }
          }
        } else if (nm.prefix.len == 0 && bound != NULL && bound->uri.len > 0) {
          /* An unqualified element inside a default namespace needs an
           * explicit reset, or re-parsing would put it in that namespace. */
          zux_str empty;
          empty.ptr = "";
          empty.len = 0;
          emit_decl(&b, empty, empty);
          if (! ns_push(&ns, empty, empty)) { rc = ZUX_ERR_MEMORY; goto done; }
        }

        /* Bindings needed by namespaced attributes. */
        for (ai = 0; ai < na; ai++) {
          zux_attr a = zux_attr_at(d, f.id, ai);
          if (a.name.uri.len == 0 || a.name.prefix.len == 0)
            continue;
          bound = ns_lookup(&ns, a.name.prefix);
          if (bound == NULL || ! str_eq(bound->uri, a.name.uri)) {
            emit_decl(&b, a.name.prefix, a.name.uri);
            if (! ns_push(&ns, a.name.prefix, a.name.uri)) { rc = ZUX_ERR_MEMORY; goto done; }
          }
        }

        for (ai = 0; ai < na; ai++) {
          zux_attr a = zux_attr_at(d, f.id, ai);
          ob_cstr(&b, " ");
          emit_qname(&b, a.name);
          ob_cstr(&b, "=\"");
          esc_attr(&b, a.value);
          ob_cstr(&b, "\"");
        }
      }

      for (c = zux_first_child(d, f.id); c != ZUX_NONE;
           c = zux_next_sibling(d, c)) {
        if (nk == cap) {
          cap *= 2;
          {
            zux_id *nb = (zux_id *)realloc(big, cap * sizeof(zux_id));
            if (nb == NULL) { free(big); rc = ZUX_ERR_MEMORY; goto done; }
            if (big == NULL) memcpy(nb, kids, nk * sizeof(zux_id));
            big = nb;
            arr = big;
          }
        }
        arr[nk++] = c;
      }

      if (kind == ZUX_ELEMENT) {
        if (nk == 0) {
          ob_cstr(&b, "/>");
          ns.n = mark;
          free(big);
          break;
        }
        ob_cstr(&b, ">");
        if (! fs_push(&st, f.id, 1, mark)) { free(big); rc = ZUX_ERR_MEMORY; goto done; }
      }
      /* Push children reversed so they pop in document order. */
      for (j = nk; j > 0; j--)
        if (! fs_push(&st, arr[j - 1], 0, ns.n)) { free(big); rc = ZUX_ERR_MEMORY; goto done; }
      free(big);
      break;
    }
    }
  }

  if (b.oom) {
    rc = ZUX_ERR_MEMORY;
    goto done;
  }
  if (! ob_reserve(&b, 1)) {
    rc = ZUX_ERR_MEMORY;
    goto done;
  }
  b.p[b.n] = '\0';
  *out = b.p;
  if (out_len != NULL)
    *out_len = b.n;
  b.p = NULL;

done:
  free(b.p);
  free(ns.v);
  free(st.v);
  return rc;
}
