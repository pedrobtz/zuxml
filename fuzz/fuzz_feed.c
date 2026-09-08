/* Fuzz target: incremental feeding through the event seam.
 * The first byte picks a chunk size, so the fuzzer explores chunk boundaries
 * as well as document content -- the property the test suite asserts by
 * enumeration, explored here adversarially. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "zux.h"

static zux_status noop_start(void *c, const zux_name *n, const zux_attr *a,
                             size_t k) {
  (void)c; (void)n; (void)a; (void)k; return ZUX_OK;
}
static zux_status noop_end(void *c, const zux_name *n) {
  (void)c; (void)n; return ZUX_OK;
}
static zux_status noop_text(void *c, zux_str t) { (void)c; (void)t; return ZUX_OK; }
static zux_status noop_cmt(void *c, zux_str t) { (void)c; (void)t; return ZUX_OK; }
static zux_status noop_pi(void *c, zux_str a, zux_str b) {
  (void)c; (void)a; (void)b; return ZUX_OK;
}
static zux_status noop_decl(void *c, zux_str a, zux_str b, int s) {
  (void)c; (void)a; (void)b; (void)s; return ZUX_OK;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  zux_options o;
  zux_handlers h;
  zux_parser *p = NULL;
  zux_error e;
  size_t chunk, pos;

  if (size < 1)
    return 0;
  chunk = (size_t)data[0] + 1u;
  data++;
  size--;

  memset(&h, 0, sizeof h);
  h.start_element = noop_start; h.end_element = noop_end;
  h.text = noop_text; h.comment = noop_cmt; h.pi = noop_pi;
  h.xml_decl = noop_decl;

  zux_options_init(&o);
  o.max_nodes = 20000;
  o.max_text = 1 << 20;
  o.max_memory = 32u << 20;

  if (zux_parser_new(&p, &o, &h, NULL) != ZUX_OK)
    return 0;
  for (pos = 0; pos < size; pos += chunk) {
    size_t k = size - pos < chunk ? size - pos : chunk;
    if (zux_parser_feed(p, data + pos, k) != ZUX_OK)
      break;
  }
  zux_parser_finish(p);
  zux_parser_error(p, &e);
  zux_parser_free(p);
  return 0;
}
