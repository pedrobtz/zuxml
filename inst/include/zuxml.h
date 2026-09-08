/* zuxml public C API.
 *
 * Downstream packages use this via:
 *
 *     Imports:    zuxml     (guarantees the package is installed and loaded,
 *                            so the symbols below are registered)
 *     LinkingTo:  zuxml     (puts this header on the include path)
 *
 * and call through the registered function table -- see zuxml_api_get()
 * below. No downstream package ever links against Expat, and no Expat type
 * appears anywhere in this header.
 *
 * ---- string lifetime contract -------------------------------------------
 * This is the single most important rule here, and the source of every
 * memory bug if ignored:
 *
 *   * Strings passed to a HANDLER are BORROWED and valid ONLY until that
 *     handler returns. They are NOT NUL-terminated. Copy anything you keep.
 *
 *   * Strings returned by a DOCUMENT accessor are OWNED by the document, ARE
 *     NUL-terminated, and stay valid until zux_document_free().
 *
 * Input buffers passed to feed() are caller-owned and are never retained
 * after the call returns.
 * ------------------------------------------------------------------------ */

#ifndef ZUXML_H
#define ZUXML_H

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

typedef struct {
  const char *ptr;
  size_t len;
} zux_str;

/* Matching is on (uri, local) only. `prefix` is retained for serialization
 * and diagnostics and must never decide identity: two prefixes bound to one
 * URI are the same name. */
typedef struct {
  zux_str uri;
  zux_str local;
  zux_str prefix;
} zux_name;

typedef struct {
  zux_name name;
  zux_str value;
} zux_attr;

/* Return ZUX_OK to continue, or any error status to stop the parse; that
 * status becomes the parse result. This is how cancellation works. Any
 * handler may be NULL. */
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
  size_t max_text;
  size_t max_memory;
  const char *encoding; /* NULL = autodetect */
  int allow_doctype;
  int keep_comments;
  int keep_pis;
} zux_options;

#define ZUX_MESSAGE_MAX 256

typedef struct {
  zux_status status;
  uint64_t line;
  uint64_t column;
  uint64_t byte_offset;
  int expat_code; /* diagnostics only; do not switch on this */
  /* Inline, not a pointer. The tree entry points free their parser before
   * returning, so a borrowed pointer here would always dangle: the message is
   * copied in and owned by the caller's own zux_error. */
  char message[ZUX_MESSAGE_MAX];
} zux_error;

typedef uint32_t zux_id;
#define ZUX_NONE 0xFFFFFFFFu

typedef enum {
  ZUX_DOCUMENT = 0,
  ZUX_ELEMENT,
  ZUX_TEXT,
  ZUX_COMMENT,
  ZUX_PI
} zux_node_type;

typedef struct zux_parser zux_parser;
typedef struct zux_document zux_document;
typedef struct zux_tree_builder zux_tree_builder;

/* ---- registered function table ------------------------------------------
 * struct_size is the ONLY version discriminator. Fields are appended, never
 * reordered or removed, so a consumer built against an older header keeps
 * working: compare struct_size against offsetof() for the member you want
 * before calling it.
 * ------------------------------------------------------------------------ */
typedef struct {
  uint32_t struct_size;

  void (*options_init)(zux_options *opt);
  const char *(*status_string)(zux_status s);

  zux_status (*parser_new)(zux_parser **out, const zux_options *opt,
                           const zux_handlers *h, void *ctx);
  zux_status (*parser_feed)(zux_parser *p, const void *data, size_t n);
  zux_status (*parser_finish)(zux_parser *p);
  void (*parser_free)(zux_parser *p);
  void (*parser_error)(const zux_parser *p, zux_error *out);

  zux_status (*tree_parse)(zux_document **out, const void *data, size_t n,
                           const zux_options *opt, zux_error *err);
  zux_status (*tree_begin)(zux_tree_builder **out, const zux_options *opt);
  zux_status (*tree_feed)(zux_tree_builder *b, const void *data, size_t n);
  zux_status (*tree_end)(zux_tree_builder *b, zux_document **out,
                         zux_error *err);
  void (*tree_error)(const zux_tree_builder *b, zux_error *out);
  void (*tree_abort)(zux_tree_builder *b);
  void (*document_free)(zux_document *d);

  zux_id (*root)(const zux_document *d);
  uint32_t (*node_count)(const zux_document *d);
  int (*node_kind)(const zux_document *d, zux_id id);
  zux_id (*parent)(const zux_document *d, zux_id id);
  zux_id (*first_child)(const zux_document *d, zux_id id);
  zux_id (*next_sibling)(const zux_document *d, zux_id id);
  zux_name (*node_name)(const zux_document *d, zux_id id);
  zux_str (*node_text)(const zux_document *d, zux_id id);
  uint32_t (*attr_count)(const zux_document *d, zux_id id);
  zux_attr (*attr_at)(const zux_document *d, zux_id id, uint32_t i);

  zux_status (*serialize)(const zux_document *d, zux_id id, char **out,
                          size_t *out_len);
} zuxml_api;

#define ZUXML_API_HAS(api, member)                                            \
  ((api)->struct_size >= offsetof(zuxml_api, member) + sizeof((api)->member))

#ifdef ZUXML_DEFINE_API_GET
/* Downstream: define ZUXML_DEFINE_API_GET in exactly one translation unit,
 * after including <R.h> and <R_ext/Rdynload.h>, to emit this accessor. */
static const zuxml_api *
zuxml_api_get(void) {
  static const zuxml_api *api = NULL;
  if (api == NULL) {
    const zuxml_api *(*fn)(void)
        = (const zuxml_api *(*)(void))R_GetCCallable("zuxml", "zuxml_api_v1");
    api = fn();
  }
  return api;
}
#endif

#ifdef __cplusplus
}
#endif
#endif /* ZUXML_H */
