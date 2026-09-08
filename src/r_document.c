/* zuxml: the R document and node API.
 *
 * A document is an external pointer with a finalizer. A node handle is an
 * integer vector carrying that pointer as an attribute, so a node and a
 * nodeset are the same object at different lengths (design section 6): one
 * allocation per handle, the document kept reachable by R's own GC tracing of
 * attributes, and every accessor naturally vectorized.
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include <string.h>

#include "zux.h"

static SEXP zux_doc_tag = NULL;

/* ---- document handle --------------------------------------------------- */

static void
doc_finalizer(SEXP xptr) {
  zux_document *d = (zux_document *)R_ExternalPtrAddr(xptr);
  if (d != NULL) {
    zux_document_free(d);
    R_ClearExternalPtr(xptr);
  }
}

static SEXP
doc_wrap(zux_document *d) {
  SEXP xptr;
  if (zux_doc_tag == NULL) {
    zux_doc_tag = Rf_install("zuxml_document_ptr");
    R_PreserveObject(zux_doc_tag);
  }
  xptr = PROTECT(R_MakeExternalPtr(d, zux_doc_tag, R_NilValue));
  R_RegisterCFinalizerEx(xptr, doc_finalizer, TRUE);
  UNPROTECT(1);
  return xptr;
}

static zux_document *
doc_ptr(SEXP xptr) {
  zux_document *d;
  if (TYPEOF(xptr) != EXTPTRSXP)
    Rf_error("zuxml: not a document handle");
  d = (zux_document *)R_ExternalPtrAddr(xptr);
  if (d == NULL)
    Rf_error("zuxml: this document has been released and can no longer be used");
  return d;
}

/* ---- parsing, interrupt- and unwind-safe -------------------------------- */

#define ZUX_FEED_CHUNK 65536

typedef struct {
  const unsigned char *data;
  size_t n;
  zux_options opt;
  zux_document *doc; /* owned until handed to an external pointer */
  zux_tree_builder *builder;
  zux_error err;
  zux_status st;
} parse_ctx;

/* Capture the parser's recorded position BEFORE tearing the builder down --
 * otherwise a failure part-way through a chunked feed loses its line, column
 * and byte offset, and the R condition reports 0. */
static void
zux_error_of_builder(parse_ctx *c) {
  if (c->builder == NULL)
    return;
  zux_tree_error(c->builder, &c->err);
  if (c->err.status == ZUX_OK) {
    c->err.status = c->st;
    c->err.message = zux_status_string(c->st);
  }
  zux_tree_abort(c->builder);
  c->builder = NULL;
}

/* Frees the in-flight document if R unwinds -- an interrupt during a long
 * parse must not leak the arena. Expat itself has no cleanup hook, which is
 * why no R API is ever called from inside a handler; interrupts are checked
 * only between feeds, at a safe boundary. */
static void
parse_cleanup(void *data, Rboolean jump) {
  parse_ctx *c = (parse_ctx *)data;
  if (! jump)
    return;
  if (c->builder != NULL) {
    zux_tree_abort(c->builder);
    c->builder = NULL;
  }
  if (c->doc != NULL) {
    zux_document_free(c->doc);
    c->doc = NULL;
  }
}

static SEXP
parse_body(void *data) {
  parse_ctx *c = (parse_ctx *)data;
  size_t pos;

  c->st = zux_tree_begin(&c->builder, &c->opt);
  if (c->st != ZUX_OK) {
    /* Failure before any parser exists -- e.g. max_memory too small for the
     * document node itself -- so there is no parser error to borrow. */
    c->err.status = c->st;
    c->err.message = zux_status_string(c->st);
    return R_NilValue;
  }

  /* Feed in bounded chunks so that R_CheckUserInterrupt() has a safe call
   * site BETWEEN feeds. It must never be called from inside an Expat
   * handler: a longjmp out of one bypasses XML_ParserFree, and Expat has no
   * cleanup hook. If the interrupt fires here, parse_cleanup() runs and
   * releases the partially built document. */
  for (pos = 0; pos < c->n; pos += ZUX_FEED_CHUNK) {
    size_t k = c->n - pos < ZUX_FEED_CHUNK ? c->n - pos : ZUX_FEED_CHUNK;
    R_CheckUserInterrupt();
    c->st = zux_tree_feed(c->builder, c->data + pos, k);
    if (c->st != ZUX_OK)
      break;
  }
  if (c->st == ZUX_OK) {
    c->st = zux_tree_end(c->builder, &c->doc, &c->err);
    c->builder = NULL;
  } else {
    zux_error_of_builder(c);
  }
  return R_NilValue;
}

