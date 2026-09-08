/* Fuzz target: the round-trip property.
 * parse -> serialize -> parse must not crash, and the re-parse must succeed:
 * if zuxml can produce output it cannot itself read back, that is a bug in
 * the serializer's escaping or namespace handling.
 * Covers the serializer, escaping and namespace re-emission. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zux.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  zux_options o;
  zux_document *d1 = NULL, *d2 = NULL;
  zux_error e;
  char *s1 = NULL, *s2 = NULL;
  size_t l1 = 0, l2 = 0;

  zux_options_init(&o);
  o.max_nodes = 20000;
  o.max_text = 1 << 20;
  o.max_memory = 32u << 20;

  if (zux_tree_parse(&d1, data, size, &o, &e) != ZUX_OK || d1 == NULL)
    return 0;
  if (zux_serialize(d1, 0, &s1, &l1) != ZUX_OK || s1 == NULL) {
    zux_document_free(d1);
    return 0;
  }
  /* Anything zuxml serializes, zuxml must be able to re-parse. */
  if (zux_tree_parse(&d2, s1, l1, &o, &e) != ZUX_OK || d2 == NULL) {
    fprintf(stderr, "round-trip FAILED to re-parse own output: %s\n",
            zux_status_string(e.status));
    abort();
  }
  /* And serializing again must be a fixed point. */
  if (zux_serialize(d2, 0, &s2, &l2) == ZUX_OK && s2 != NULL) {
    if (l1 != l2 || memcmp(s1, s2, l1) != 0) {
      fprintf(stderr, "round-trip NOT a fixed point\n");
      abort();
    }
    free(s2);
  }
  free(s1);
  zux_document_free(d1);
  zux_document_free(d2);
  return 0;
}
