/* Fuzz target: whole-document tree construction.
 * Covers the tree builder, attribute copying, text coalescing and interning. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "zux.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  zux_options o;
  zux_document *d = NULL;
  zux_error e;

  zux_options_init(&o);
  /* Keep limits low so the fuzzer explores parser behaviour rather than
   * spending its budget allocating memory. */
  o.max_nodes = 20000;
  o.max_text = 1 << 20;
  o.max_memory = 32u << 20;
  o.max_depth = 256;
  /* Let the fuzzer reach the allow_doctype branch too. */
  o.allow_doctype = (size > 0 && (data[0] & 1)) ? 1 : 0;

  if (zux_tree_parse(&d, data, size, &o, &e) == ZUX_OK && d != NULL) {
    zux_id id;
    uint32_t n = zux_node_count(d);
    for (id = 0; id < n; id++) {
      uint32_t i, na = zux_attr_count(d, id);
      (void)zux_node_kind(d, id);
      (void)zux_parent(d, id);
      (void)zux_first_child(d, id);
      (void)zux_next_sibling(d, id);
      (void)zux_node_name(d, id);
      (void)zux_node_text(d, id);
      for (i = 0; i < na; i++)
        (void)zux_attr_at(d, id, i);
    }
    (void)zux_root(d);
    (void)zux_doc_version(d);
    (void)zux_doc_encoding(d);
    zux_document_free(d);
  }
  return 0;
}
