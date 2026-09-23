/* Consumes zuxml through the registered table, the way new C code is meant
 * to: zuxml.h is the only zuxml header included, no Expat header is, and
 * every call goes through zuxml_api_get(). Between them the entry points
 * below call all 26 members of the table.
 *
 * Handlers never call the R API -- a longjmp out of one would skip the
 * parser's cleanup -- so events are collected into plain C buffers and only
 * turned into R objects once the parse is over. */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ZUXML_DEFINE_API_GET
#include "zuxml.h"

/* ---- the table as zuxml 0.1.0 ships it, frozen ---------------------------
 * A consumer compiled against the 0.1.0 header has these offsets baked into
 * its object code, and R does not rebuild it when zuxml is upgraded. So every
 * later header must keep them: members are appended, never reordered or
 * removed (roadmap Stage 6, criterion 4). Each SAME_OFFSET line fails to
 * compile if the current header has moved that member. */
typedef struct {
  uint32_t struct_size;
  void (*options_init)(zux_options *);
  const char *(*status_string)(zux_status);
  zux_status (*parser_new)(zux_parser **, const zux_options *,
                           const zux_handlers *, void *);
  zux_status (*parser_feed)(zux_parser *, const void *, size_t);
  zux_status (*parser_finish)(zux_parser *);
  void (*parser_free)(zux_parser *);
  void (*parser_error)(const zux_parser *, zux_error *);
  zux_status (*tree_parse)(zux_document **, const void *, size_t,
                           const zux_options *, zux_error *);
  zux_status (*tree_begin)(zux_tree_builder **, const zux_options *);
  zux_status (*tree_feed)(zux_tree_builder *, const void *, size_t);
  zux_status (*tree_end)(zux_tree_builder *, zux_document **, zux_error *);
  void (*tree_error)(const zux_tree_builder *, zux_error *);
  void (*tree_abort)(zux_tree_builder *);
  void (*document_free)(zux_document *);
  zux_id (*root)(const zux_document *);
  uint32_t (*node_count)(const zux_document *);
  int (*node_kind)(const zux_document *, zux_id);
  zux_id (*parent)(const zux_document *, zux_id);
  zux_id (*first_child)(const zux_document *, zux_id);
  zux_id (*next_sibling)(const zux_document *, zux_id);
  zux_name (*node_name)(const zux_document *, zux_id);
  zux_str (*node_text)(const zux_document *, zux_id);
  uint32_t (*attr_count)(const zux_document *, zux_id);
  zux_attr (*attr_at)(const zux_document *, zux_id, uint32_t);
  zux_status (*serialize)(const zux_document *, zux_id, char **, size_t *);
  void (*set_message)(zux_error *, const char *);
} zuxml_api_0_1_0;

#define ZUXML_MEMBERS(X)                                                      \
  X(options_init) X(status_string) X(parser_new) X(parser_feed)               \
  X(parser_finish) X(parser_free) X(parser_error) X(tree_parse)               \
  X(tree_begin) X(tree_feed) X(tree_end) X(tree_error) X(tree_abort)          \
  X(document_free) X(root) X(node_count) X(node_kind) X(parent)               \
  X(first_child) X(next_sibling) X(node_name) X(node_text) X(attr_count)      \
  X(attr_at) X(serialize) X(set_message)

#define SAME_OFFSET(m)                                                        \
  typedef char same_offset_##m[offsetof(zuxml_api, m)                         \
                                       == offsetof(zuxml_api_0_1_0, m)        \
                                   ? 1                                        \
                                   : -1];
SAME_OFFSET(struct_size)
ZUXML_MEMBERS(SAME_OFFSET)
typedef char no_smaller_than_0_1_0
    [sizeof(zuxml_api) >= sizeof(zuxml_api_0_1_0) ? 1 : -1];

static const zuxml_api *
api_or_error(void) {
  const zuxml_api *api = zuxml_api_get();
  if (api == NULL)
    Rf_error("zuxmltable: could not obtain the zuxml API table");
  if (api->struct_size < sizeof(zuxml_api_0_1_0))
    Rf_error("zuxmltable: the running zuxml's table is older than 0.1.0's");
  return api;
}