static SEXP
opt_get(SEXP opts, const char *name) {
  SEXP nms = Rf_getAttrib(opts, R_NamesSymbol);
  R_xlen_t i;
  if (nms == R_NilValue)
    return R_NilValue;
  for (i = 0; i < Rf_xlength(opts); i++)
    if (strcmp(CHAR(STRING_ELT(nms, i)), name) == 0)
      return VECTOR_ELT(opts, i);
  return R_NilValue;
}

static size_t
opt_size(SEXP opts, const char *name, size_t fallback) {
  SEXP v = opt_get(opts, name);
  double d;
  if (v == R_NilValue || Rf_xlength(v) < 1)
    return fallback;
  d = Rf_asReal(v);
  if (!(d > 0) || !R_FINITE(d))
    return fallback;
  return (size_t)d;
}

static int
opt_flag(SEXP opts, const char *name, int fallback) {
  SEXP v = opt_get(opts, name);
  if (v == R_NilValue || Rf_xlength(v) < 1)
    return fallback;
  return Rf_asLogical(v) == TRUE ? 1 : 0;
}

SEXP
C_zux_parse(SEXP x, SEXP opts) {
  parse_ctx c;
  SEXP cont, out, nms;

  if (TYPEOF(x) != RAWSXP)
    Rf_error("zuxml: expected a raw vector");

  memset(&c, 0, sizeof(c));
  zux_options_init(&c.opt);
  c.opt.max_depth = (uint32_t)opt_size(opts, "max_depth", c.opt.max_depth);
  c.opt.max_nodes = (uint32_t)opt_size(opts, "max_nodes", c.opt.max_nodes);
  c.opt.max_attrs = (uint32_t)opt_size(opts, "max_attrs", c.opt.max_attrs);
  c.opt.max_text = opt_size(opts, "max_text", c.opt.max_text);
  c.opt.max_memory = opt_size(opts, "max_memory", c.opt.max_memory);
  c.opt.allow_doctype = opt_flag(opts, "allow_doctype", c.opt.allow_doctype);
  c.opt.keep_comments = opt_flag(opts, "comments", c.opt.keep_comments);
  c.opt.keep_pis = opt_flag(opts, "pis", c.opt.keep_pis);
  {
    SEXP enc = opt_get(opts, "encoding");
    if (enc != R_NilValue && TYPEOF(enc) == STRSXP && Rf_xlength(enc) == 1
        && STRING_ELT(enc, 0) != NA_STRING)
      c.opt.encoding = CHAR(STRING_ELT(enc, 0));
  }
  c.data = RAW(x);
  c.n = (size_t)Rf_xlength(x);

  cont = PROTECT(R_MakeUnwindCont());
  R_UnwindProtect(parse_body, &c, parse_cleanup, &c, cont);
  UNPROTECT(1);

  out = PROTECT(Rf_allocVector(VECSXP, 7));
  SET_VECTOR_ELT(out, 0, Rf_mkString(zux_status_string(
                             c.st != ZUX_OK ? c.st : c.err.status)));
  SET_VECTOR_ELT(out, 1,
                 c.doc == NULL ? R_NilValue : doc_wrap(c.doc));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)c.err.line));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)c.err.column));
  SET_VECTOR_ELT(out, 4, Rf_ScalarReal((double)c.err.byte_offset));
  SET_VECTOR_ELT(out, 5,
                 Rf_mkString(c.err.message == NULL ? "" : c.err.message));
  SET_VECTOR_ELT(out, 6, Rf_ScalarInteger((int)(c.st != ZUX_OK ? c.st
                                                              : c.err.status)));
  nms = PROTECT(Rf_allocVector(STRSXP, 7));
  SET_STRING_ELT(nms, 0, Rf_mkChar("status"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("doc"));
  SET_STRING_ELT(nms, 2, Rf_mkChar("line"));
  SET_STRING_ELT(nms, 3, Rf_mkChar("column"));
  SET_STRING_ELT(nms, 4, Rf_mkChar("byte_offset"));
  SET_STRING_ELT(nms, 5, Rf_mkChar("message"));
  SET_STRING_ELT(nms, 6, Rf_mkChar("code"));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}

/* ---- helpers ----------------------------------------------------------- */

static SEXP
mk_utf8(zux_str s) {
  return Rf_mkCharLenCE(s.ptr, (int)s.len, CE_UTF8);
}

