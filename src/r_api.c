/* zuxml: R bindings.
 *
 * At Stage 2 this exposes only an event-log harness so that testthat can
 * drive the seam directly: it records every event as a string, which makes
 * chunk-independence a plain vector comparison. The real R document API and
 * its R_UnwindProtect handling arrive in Stage 4; this harness deliberately
 * does no R allocation until the parse is over.
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zux.h"

typedef struct {
  char **v;
  size_t n, cap;
  int oom;
  long cancel_at; /* 1-based event index, 0 = never */
  long count;
} evlog;

static int
ev_push(evlog *e, char *owned) {
  if (owned == NULL) {
    e->oom = 1;
    return 0;
  }
  if (e->n == e->cap) {
    size_t cap = e->cap ? e->cap * 2 : 32;
    char **grown = (char **)realloc(e->v, cap * sizeof(char *));
    if (grown == NULL) {
      free(owned);
      e->oom = 1;
      return 0;
    }
    e->v = grown;
    e->cap = cap;
  }
  e->v[e->n++] = owned;
  return 1;
}

static char *
ev_fmt(const char *fmt, ...) {
  va_list ap;
  int len;
  char *buf;

  va_start(ap, fmt);
  len = vsnprintf(NULL, 0, fmt, ap);
  va_end(ap);
  if (len < 0)
    return NULL;
  buf = (char *)malloc((size_t)len + 1);
  if (buf == NULL)
    return NULL;
  va_start(ap, fmt);
  vsnprintf(buf, (size_t)len + 1, fmt, ap);
  va_end(ap);
  return buf;
}

/* Render a name as {uri}local^prefix so every field is visible to tests. */
static char *
name_str(const zux_name *n) {
  return ev_fmt("{%.*s}%.*s^%.*s", (int)n->uri.len, n->uri.ptr,
                (int)n->local.len, n->local.ptr, (int)n->prefix.len,
                n->prefix.ptr);
}

static zux_status
ev_tick(evlog *e) {
  e->count++;
  if (e->cancel_at > 0 && e->count == e->cancel_at)
    return ZUX_ERR_CANCELLED;
  return ZUX_OK;
}

static zux_status
h_start(void *ctx, const zux_name *name, const zux_attr *attrs,
        size_t n_attrs) {
  evlog *e = (evlog *)ctx;
  char *nm = name_str(name);
  char *line = ev_fmt("start|%s|n=%d", nm == NULL ? "?" : nm, (int)n_attrs);
  size_t i;
  free(nm);
  if (! ev_push(e, line))
    return ZUX_ERR_MEMORY;
  for (i = 0; i < n_attrs; i++) {
    char *an = name_str(&attrs[i].name);
    char *al = ev_fmt("  attr|%s|%.*s", an == NULL ? "?" : an,
                      (int)attrs[i].value.len, attrs[i].value.ptr);
    free(an);
    if (! ev_push(e, al))
      return ZUX_ERR_MEMORY;
  }
  return ev_tick(e);
}

static zux_status
h_end(void *ctx, const zux_name *name) {
  evlog *e = (evlog *)ctx;
  char *nm = name_str(name);
  char *line = ev_fmt("end|%s", nm == NULL ? "?" : nm);
  free(nm);
  if (! ev_push(e, line))
    return ZUX_ERR_MEMORY;
  return ev_tick(e);
}

static zux_status
h_text(void *ctx, zux_str t) {
  evlog *e = (evlog *)ctx;
  if (! ev_push(e, ev_fmt("text|%.*s", (int)t.len, t.ptr)))
    return ZUX_ERR_MEMORY;
  return ev_tick(e);
}

static zux_status
h_comment(void *ctx, zux_str t) {
  evlog *e = (evlog *)ctx;
  if (! ev_push(e, ev_fmt("comment|%.*s", (int)t.len, t.ptr)))
    return ZUX_ERR_MEMORY;
  return ev_tick(e);
}

static zux_status
h_pi(void *ctx, zux_str target, zux_str data) {
  evlog *e = (evlog *)ctx;
  if (! ev_push(e, ev_fmt("pi|%.*s|%.*s", (int)target.len, target.ptr,
                          (int)data.len, data.ptr)))
    return ZUX_ERR_MEMORY;
  return ev_tick(e);
}

static zux_status
h_decl(void *ctx, zux_str version, zux_str encoding, int standalone) {
  evlog *e = (evlog *)ctx;
  if (! ev_push(e, ev_fmt("decl|%.*s|%.*s|%d", (int)version.len, version.ptr,
                          (int)encoding.len, encoding.ptr, standalone)))
    return ZUX_ERR_MEMORY;
  return ev_tick(e);
}

