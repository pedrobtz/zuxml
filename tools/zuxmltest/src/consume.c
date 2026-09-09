/* Consumes zuxml exactly as zuhttp will: no Expat header on the include path,
 * no linking against Expat, everything through the registered table. */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define ZUXML_DEFINE_API_GET
#include "zuxml.h"

/* Streaming consumer: counts events without building a tree, which is the
 * shape zuhttp needs for large response bodies. */
typedef struct {
  long elements, texts, attrs;
  size_t text_bytes;
} counter;

static zux_status
on_start(void *ctx, const zux_name *name, const zux_attr *attrs,
         size_t n_attrs) {
  counter *c = (counter *)ctx;
  (void)name;
  (void)attrs;
  c->elements++;
  c->attrs += (long)n_attrs;
  return ZUX_OK;
}

static zux_status
on_text(void *ctx, zux_str t) {
  counter *c = (counter *)ctx;
  c->texts++;
  c->text_bytes += t.len; /* borrowed: length only, no retained pointer */
  return ZUX_OK;
}

SEXP
C_consume(SEXP x, SEXP chunk_) {
  const zuxml_api *api = zuxml_api_get();
  zux_options opt;
  zux_handlers h;
  zux_parser *p = NULL;
  zux_error err;
  counter c;
  zux_status st;
  const unsigned char *data;
  size_t total, pos, chunk;
  SEXP out, nms;
  zux_document *doc = NULL;
  uint32_t n_nodes = 0;
  char *ser = NULL;
  size_t ser_len = 0;

  if (api == NULL)
    Rf_error("zuxmltest: could not obtain the zuxml API table");
  if (!ZUXML_API_HAS(api, set_message))
    Rf_error("zuxmltest: zuxml API table is too old");

  memset(&c, 0, sizeof(c));
  memset(&h, 0, sizeof(h));
  h.start_element = on_start;
  h.text = on_text;

  api->options_init(&opt);

  data = RAW(x);
  total = (size_t)Rf_xlength(x);
  chunk = (size_t)Rf_asInteger(chunk_);
  if (chunk == 0)
    chunk = total > 0 ? total : 1;

  st = api->parser_new(&p, &opt, &h, &c);
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
    memset(&err, 0, sizeof(err));
    err.status = st;
    /* message is an inline buffer; the table copies into it for us. */
    api->set_message(&err, api->status_string(st));
  }

  /* Also exercise the tree and serializer paths through the table. */
  if (api->tree_parse(&doc, data, total, &opt, NULL) == ZUX_OK && doc != NULL) {
    n_nodes = api->node_count(doc);
    if (api->serialize(doc, 0, &ser, &ser_len) != ZUX_OK)
      ser = NULL;
    api->document_free(doc);
  }

  out = PROTECT(Rf_allocVector(VECSXP, 7));
  SET_VECTOR_ELT(out, 0, Rf_mkString(api->status_string(err.status)));
  SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)c.elements));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)c.attrs));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)c.text_bytes));
  SET_VECTOR_ELT(out, 4, Rf_ScalarReal((double)n_nodes));
  SET_VECTOR_ELT(out, 5,
                 ser == NULL ? Rf_mkString("") : Rf_mkString(ser));
  /* Surfaced so the gate can assert on it: a message that arrives empty or
   * truncated across the table is exactly the ABI regression this fixture
   * exists to catch, and it is invisible if only `status` is returned. */
  SET_VECTOR_ELT(out, 6, Rf_mkString(err.message));
  free(ser);
  nms = PROTECT(Rf_allocVector(STRSXP, 7));
  SET_STRING_ELT(nms, 0, Rf_mkChar("status"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("elements"));
  SET_STRING_ELT(nms, 2, Rf_mkChar("attrs"));
  SET_STRING_ELT(nms, 3, Rf_mkChar("text_bytes"));
  SET_STRING_ELT(nms, 4, Rf_mkChar("n_nodes"));
  SET_STRING_ELT(nms, 5, Rf_mkChar("serialized"));
  SET_STRING_ELT(nms, 6, Rf_mkChar("message"));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(2);
  return out;
}

static const R_CallMethodDef call_methods[] = {
    {"C_consume", (DL_FUNC)&C_consume, 2}, {NULL, NULL, 0}};

void
R_init_zuxmltest(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