static int
name_matches(zux_name nm, SEXP local, SEXP uri) {
  if (local != R_NilValue) {
    const char *want = CHAR(STRING_ELT(local, 0));
    size_t wl = strlen(want);
    if (wl != nm.local.len || memcmp(want, nm.local.ptr, wl) != 0)
      return 0;
  }
  if (uri != R_NilValue) {
    if (STRING_ELT(uri, 0) == NA_STRING) {
      /* ns = NA means "in no namespace at all". */
      if (nm.uri.len != 0)
        return 0;
    } else {
      const char *want = CHAR(STRING_ELT(uri, 0));
      size_t wl = strlen(want);
      if (wl != nm.uri.len || memcmp(want, nm.uri.ptr, wl) != 0)
        return 0;
    }
  }
  return 1;
}

/* Growable integer result, so every traversal returns one flat nodeset. */
typedef struct {
  int *v;
  size_t n, cap;
} idbuf;

static void
idbuf_add(idbuf *b, zux_id id) {
  if (b->n == b->cap) {
    size_t cap = b->cap ? b->cap * 2 : 32;
    int *p = (int *)R_alloc(cap, sizeof(int));
    if (b->v != NULL)
      memcpy(p, b->v, b->n * sizeof(int));
    b->v = p;
    b->cap = cap;
  }
  b->v[b->n++] = (int)id;
}

static SEXP
idbuf_sexp(idbuf *b) {
  SEXP out = Rf_allocVector(INTSXP, (R_xlen_t)b->n);
  if (b->n > 0)
    memcpy(INTEGER(out), b->v, b->n * sizeof(int));
  return out;
}

static zux_id
check_id(const zux_document *d, int v) {
  if (v == NA_INTEGER || v < 0 || (uint32_t)v >= zux_node_count(d))
    Rf_error("zuxml: invalid node reference");
  return (zux_id)v;
}

/* ---- accessors --------------------------------------------------------- */

SEXP
C_zux_root(SEXP xp) {
  zux_document *d = doc_ptr(xp);
  zux_id r = zux_root(d);
  return Rf_ScalarInteger(r == ZUX_NONE ? NA_INTEGER : (int)r);
}

SEXP
C_zux_node_info(SEXP xp, SEXP ids, SEXP what) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  const char *w = CHAR(STRING_ELT(what, 0));
  SEXP out;

  if (strcmp(w, "kind") == 0) {
    out = PROTECT(Rf_allocVector(STRSXP, n));
    for (i = 0; i < n; i++) {
      zux_id id = check_id(d, INTEGER(ids)[i]);
      int k = zux_node_kind(d, id);
      const char *s = k == ZUX_DOCUMENT  ? "document"
                      : k == ZUX_ELEMENT ? "element"
                      : k == ZUX_TEXT    ? "text"
                      : k == ZUX_COMMENT ? "comment"
                                         : "pi";
      SET_STRING_ELT(out, i, Rf_mkChar(s));
    }
    UNPROTECT(1);
    return out;
  }

  out = PROTECT(Rf_allocVector(STRSXP, n));
  for (i = 0; i < n; i++) {
    zux_id id = check_id(d, INTEGER(ids)[i]);
    zux_name nm = zux_node_name(d, id);
    int is_named = zux_node_kind(d, id) == ZUX_ELEMENT
                   || zux_node_kind(d, id) == ZUX_PI;
    if (! is_named) {
      SET_STRING_ELT(out, i, NA_STRING);
      continue;
    }
    if (strcmp(w, "local") == 0) {
      SET_STRING_ELT(out, i, mk_utf8(nm.local));
    } else if (strcmp(w, "uri") == 0) {
      SET_STRING_ELT(out, i,
                     nm.uri.len ? mk_utf8(nm.uri) : NA_STRING);
    } else if (strcmp(w, "prefix") == 0) {
      SET_STRING_ELT(out, i,
                     nm.prefix.len ? mk_utf8(nm.prefix) : NA_STRING);
    } else { /* qualified name */
      if (nm.prefix.len) {
        char buf[512];
        size_t need = nm.prefix.len + 1 + nm.local.len;
        if (need < sizeof(buf)) {
          memcpy(buf, nm.prefix.ptr, nm.prefix.len);
          buf[nm.prefix.len] = ':';
          memcpy(buf + nm.prefix.len + 1, nm.local.ptr, nm.local.len);
          SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int)need, CE_UTF8));
        } else {
          SET_STRING_ELT(out, i, mk_utf8(nm.local));
        }
      } else {
        SET_STRING_ELT(out, i, mk_utf8(nm.local));
      }
    }
  }
  UNPROTECT(1);
  return out;
}

