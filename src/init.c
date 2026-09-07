#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

/* Registration table. Entry points are added here as they are implemented;
 * see .agents/roadmap.md. Keeping the table empty but present means the
 * shared object always exports R_init_zuxml, and symbol search stays off
 * from the very first commit rather than being retrofitted later. */
static const R_CallMethodDef call_methods[] = {
    {NULL, NULL, 0}
};

attribute_visible void R_init_zuxml(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
