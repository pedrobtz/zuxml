#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "expat_config.h"
#include "vendor/expat/expat.h"

/* Name of the entropy backend src/expat_config.h selected. Reported by
 * zuxml_info() so that a weak source can never be shipped unnoticed. */
static const char *
zux_entropy_source(void) {
#if defined(_WIN32)
  return "rand_s";
#elif defined(HAVE_ARC4RANDOM_BUF)
  return "arc4random_buf";
#elif defined(HAVE_ARC4RANDOM)
  return "arc4random";
#elif defined(HAVE_SYSCALL_GETRANDOM)
  return "syscall(SYS_getrandom)";
#elif defined(HAVE_GETRANDOM)
  return "getrandom";
#elif defined(HAVE_GETENTROPY)
  return "getentropy";
#elif defined(XML_DEV_URANDOM)
  return "/dev/urandom";
#else
  return "none";
#endif
}

/* Stage 1 smoke test: build a namespace-aware parser with the separator the
 * design mandates, then free it. Proves the vendored library is linked and
 * usable, which is the whole point of this stage. */
static int
zux_parser_roundtrip(void) {
  XML_Parser p = XML_ParserCreateNS(NULL, (XML_Char)'\f');
  if (p == NULL)
    return 0;
  XML_ParserFree(p);
  return 1;
}

static SEXP
zux_str(const char *s) {
  return Rf_ScalarString(Rf_mkCharCE(s, CE_UTF8));
}

SEXP
C_zuxml_info(void) {
  const char *names[] = {"expat_version", "namespaces",  "dtd",
                         "general_entities", "context_bytes", "xml_char_bytes",
                         "byteorder",     "entropy",     "parser_ok",
                         ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));

  SET_VECTOR_ELT(out, 0, zux_str(XML_ExpatVersion()));
  SET_VECTOR_ELT(out, 1, Rf_ScalarLogical(XML_NS ? TRUE : FALSE));
#if defined(XML_DTD)
  SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(TRUE));
#else
  SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(FALSE));
#endif
  SET_VECTOR_ELT(out, 3, Rf_ScalarLogical(XML_GE == 1 ? TRUE : FALSE));
  SET_VECTOR_ELT(out, 4, Rf_ScalarInteger(XML_CONTEXT_BYTES));
  SET_VECTOR_ELT(out, 5, Rf_ScalarInteger((int)sizeof(XML_Char)));
  SET_VECTOR_ELT(out, 6, zux_str(BYTEORDER == 1234 ? "little" : "big"));
  SET_VECTOR_ELT(out, 7, zux_str(zux_entropy_source()));
  SET_VECTOR_ELT(out, 8, Rf_ScalarLogical(zux_parser_roundtrip() ? TRUE : FALSE));

  UNPROTECT(1);
  return out;
}

/* Entry points are added here as they are implemented; see
 * .agents/roadmap.md. Symbol search is off and symbols are forced from the
 * first commit rather than being retrofitted later. */
static const R_CallMethodDef call_methods[] = {
    {"C_zuxml_info", (DL_FUNC)&C_zuxml_info, 0},
    {NULL, NULL, 0}};

attribute_visible void
R_init_zuxml(DllInfo *dll) {
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