SEXP
C_zux_parent(SEXP xp, SEXP ids) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  for (i = 0; i < n; i++) {
    zux_id p = zux_parent(d, check_id(d, INTEGER(ids)[i]));
    INTEGER(out)[i] = p == ZUX_NONE ? NA_INTEGER : (int)p;
  }
  UNPROTECT(1);
  return out;
}

/* mode 0 = all children, 1 = element children (filtered),
 * mode 2 = element descendants (filtered), all in document order. */
SEXP
C_zux_select(SEXP xp, SEXP ids, SEXP mode_, SEXP local, SEXP uri) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  int mode = Rf_asInteger(mode_);
  idbuf b;
  memset(&b, 0, sizeof(b));

  for (i = 0; i < n; i++) {
    zux_id root = check_id(d, INTEGER(ids)[i]);
    zux_id c;
    if (mode == 0) {
      for (c = zux_first_child(d, root); c != ZUX_NONE;
           c = zux_next_sibling(d, c))
        idbuf_add(&b, c);
    } else if (mode == 1) {
      for (c = zux_first_child(d, root); c != ZUX_NONE;
           c = zux_next_sibling(d, c))
        if (zux_node_kind(d, c) == ZUX_ELEMENT
            && name_matches(zux_node_name(d, c), local, uri))
          idbuf_add(&b, c);
    } else {
      /* Iterative pre-order descent with an explicit stack: deep documents
       * must not be able to recurse the C stack here either. */
      idbuf stack, seed;
      size_t s0;
      memset(&stack, 0, sizeof(stack));
      memset(&seed, 0, sizeof(seed));
      /* Seed reversed, like every later push, so popping yields document
       * order rather than reverse document order. */
      for (c = zux_first_child(d, root); c != ZUX_NONE;
           c = zux_next_sibling(d, c))
        idbuf_add(&seed, c);
      for (s0 = seed.n; s0 > 0; s0--)
        idbuf_add(&stack, (zux_id)seed.v[s0 - 1]);
      while (stack.n > 0) {
        zux_id id = (zux_id)stack.v[--stack.n];
        zux_id k;
        idbuf kids;
        size_t j;
        if (zux_node_kind(d, id) == ZUX_ELEMENT
            && name_matches(zux_node_name(d, id), local, uri))
          idbuf_add(&b, id);
        memset(&kids, 0, sizeof(kids));
        for (k = zux_first_child(d, id); k != ZUX_NONE;
             k = zux_next_sibling(d, k))
          idbuf_add(&kids, k);
        for (j = kids.n; j > 0; j--)
          idbuf_add(&stack, (zux_id)kids.v[j - 1]);
      }
    }
  }
  return idbuf_sexp(&b);
}

SEXP
C_zux_text(SEXP xp, SEXP ids, SEXP recursive_) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  int recursive = Rf_asLogical(recursive_) == TRUE;
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));

  for (i = 0; i < n; i++) {
    zux_id id = check_id(d, INTEGER(ids)[i]);
    int kind = zux_node_kind(d, id);
    size_t total = 0;
    char *buf;

    if (kind == ZUX_TEXT || kind == ZUX_COMMENT) {
      SET_STRING_ELT(out, i, mk_utf8(zux_node_text(d, id)));
      continue;
    }

    /* Two iterative passes: measure, then fill. */
    {
      idbuf stack;
      memset(&stack, 0, sizeof(stack));
      idbuf_add(&stack, id);
      while (stack.n > 0) {
        zux_id cur = (zux_id)stack.v[--stack.n];
        zux_id c;
        if (cur != id && zux_node_kind(d, cur) == ZUX_TEXT)
          total += zux_node_text(d, cur).len;
        if (cur == id || recursive)
          for (c = zux_first_child(d, cur); c != ZUX_NONE;
               c = zux_next_sibling(d, c))
            idbuf_add(&stack, c);
      }
      /* Order is irrelevant for the measuring pass; the filling pass below
       * collects text nodes in document order. */
    }
    buf = (char *)R_alloc(total + 1, 1);
    {
      size_t off = 0;
      size_t j;
      idbuf stack;
      idbuf order;
      memset(&stack, 0, sizeof(stack));
      memset(&order, 0, sizeof(order));
      idbuf_add(&stack, id);
      while (stack.n > 0) {
        zux_id cur = (zux_id)stack.v[--stack.n];
        zux_id c;
        idbuf kids;
        size_t m;
        if (cur != id && zux_node_kind(d, cur) == ZUX_TEXT)
          idbuf_add(&order, cur);
        if (cur == id || recursive) {
          memset(&kids, 0, sizeof(kids));
          for (c = zux_first_child(d, cur); c != ZUX_NONE;
               c = zux_next_sibling(d, c))
            idbuf_add(&kids, c);
          for (m = kids.n; m > 0; m--)
            idbuf_add(&stack, (zux_id)kids.v[m - 1]);
        }
      }
      for (j = 0; j < order.n; j++) {
        zux_str s = zux_node_text(d, (zux_id)order.v[j]);
        memcpy(buf + off, s.ptr, s.len);
        off += s.len;
      }
      buf[off] = '\0';
      SET_STRING_ELT(out, i, Rf_mkCharLenCE(buf, (int)off, CE_UTF8));
    }
  }
  UNPROTECT(1);
  return out;
}