static SEXP
opt_get(SEXP opts, const char *name) {
  SEXP nms = Rf_getAttrib(opts, R_NamesSymbol);
  R_xlen_t i;
  if (nms == R_NilValue)
    return R_NilValue;
  for (i = 0; i < Rf_xlength(opts); i++) {
    if (strcmp(CHAR(STRING_ELT(nms, i)), name) == 0)
      return VECTOR_ELT(opts, i);
  }
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
C_zux_event_log(SEXP x, SEXP chunk_, SEXP opts, SEXP cancel_) {
  zux_options opt;
  zux_handlers h;
  zux_parser *p = NULL;
  zux_error err;
  evlog e;
  const unsigned char *data;
  size_t total, pos, chunk;
  zux_status st;
  SEXP out, events, nms;
  size_t i;

  if (TYPEOF(x) != RAWSXP)
    Rf_error("zuxml: expected a raw vector");

  memset(&e, 0, sizeof(e));
  e.cancel_at = (long)Rf_asInteger(cancel_);

  zux_options_init(&opt);
  opt.max_depth = (uint32_t)opt_size(opts, "max_depth", opt.max_depth);
  opt.max_nodes = (uint32_t)opt_size(opts, "max_nodes", opt.max_nodes);
  opt.max_attrs = (uint32_t)opt_size(opts, "max_attrs", opt.max_attrs);
  opt.max_text = opt_size(opts, "max_text", opt.max_text);
  opt.max_memory = opt_size(opts, "max_memory", opt.max_memory);
  opt.allow_doctype = opt_flag(opts, "allow_doctype", opt.allow_doctype);
  opt.keep_comments = opt_flag(opts, "comments", opt.keep_comments);
  opt.keep_pis = opt_flag(opts, "pis", opt.keep_pis);
  {
    SEXP enc = opt_get(opts, "encoding");
    if (enc != R_NilValue && TYPEOF(enc) == STRSXP && Rf_xlength(enc) == 1
        && STRING_ELT(enc, 0) != NA_STRING)
      opt.encoding = CHAR(STRING_ELT(enc, 0));
  }

  memset(&h, 0, sizeof(h));
  h.start_element = h_start;
  h.end_element = h_end;
  h.text = h_text;
  h.comment = h_comment;
  h.pi = h_pi;
  h.xml_decl = h_decl;

  st = zux_parser_new(&p, &opt, &h, &e);
  if (st == ZUX_OK) {
    data = RAW(x);
    total = (size_t)Rf_xlength(x);
    chunk = (size_t)Rf_asInteger(chunk_);
    if (chunk == 0)
      chunk = total > 0 ? total : 1;
    for (pos = 0; pos < total; pos += chunk) {
      size_t n = total - pos < chunk ? total - pos : chunk;
      st = zux_parser_feed(p, data + pos, n);
      if (st != ZUX_OK)
        break;
    }
    if (st == ZUX_OK)
      st = zux_parser_finish(p);
    zux_parser_error(p, &err);
  } else {
    memset(&err, 0, sizeof(err));
    err.status = st;
    err.message = zux_status_string(st);
  }

  if (e.oom) {
    err.status = ZUX_ERR_MEMORY;
    err.message = "harness out of memory";
  }

  /* All C work is complete; only now do we allocate anything R can longjmp
   * out of. The event buffer is copied and released immediately. */
  out = PROTECT(Rf_allocVector(VECSXP, 6));
  events = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)e.n));
  for (i = 0; i < e.n; i++)
    SET_STRING_ELT(events, (R_xlen_t)i, Rf_mkCharCE(e.v[i], CE_UTF8));
  SET_VECTOR_ELT(out, 0, events);
  SET_VECTOR_ELT(out, 1, Rf_mkString(zux_status_string(err.status)));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)err.line));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)err.column));
  SET_VECTOR_ELT(out, 4, Rf_ScalarReal((double)err.byte_offset));
  SET_VECTOR_ELT(out, 5,
                 Rf_mkString(err.message == NULL ? "" : err.message));
  nms = PROTECT(Rf_allocVector(STRSXP, 6));
  SET_STRING_ELT(nms, 0, Rf_mkChar("events"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("status"));
  SET_STRING_ELT(nms, 2, Rf_mkChar("line"));
  SET_STRING_ELT(nms, 3, Rf_mkChar("column"));
  SET_STRING_ELT(nms, 4, Rf_mkChar("byte_offset"));
  SET_STRING_ELT(nms, 5, Rf_mkChar("message"));
  Rf_setAttrib(out, R_NamesSymbol, nms);

  for (i = 0; i < e.n; i++)
    free(e.v[i]);
  free(e.v);
  zux_parser_free(p);

  UNPROTECT(3);
  return out;
}