/* ---- a growable byte buffer, malloc only --------------------------------- */
typedef struct {
  char *p;
  size_t n, cap;
  int oom;
} sbuf;

static void
sb_put(sbuf *b, const char *s, size_t n) {
  if (b->oom)
    return;
  if (b->n + n + 1 > b->cap) {
    size_t cap = b->cap ? b->cap : 256;
    char *q;
    while (cap < b->n + n + 1)
      cap *= 2;
    q = (char *)realloc(b->p, cap);
    if (q == NULL) {
      b->oom = 1;
      return;
    }
    b->p = q;
    b->cap = cap;
  }
  memcpy(b->p + b->n, s, n);
  b->n += n;
  b->p[b->n] = '\0';
}

static void
sb_str(sbuf *b, const char *s) {
  sb_put(b, s, strlen(s));
}

static void
sb_zstr(sbuf *b, zux_str s) {
  sb_put(b, s.ptr, s.len);
}

static void
sb_name(sbuf *b, zux_name nm) {
  sb_str(b, "{");
  sb_zstr(b, nm.uri);
  sb_str(b, "}");
  sb_zstr(b, nm.local);
  if (nm.prefix.len > 0) {
    sb_str(b, "~");
    sb_zstr(b, nm.prefix);
  }
}

static void
sb_uint(sbuf *b, unsigned long v) {
  char tmp[32];
  snprintf(tmp, sizeof(tmp), "%lu", v);
  sb_str(b, tmp);
}

/* Events are separated by '\n' in the log. Text can itself contain a
 * newline, so text and attribute values are written as a byte count then the
 * bytes, which keeps the log unambiguous without escaping. */
static void
sb_counted(sbuf *b, zux_str s) {
  sb_uint(b, (unsigned long)s.len);
  sb_str(b, ":");
  sb_zstr(b, s);
}

static SEXP
mk_string(const sbuf *b) {
  return Rf_ScalarString(
      Rf_mkCharLenCE(b->p ? b->p : "", b->p ? (int)b->n : 0, CE_UTF8));
}

static SEXP
named_list(int n, const char **names) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, n));
  int i;
  for (i = 0; i < n; i++)
    SET_STRING_ELT(nms, i, Rf_mkChar(names[i]));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}

/* ---- C_members ----------------------------------------------------------- */
SEXP
C_members(void) {
  const zuxml_api *api = api_or_error();
  static const char *member_names[] = {
#define NAME(m) #m,
      ZUXML_MEMBERS(NAME)
#undef NAME
  };
  static const char *names[] = {"struct_size", "header_size", "present"};
  int n = (int)(sizeof(member_names) / sizeof(member_names[0]));
  int i = 0;
  SEXP out = PROTECT(named_list(3, names));
  SEXP present = PROTECT(Rf_allocVector(LGLSXP, n));
  SEXP pn = PROTECT(Rf_allocVector(STRSXP, n));
#define CHECK(m)                                                              \
  LOGICAL(present)[i] = ZUXML_API_HAS(api, m) && api->m != NULL;             \
  SET_STRING_ELT(pn, i, Rf_mkChar(member_names[i]));                         \
  i++;
  ZUXML_MEMBERS(CHECK)
#undef CHECK
  Rf_setAttrib(present, R_NamesSymbol, pn);
  SET_VECTOR_ELT(out, 0, Rf_ScalarReal((double)api->struct_size));
  SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)sizeof(zuxml_api)));
  SET_VECTOR_ELT(out, 2, present);
  UNPROTECT(3);
  return out;
}

