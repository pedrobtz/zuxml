/* zuxml internal C API -- the event seam.
 *
 * This is the boundary described in .agents/zuxml-design.md section 3. No
 * Expat type crosses it: producers below emit these events, consumers above
 * (the tree builder, zuhttp) only ever see these types. Stage 6 promotes a
 * subset of this to inst/include/zuxml.h as the public ABI.
 */

#ifndef ZUX_H
#define ZUX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public types, the function-table layout and the string-lifetime contract
 * all live in the installed header, so the internal and public views cannot
 * drift. This file adds only the direct entry points, which downstream
 * packages reach through the registered table instead. */
#include "zuxml.h"

void zux_options_init(zux_options *opt);

zux_status zux_parser_new(zux_parser **out, const zux_options *opt,
                          const zux_handlers *h, void *ctx);
zux_status zux_parser_feed(zux_parser *p, const void *data, size_t n);
zux_status zux_parser_finish(zux_parser *p);
void zux_parser_free(zux_parser *p);
void zux_parser_error(const zux_parser *p, zux_error *out);

const char *zux_status_string(zux_status s);

/* ---- document tree -------------------------------------------------------
 * One document owns everything. Three growable arrays plus a string buffer,
 * all addressed by index or offset and never by pointer, so realloc is always
 * safe and pointer stability never has to be reasoned about.
 *
 * Strings returned by these accessors are owned by the document, are
 * NUL-terminated, and stay valid for its lifetime -- the opposite of the
 * borrowed, non-terminated strings handlers receive.
 * ------------------------------------------------------------------------ */

zux_status zux_tree_parse(zux_document **out, const void *data, size_t n,
                          const zux_options *opt, zux_error *err);

/* Incremental form. Lets a caller feed arbitrary chunks -- so that R can
 * check for interrupts at a safe boundary between them, and so that zuhttp
 * can build a tree from response chunks without materializing the body. */
zux_status zux_tree_begin(zux_tree_builder **out, const zux_options *opt);
zux_status zux_tree_feed(zux_tree_builder *b, const void *data, size_t n);
zux_status zux_tree_end(zux_tree_builder *b, zux_document **out,
                        zux_error *err);
void zux_tree_error(const zux_tree_builder *b, zux_error *out);
void zux_tree_abort(zux_tree_builder *b);
void zux_document_free(zux_document *doc);

zux_id zux_root(const zux_document *d);
uint32_t zux_node_count(const zux_document *d);
uint32_t zux_name_count(const zux_document *d);
uint32_t zux_attr_total(const zux_document *d);
size_t zux_document_bytes(const zux_document *d);

int zux_node_kind(const zux_document *d, zux_id id);
zux_id zux_parent(const zux_document *d, zux_id id);
zux_id zux_first_child(const zux_document *d, zux_id id);
zux_id zux_next_sibling(const zux_document *d, zux_id id);
zux_name zux_node_name(const zux_document *d, zux_id id);
zux_str zux_node_text(const zux_document *d, zux_id id);
uint32_t zux_attr_count(const zux_document *d, zux_id id);
zux_attr zux_attr_at(const zux_document *d, zux_id id, uint32_t i);

/* Serialize a node and its subtree to UTF-8. Caller frees *out with free().
 * Iterative: safe on arbitrarily deep documents. */
zux_status zux_serialize(const zux_document *d, zux_id id, char **out,
                         size_t *out_len);

zux_str zux_doc_version(const zux_document *d);
zux_str zux_doc_encoding(const zux_document *d);
int zux_doc_standalone(const zux_document *d);


#ifdef __cplusplus
}
#endif
#endif /* ZUX_H */
