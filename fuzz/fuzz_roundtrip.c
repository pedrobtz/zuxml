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

/* Every input is tried under all four comment/PI settings rather than having
 * a byte of the input select one.
 *
 * Dropping a comment or a PI leaves two text nodes adjacent in the output,
 * and that is the only way a "]]>" can straddle a text-node boundary -- so
 * with both kept, as this target used to run, the seam was unreachable and
 * 2.5M executions could not find it. Selecting from the input instead would
 * not have helped: the option byte is also document content, so every seed
 * that starts with '<' pins the same setting, and a shrunk reproducer can
 * land on different options than the input that crashed.
 *
 * Four cheap parses per execution buys an unconditional guarantee that each
 * setting is exercised, and keeps every crash reproducible from its input
 * alone. */
static const struct { int comments, pis; } modes[] = {
  { 1, 1 }, { 0, 1 }, { 1, 0 }, { 0, 0 }
};

static void
roundtrip(const uint8_t *data, size_t size, int keep_comments, int keep_pis) {
  zux_options o;
  zux_document *d1 = NULL, *d2 = NULL;
  zux_error e;
  char *s1 = NULL, *s2 = NULL;
  size_t l1 = 0, l2 = 0;

  zux_options_init(&o);
  o.max_nodes = 20000;
  o.max_text = 1 << 20;
  o.max_memory = 32u << 20;
  o.keep_comments = keep_comments;
  o.keep_pis = keep_pis;

  if (zux_tree_parse(&d1, data, size, &o, &e) != ZUX_OK || d1 == NULL)
    return;
  if (zux_serialize(d1, 0, &s1, &l1) != ZUX_OK || s1 == NULL) {
    zux_document_free(d1);
    return;
  }
  /* Anything zuxml serializes, zuxml must be able to re-parse. */
  if (zux_tree_parse(&d2, s1, l1, &o, &e) != ZUX_OK || d2 == NULL) {
    fprintf(stderr,
            "round-trip FAILED to re-parse own output "
            "(comments=%d pis=%d): %s\n",
            keep_comments, keep_pis, zux_status_string(e.status));
    abort();
  }
  /* And serializing again must be a fixed point. */
  if (zux_serialize(d2, 0, &s2, &l2) == ZUX_OK && s2 != NULL) {
    if (l1 != l2 || memcmp(s1, s2, l1) != 0) {
      fprintf(stderr, "round-trip NOT a fixed point (comments=%d pis=%d)\n",
              keep_comments, keep_pis);
      abort();
    }
    free(s2);
  }
  free(s1);
  zux_document_free(d1);
  zux_document_free(d2);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  size_t m;
  for (m = 0; m < sizeof(modes) / sizeof(modes[0]); m++)
    roundtrip(data, size, modes[m].comments, modes[m].pis);
  return 0;
}
