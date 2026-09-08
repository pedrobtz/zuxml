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

typedef enum {
  ZUX_OK = 0,
  ZUX_DONE,
  ZUX_ERR_INVALID_ARGUMENT,
  ZUX_ERR_INVALID_XML,
  ZUX_ERR_ENCODING,
  ZUX_ERR_DOCTYPE,
  ZUX_ERR_UNDEFINED_ENTITY,
  ZUX_ERR_DEPTH_LIMIT,
  ZUX_ERR_NODE_LIMIT,
  ZUX_ERR_ATTR_LIMIT,
  ZUX_ERR_TEXT_LIMIT,
  ZUX_ERR_MEMORY_LIMIT,
  ZUX_ERR_MEMORY,
  ZUX_ERR_CANCELLED,
  ZUX_ERR_INTERNAL
} zux_status;

/* ---- string contract -----------------------------------------------------
 * Strings reaching a HANDLER are borrowed and valid ONLY until that handler
 * returns. They are NOT NUL-terminated. Callees MUST copy anything they keep.
 * (Document accessors added in Stage 3 have the opposite contract: owned,
 * NUL-terminated, valid for the document's lifetime.)
 * ------------------------------------------------------------------------ */
typedef struct {
  const char *ptr;
  size_t len;
} zux_str;

/* A namespace-expanded name. `uri` and `prefix` have len 0 when absent.
 * Matching is on (uri, local) only; `prefix` is retained for serialization
 * and diagnostics and must never be used to decide identity. */
typedef struct {
  zux_str uri;
  zux_str local;
  zux_str prefix;
} zux_name;

typedef struct {
  zux_name name;
  zux_str value;
} zux_attr;

/* Handlers return ZUX_OK to continue or any error status to stop the parse;
 * that status becomes the parse result. This is the cancellation mechanism.
 * Any handler may be NULL. */
typedef struct {
  zux_status (*start_element)(void *ctx, const zux_name *name,
                              const zux_attr *attrs, size_t n_attrs);
  zux_status (*end_element)(void *ctx, const zux_name *name);
  zux_status (*text)(void *ctx, zux_str text);
  zux_status (*comment)(void *ctx, zux_str text);
  zux_status (*pi)(void *ctx, zux_str target, zux_str data);
  zux_status (*xml_decl)(void *ctx, zux_str version, zux_str encoding,
                         int standalone);
} zux_handlers;

typedef struct {
  uint32_t max_depth;
  uint32_t max_nodes;
  uint32_t max_attrs;
  size_t max_text;   /* bytes, per text node after coalescing */
  size_t max_memory; /* bytes, total seam+tree allocation */
  const char *encoding;
  int allow_doctype;
  int keep_comments;
  int keep_pis;
} zux_options;

void zux_options_init(zux_options *opt);

typedef struct zux_parser zux_parser;

typedef struct {
  zux_status status;
  uint64_t line;
  uint64_t column;
  uint64_t byte_offset;
  int expat_code;
  const char *message; /* owned by the parser; valid until free */
} zux_error;

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

typedef uint32_t zux_id;
#define ZUX_NONE 0xFFFFFFFFu

typedef enum {
  ZUX_DOCUMENT = 0,
  ZUX_ELEMENT,
  ZUX_TEXT,
  ZUX_COMMENT,
  ZUX_PI
} zux_node_type;

typedef struct zux_document zux_document;

zux_status zux_tree_parse(zux_document **out, const void *data, size_t n,
                          const zux_options *opt, zux_error *err);

/* Incremental form. Lets a caller feed arbitrary chunks -- so that R can
 * check for interrupts at a safe boundary between them, and so that zuhttp
 * can build a tree from response chunks without materializing the body. */
typedef struct zux_tree_builder zux_tree_builder;
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

zux_str zux_doc_version(const zux_document *d);
zux_str zux_doc_encoding(const zux_document *d);
int zux_doc_standalone(const zux_document *d);


#ifdef __cplusplus
}
#endif
#endif /* ZUX_H */