/* ---- C_events: the streaming seam ---------------------------------------- */
static zux_status
on_start(void *ctx, const zux_name *name, const zux_attr *attrs,
         size_t n_attrs) {
  sbuf *b = (sbuf *)ctx;
  size_t i;
  sb_str(b, "start ");
  sb_name(b, *name);
  for (i = 0; i < n_attrs; i++) {
    sb_str(b, " @");
    sb_name(b, attrs[i].name);
    sb_str(b, "=");
    sb_counted(b, attrs[i].value);
  }
  sb_str(b, "\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static zux_status
on_end(void *ctx, const zux_name *name) {
  sbuf *b = (sbuf *)ctx;
  sb_str(b, "end ");
  sb_name(b, *name);
  sb_str(b, "\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static zux_status
on_text(void *ctx, zux_str t) {
  sbuf *b = (sbuf *)ctx;
  /* Borrowed and not NUL-terminated: copied by length, never kept. */
  sb_str(b, "text ");
  sb_counted(b, t);
  sb_str(b, "\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static zux_status
on_comment(void *ctx, zux_str t) {
  sbuf *b = (sbuf *)ctx;
  sb_str(b, "comment ");
  sb_counted(b, t);
  sb_str(b, "\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static zux_status
on_pi(void *ctx, zux_str target, zux_str data) {
  sbuf *b = (sbuf *)ctx;
  sb_str(b, "pi ");
  sb_counted(b, target);
  sb_str(b, " ");
  sb_counted(b, data);
  sb_str(b, "\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static zux_status
on_decl(void *ctx, zux_str version, zux_str encoding, int standalone) {
  sbuf *b = (sbuf *)ctx;
  sb_str(b, "decl ");
  sb_counted(b, version);
  sb_str(b, " ");
  sb_counted(b, encoding);
  sb_str(b, standalone > 0 ? " yes\n" : standalone == 0 ? " no\n" : " -\n");
  return b->oom ? ZUX_ERR_MEMORY : ZUX_OK;
}

static size_t
chunk_of(SEXP chunk_, size_t total) {
  int k = Rf_asInteger(chunk_);
  if (k == NA_INTEGER || k <= 0)
    return total > 0 ? total : 1;
  return (size_t)k;
}

SEXP
C_events(SEXP x, SEXP chunk_) {
  static const char *names[] = {"status", "message", "line", "column",
                                "events"};
  const zuxml_api *api = api_or_error();
  const unsigned char *data = RAW(x);
  size_t total = (size_t)Rf_xlength(x), chunk = chunk_of(chunk_, total), pos;
  zux_options opt;
  zux_handlers h;
  zux_parser *p = NULL;
  zux_error err;
  zux_status st;
  sbuf log = {NULL, 0, 0, 0};
  SEXP out;

  memset(&h, 0, sizeof(h));
  h.start_element = on_start;
  h.end_element = on_end;
  h.text = on_text;
  h.comment = on_comment;
  h.pi = on_pi;
  h.xml_decl = on_decl;
  api->options_init(&opt);
  memset(&err, 0, sizeof(err));

  st = api->parser_new(&p, &opt, &h, &log);
  if (st == ZUX_OK) {
    for (pos = 0; pos < total; pos += chunk) {
      size_t k = total - pos < chunk ? total - pos : chunk;
      st = api->parser_feed(p, data + pos, k);
      if (st != ZUX_OK)
        break;
    }
    if (st == ZUX_OK)
      st = api->parser_finish(p);
    api->parser_error(p, &err);
    api->parser_free(p);
  } else {
    err.status = st;
    api->set_message(&err, api->status_string(st));
  }
  if (st == ZUX_DONE)
    st = ZUX_OK;

  out = PROTECT(named_list(5, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(api->status_string(st)));
  SET_VECTOR_ELT(out, 1, Rf_mkString(err.message));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)err.line));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)err.column));
  SET_VECTOR_ELT(out, 4, mk_string(&log));
  free(log.p);
  UNPROTECT(1);
  return out;
}

/* ---- C_tree: the tree builder and every accessor -------------------------- */

/* Preorder walk with an explicit stack, emitting one line per node. Returns
 * non-zero if a contract the header states does not hold: parent() must
 * agree with the first_child()/next_sibling() links, and document strings
 * must be NUL-terminated. */
static int
dump_tree(const zuxml_api *api, const zux_document *d, sbuf *b) {
  zux_id *stack = NULL, *kids = NULL;
  size_t top = 0, cap = 0, nk, kcap = 0, i;
  int broken = 0;
  zux_id id, c;

  if (d == NULL)
    return 0;
  cap = 64;
  stack = (zux_id *)malloc(cap * sizeof(zux_id));
  if (stack == NULL) {
    b->oom = 1;
    return 0;
  }
  stack[top++] = api->root(d);
  while (top > 0 && !b->oom) {
    int kind;
    uint32_t a, na;
    id = stack[--top];
    kind = api->node_kind(d, id);
    sb_uint(b, (unsigned long)kind);
    if (kind == ZUX_ELEMENT || kind == ZUX_PI) {
      sb_str(b, " ");
      sb_name(b, api->node_name(d, id));
    }
    if (kind == ZUX_TEXT || kind == ZUX_COMMENT || kind == ZUX_PI) {
      /* Document strings are owned by the document and NUL-terminated. */
      zux_str t = api->node_text(d, id);
      if (t.ptr != NULL && t.ptr[t.len] != '\0')
        broken = 1;
      sb_str(b, " ");
      sb_counted(b, t);
    }
    na = api->attr_count(d, id);
    for (a = 0; a < na; a++) {
      zux_attr at = api->attr_at(d, id, a);
      sb_str(b, " @");
      sb_name(b, at.name);
      sb_str(b, "=");
      sb_counted(b, at.value);
    }
    sb_str(b, "\n");

    nk = 0;
    for (c = api->first_child(d, id); c != ZUX_NONE;
         c = api->next_sibling(d, c)) {
      if (api->parent(d, c) != id)
        broken = 1;
      if (nk == kcap) {
        size_t ncap = kcap ? kcap * 2 : 16;
        zux_id *q = (zux_id *)realloc(kids, ncap * sizeof(zux_id));
        if (q == NULL) {
          b->oom = 1;
          break;
        }
        kids = q;
        kcap = ncap;
      }
      kids[nk++] = c;
    }
    if (top + nk > cap) {
      size_t ncap = cap;
      zux_id *q;
      while (ncap < top + nk)
        ncap *= 2;
      q = (zux_id *)realloc(stack, ncap * sizeof(zux_id));
      if (q == NULL) {
        b->oom = 1;
        break;
      }
      stack = q;
      cap = ncap;
    }
    for (i = nk; i > 0; i--)
      stack[top++] = kids[i - 1];
  }
  free(kids);
  free(stack);
  return broken;
}

static void
serialize_into(const zuxml_api *api, const zux_document *d, sbuf *b) {
  char *s = NULL;
  size_t len = 0;
  if (d == NULL)
    return;
  if (api->serialize(d, api->root(d), &s, &len) == ZUX_OK && s != NULL) {
    /* Owned by the caller, NUL-terminated, len excludes the terminator. */
    if (s[len] != '\0')
      b->oom = 1;
    sb_put(b, s, len);
  }
  free(s);
}

SEXP
C_tree(SEXP x, SEXP chunk_) {
  static const char *names[] = {"status",     "message",    "line",
                                "column",     "node_count", "dump",
                                "dump_whole", "serialized", "serialized_whole",
                                "consistent"};
  const zuxml_api *api = api_or_error();
  const unsigned char *data = RAW(x);
  size_t total = (size_t)Rf_xlength(x), chunk = chunk_of(chunk_, total), pos;
  zux_options opt;
  zux_tree_builder *tb = NULL;
  zux_document *doc = NULL, *whole = NULL;
  zux_error err, err_whole;
  zux_status st;
  sbuf dump = {NULL, 0, 0, 0}, dump_whole = {NULL, 0, 0, 0};
  sbuf ser = {NULL, 0, 0, 0}, ser_whole = {NULL, 0, 0, 0};
  int broken = 0;
  double n_nodes = 0;
  SEXP out;

  api->options_init(&opt);
  memset(&err, 0, sizeof(err));
  memset(&err_whole, 0, sizeof(err_whole));

  /* Incrementally: tree_begin, tree_feed per chunk, then tree_end -- or, on
   * a failed feed, tree_error for the position and tree_abort to release the
   * builder, which tree_end would otherwise have consumed. */
  st = api->tree_begin(&tb, &opt);
  if (st == ZUX_OK) {
    for (pos = 0; pos < total; pos += chunk) {
      size_t k = total - pos < chunk ? total - pos : chunk;
      st = api->tree_feed(tb, data + pos, k);
      if (st != ZUX_OK)
        break;
    }
    if (st == ZUX_OK) {
      st = api->tree_end(tb, &doc, &err);
    } else {
      api->tree_error(tb, &err);
      api->tree_abort(tb);
    }
    tb = NULL;
  }
  if (st != ZUX_OK && err.message[0] == '\0')
    api->set_message(&err, api->status_string(st));

  /* Whole, for comparison. */
  (void)api->tree_parse(&whole, data, total, &opt, &err_whole);

  if (doc != NULL) {
    n_nodes = (double)api->node_count(doc);
    broken |= dump_tree(api, doc, &dump);
    serialize_into(api, doc, &ser);
    api->document_free(doc);
  }
  if (whole != NULL) {
    broken |= dump_tree(api, whole, &dump_whole);
    serialize_into(api, whole, &ser_whole);
    api->document_free(whole);
  }

  out = PROTECT(named_list(10, names));
  SET_VECTOR_ELT(out, 0, Rf_mkString(api->status_string(st)));
  SET_VECTOR_ELT(out, 1, Rf_mkString(err.message));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)err.line));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)err.column));
  SET_VECTOR_ELT(out, 4, Rf_ScalarReal(n_nodes));
  SET_VECTOR_ELT(out, 5, mk_string(&dump));
  SET_VECTOR_ELT(out, 6, mk_string(&dump_whole));
  SET_VECTOR_ELT(out, 7, mk_string(&ser));
  SET_VECTOR_ELT(out, 8, mk_string(&ser_whole));
  SET_VECTOR_ELT(out, 9,
                 Rf_ScalarLogical(!broken && !dump.oom && !dump_whole.oom
                                  && !ser.oom && !ser_whole.oom));
  free(dump.p);
  free(dump_whole.p);
  free(ser.p);
  free(ser_whole.p);
  UNPROTECT(1);
  return out;
}

