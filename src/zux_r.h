/* Prototypes for the .Call entry points.
 *
 * These are referenced only from init.c's registration table, so without
 * declarations they trip -Wmissing-prototypes. Declaring them here satisfies
 * the warning properly rather than suppressing it, and keeps the registration
 * table and the definitions type-checked against one another.
 */

#ifndef ZUX_R_H
#define ZUX_R_H

#include <Rinternals.h>

#include "zuxml.h"

SEXP C_zuxml_info(void);

/* Test harnesses (Stages 2 and 3); not part of the public R API. */
SEXP C_zux_event_log(SEXP x, SEXP chunk, SEXP opts, SEXP cancel);
SEXP C_zux_tree_info(SEXP x, SEXP opts);

/* Document and node API. */
SEXP C_zux_parse(SEXP x, SEXP opts);
SEXP C_zux_root(SEXP xp);
SEXP C_zux_node_info(SEXP xp, SEXP ids, SEXP what);
SEXP C_zux_parent(SEXP xp, SEXP ids);
SEXP C_zux_select(SEXP xp, SEXP ids, SEXP mode, SEXP local, SEXP uri);
SEXP C_zux_text(SEXP xp, SEXP ids, SEXP recursive);
SEXP C_zux_attrs(SEXP xp, SEXP ids);
SEXP C_zux_attr(SEXP xp, SEXP ids, SEXP local, SEXP uri);
SEXP C_zux_doc_meta(SEXP xp);
SEXP C_zux_serialize(SEXP xp, SEXP ids);

/* Entry point R calls on load (src/init.c). */
struct _DllInfo;
void R_init_zuxml(struct _DllInfo *dll);

/* Registration of the public C API table (src/zux_register.c). */
const zuxml_api *zuxml_api_v2(void);
void zuxml_register_api(struct _DllInfo *dll);

#endif /* ZUX_R_H */
