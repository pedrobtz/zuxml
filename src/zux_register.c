/* zuxml: registration of the public C API table.
 *
 * Downstream packages fetch this with R_GetCCallable("zuxml", "zuxml_api_v1")
 * -- see inst/include/zuxml.h. struct_size is the only version discriminator;
 * fields may be appended but never reordered or removed.
 */

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include "zux.h"
#include "zux_r.h"

static const zuxml_api zuxml_api_table = {
    (uint32_t)sizeof(zuxml_api),

    zux_options_init,
    zux_status_string,

    zux_parser_new,
    zux_parser_feed,
    zux_parser_finish,
    zux_parser_free,
    zux_parser_error,

    zux_tree_parse,
    zux_tree_begin,
    zux_tree_feed,
    zux_tree_end,
    zux_tree_error,
    zux_tree_abort,
    zux_document_free,

    zux_root,
    zux_node_count,
    zux_node_kind,
    zux_parent,
    zux_first_child,
    zux_next_sibling,
    zux_node_name,
    zux_node_text,
    zux_attr_count,
    zux_attr_at,

    zux_serialize};

const zuxml_api *
zuxml_api_v1(void) {
  return &zuxml_api_table;
}

void
zuxml_register_api(DllInfo *dll) {
  /* R_RegisterCCallable is keyed on the package name, not the DllInfo. */
  (void)dll;
  R_RegisterCCallable("zuxml", "zuxml_api_v1", (DL_FUNC)zuxml_api_v1);
}
