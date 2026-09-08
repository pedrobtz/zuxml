/* Parses stdin and prints the resulting status. Used by tools/run-mutation-check
 * to observe how behaviour changes when a guard is deliberately removed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zux.h"

int main(int argc, char **argv) {
  zux_options o;
  zux_document *d = NULL;
  zux_error e;
  char *buf = NULL;
  size_t cap = 0, n = 0;
  int c, i;

  zux_options_init(&o);
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--allow-doctype") == 0) o.allow_doctype = 1;
    else if (strncmp(argv[i], "--max-depth=", 12) == 0) o.max_depth = (uint32_t)atoi(argv[i]+12);
    else if (strncmp(argv[i], "--max-nodes=", 12) == 0) o.max_nodes = (uint32_t)atoi(argv[i]+12);
    else if (strncmp(argv[i], "--max-attrs=", 12) == 0) o.max_attrs = (uint32_t)atoi(argv[i]+12);
    else if (strncmp(argv[i], "--max-text=", 11) == 0) o.max_text = (size_t)atol(argv[i]+11);
  }

  while ((c = getchar()) != EOF) {
    if (n + 1 >= cap) { cap = cap ? cap * 2 : 256; buf = realloc(buf, cap); }
    buf[n++] = (char)c;
  }

  memset(&e, 0, sizeof e);
  zux_tree_parse(&d, buf ? buf : "", n, &o, &e);
  printf("%s\n", zux_status_string(e.status));
  zux_document_free(d);
  free(buf);
  return 0;
}
