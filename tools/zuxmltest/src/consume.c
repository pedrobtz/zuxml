/* Consumes zuxml exactly as zuxlsx does: Expat's own API, off the LinkingTo
 * include path, linked statically out of inst/lib/libzuxml.a. Nothing here
 * includes zuxml.h or touches zuxml's namespace.
 *
 * The two entry points fail in different ways, on purpose:
 *
 *   C_consume         drives a real parse through the buffer and
 *                     suspend/resume pair. Those are what a pull-style reader
 *                     such as xlsxio needs, and they are the reason a
 *                     downstream package links this archive rather than going
 *                     through a callback table. A wrongly built archive shows
 *                     up here, at run time.
 *   C_expat_version   is a real call, not a macro, so the archive has to
 *                     supply a definition for it. On Linux and Windows a
 *                     dropped PKG_LIBS therefore fails at link time. On macOS
 *                     it does not -- R links with -undefined dynamic_lookup,
 *                     and the loader quietly satisfies XML_* from whatever
 *                     Expat is already in the process -- which is why
 *                     tools/run-downstream-check checks nm -u as well.
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include <expat.h>

#include <stddef.h>
#include <string.h>

/* Streaming consumer: counts events without building a tree. */
typedef struct {
  XML_Parser parser;
  long elements, attrs;
  size_t text_bytes;
  int suspended; /* set once, so resume cannot loop forever */
} counter;

static void XMLCALL
on_start(void *ctx, const XML_Char *name, const XML_Char **atts) {
  counter *c = (counter *)ctx;
  (void)name;
  c->elements++;
  for (; atts != NULL && *atts != NULL; atts += 2)
    c->attrs++;
  /* Suspend on the first element and let the feed loop resume. A reader that
   * hands rows back to its caller lives on this pair, and an archive built
   * without XML_STOPPARSER support would still link and still parse -- it
   * would only fail here. */
  if (!c->suspended) {
    c->suspended = 1;
    XML_StopParser(c->parser, XML_TRUE);
  }
}

static void XMLCALL
on_text(void *ctx, const XML_Char *s, int len) {
  counter *c = (counter *)ctx;
  (void)s; /* borrowed and not NUL-terminated: length only */
  c->text_bytes += (size_t)len;
}

SEXP
C_consume(SEXP x, SEXP chunk_) {
  /* No count of text callbacks: Expat splits character data at buffer
   * boundaries, so that number is a function of the chunk size, while
   * text_bytes is not. Returning it would make the chunk-independence
   * assertion in tools/run-downstream-check fail for a correct parse. */
  const char *fields[] = {"status", "elements", "attrs", "text_bytes",
                          "message", ""};
  const unsigned char *data = RAW(x);
  size_t total = (size_t)Rf_xlength(x);
  size_t chunk = (size_t)Rf_asInteger(chunk_);
  size_t pos = 0;
  enum XML_Status st = XML_STATUS_OK;
  const char *message = "";
  counter c;
  XML_Parser p;
  SEXP out;

  if (chunk == 0)
    chunk = total > 0 ? total : 1;

  p = XML_ParserCreate(NULL);
  if (p == NULL)
    Rf_error("zuxmltest: XML_ParserCreate() failed");

  memset(&c, 0, sizeof(c));
  c.parser = p;
  XML_SetUserData(p, &c);
  XML_SetStartElementHandler(p, on_start);
  XML_SetCharacterDataHandler(p, on_text);

  /* XML_GetBuffer/XML_ParseBuffer rather than XML_Parse: it is the copy-free
   * shape, and it is what breaks first if the archive was built with a
   * different XML_Char width than the header on the include path declares. */
  do {
    size_t k = total - pos < chunk ? total - pos : chunk;
    int final;
    void *buf = XML_GetBuffer(p, (int)(k > 0 ? k : 1));
    if (buf == NULL) {
      XML_ParserFree(p);
      Rf_error("zuxmltest: XML_GetBuffer() failed");
    }
    if (k > 0)
      memcpy(buf, data + pos, k);
    pos += k;
    final = pos >= total;
    st = XML_ParseBuffer(p, (int)k, final);
    while (st == XML_STATUS_SUSPENDED)
      st = XML_ResumeParser(p);
    if (st == XML_STATUS_ERROR || final)
      break;
  } while (1);

  /* XML_ErrorString() returns a pointer into Expat's own static table, so it
   * outlives the parser and this is safe to read after the free below. */
  if (st == XML_STATUS_ERROR)
    message = XML_ErrorString(XML_GetErrorCode(p));
  XML_ParserFree(p);

  out = PROTECT(Rf_mkNamed(VECSXP, fields));
  SET_VECTOR_ELT(out, 0,
                 Rf_mkString(st == XML_STATUS_ERROR ? "error" : "ok"));
  SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)c.elements));
  SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double)c.attrs));
  SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)c.text_bytes));
  /* Surfaced so the gate can assert on it: Expat's own message, proving the
   * error tables came out of the archive intact. */
  SET_VECTOR_ELT(out, 4, Rf_mkString(message));
  UNPROTECT(1);
  return out;
}

SEXP
C_expat_version(void) {
  return Rf_mkString(XML_ExpatVersion());
}

static const R_CallMethodDef call_methods[] = {
    {"C_consume", (DL_FUNC)&C_consume, 2},
    {"C_expat_version", (DL_FUNC)&C_expat_version, 0},
    {NULL, NULL, 0}};

void
R_init_zuxmltest(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