/* ---- C_abort: releasing a live builder ----------------------------------- */
SEXP
C_abort(SEXP x, SEXP after_) {
  const zuxml_api *api = api_or_error();
  zux_options opt;
  zux_tree_builder *tb = NULL;
  size_t total = (size_t)Rf_xlength(x);
  int after = Rf_asInteger(after_);
  size_t k = after == NA_INTEGER || after < 0 ? 0 : (size_t)after;
  zux_status st;

  if (k > total)
    k = total;
  api->options_init(&opt);
  st = api->tree_begin(&tb, &opt);
  if (st != ZUX_OK)
    return Rf_mkString(api->status_string(st));
  st = api->tree_feed(tb, RAW(x), k);
  api->tree_abort(tb);
  return Rf_mkString(api->status_string(st));
}

/* ---- C_degrade: struct_size against an older zuxml ------------------------ */
SEXP
C_degrade(void) {
  static const char *names[] = {"real_has_set_message", "old_has_serialize",
                                "old_has_set_message", "message"};
  const zuxml_api *api = api_or_error();
  zuxml_api older = *api;
  zux_error e;
  SEXP out;

  /* A zuxml whose table ends just before set_message: everything up to
   * serialize is there, set_message is not. */
  older.struct_size = (uint32_t)offsetof(zuxml_api, set_message);

  memset(&e, 0, sizeof(e));
  if (ZUXML_API_HAS(&older, set_message)) {
    older.set_message(&e, "called past the end of the table");
  } else {
    /* The fallback such a consumer has to carry. */
    strncpy(e.message, "fallback", sizeof(e.message) - 1);
  }

  out = PROTECT(named_list(4, names));
  SET_VECTOR_ELT(out, 0, Rf_ScalarLogical(ZUXML_API_HAS(api, set_message)));
  SET_VECTOR_ELT(out, 1, Rf_ScalarLogical(ZUXML_API_HAS(&older, serialize)));
  SET_VECTOR_ELT(out, 2,
                 Rf_ScalarLogical(ZUXML_API_HAS(&older, set_message)));
  SET_VECTOR_ELT(out, 3, Rf_mkString(e.message));
  UNPROTECT(1);
  return out;
}

static const R_CallMethodDef call_methods[] = {
    {"C_members", (DL_FUNC)&C_members, 0},
    {"C_events", (DL_FUNC)&C_events, 2},
    {"C_tree", (DL_FUNC)&C_tree, 2},
    {"C_abort", (DL_FUNC)&C_abort, 2},
    {"C_degrade", (DL_FUNC)&C_degrade, 0},
    {NULL, NULL, 0}};

void R_init_zuxmltable(DllInfo *dll);

void
R_init_zuxmltable(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