SEXP
C_zux_attrs(SEXP xp, SEXP ids) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  for (i = 0; i < n; i++) {
    zux_id id = check_id(d, INTEGER(ids)[i]);
    uint32_t k, na = zux_attr_count(d, id);
    SEXP v = PROTECT(Rf_allocVector(STRSXP, na));
    SEXP nms = PROTECT(Rf_allocVector(STRSXP, na));
    for (k = 0; k < na; k++) {
      zux_attr a = zux_attr_at(d, id, k);
      SET_STRING_ELT(v, k, mk_utf8(a.value));
      if (a.name.prefix.len) {
        char buf[512];
        size_t need = a.name.prefix.len + 1 + a.name.local.len;
        if (need < sizeof(buf)) {
          memcpy(buf, a.name.prefix.ptr, a.name.prefix.len);
          buf[a.name.prefix.len] = ':';
          memcpy(buf + a.name.prefix.len + 1, a.name.local.ptr,
                 a.name.local.len);
          SET_STRING_ELT(nms, k, Rf_mkCharLenCE(buf, (int)need, CE_UTF8));
        } else {
          SET_STRING_ELT(nms, k, mk_utf8(a.name.local));
        }
      } else {
        SET_STRING_ELT(nms, k, mk_utf8(a.name.local));
      }
    }
    Rf_setAttrib(v, R_NamesSymbol, nms);
    SET_VECTOR_ELT(out, i, v);
    UNPROTECT(2);
  }
  UNPROTECT(1);
  return out;
}

SEXP
C_zux_attr(SEXP xp, SEXP ids, SEXP local, SEXP uri) {
  zux_document *d = doc_ptr(xp);
  R_xlen_t n = Rf_xlength(ids), i;
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  for (i = 0; i < n; i++) {
    zux_id id = check_id(d, INTEGER(ids)[i]);
    uint32_t k, na = zux_attr_count(d, id);
    SET_STRING_ELT(out, i, NA_STRING);
    for (k = 0; k < na; k++) {
      zux_attr a = zux_attr_at(d, id, k);
      if (name_matches(a.name, local, uri)) {
        SET_STRING_ELT(out, i, mk_utf8(a.value));
        break;
      }
    }
  }
  UNPROTECT(1);
  return out;
}

SEXP
C_zux_doc_meta(SEXP xp) {
  zux_document *d = doc_ptr(xp);
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 6));
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, 6));
  zux_str v = zux_doc_version(d), e = zux_doc_encoding(d);
  int sa = zux_doc_standalone(d);
  SET_VECTOR_ELT(out, 0, v.len ? Rf_ScalarString(mk_utf8(v))
                               : Rf_ScalarString(NA_STRING));
  SET_VECTOR_ELT(out, 1, e.len ? Rf_ScalarString(mk_utf8(e))
                               : Rf_ScalarString(NA_STRING));
  SET_VECTOR_ELT(out, 2,
                 Rf_ScalarLogical(sa < 0 ? NA_LOGICAL : (sa ? TRUE : FALSE)));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)zux_node_count(d)));
  SET_VECTOR_ELT(out, 4, Rf_ScalarReal((double)zux_attr_total(d)));
  SET_VECTOR_ELT(out, 5, Rf_ScalarReal((double)zux_document_bytes(d)));
  SET_STRING_ELT(nms, 0, Rf_mkChar("version"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("encoding"));
  SET_STRING_ELT(nms, 2, Rf_mkChar("standalone"));
  SET_STRING_ELT(nms, 3, Rf_mkChar("n_nodes"));
  SET_STRING_ELT(nms, 4, Rf_mkChar("n_attrs"));
  SET_STRING_ELT(nms, 5, Rf_mkChar("bytes"));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}
