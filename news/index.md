# Changelog

## zuxml 0.1.0

First release.

### Parsing

- [`xml_parse()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
  parses XML from a single string or a raw vector, and
  [`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
  from a file. Both build an immutable document tree. A character vector
  of another length is an error rather than being joined silently: join
  the lines of [`readLines()`](https://rdrr.io/r/base/readLines.html)
  with `"\n"` first.
- Encodings Expat handles natively are passed through, under any of
  their common spellings (`"latin1"`, `"UTF8"`, `"ASCII"`); anything
  else is transcoded with
  [`iconv()`](https://rdrr.io/r/base/iconv.html), after which the (now
  stale) encoding declaration is overridden so it cannot mislead the
  parser. A character string is already decoded, so `encoding` must be
  `NULL` or UTF-8 for one.

### Navigation and accessors

- [`xml_root()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md),
  [`xml_parent()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md),
  [`xml_children()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md),
  [`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
  and
  [`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
  walk the tree.
  [`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
  and
  [`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
  take an optional name and namespace filter.
- [`xml_name()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_local()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_ns()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_prefix()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_attr()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_attrs()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
  [`xml_text()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
  and
  [`xml_type()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
  read node properties. All are vectorized over a nodeset, so *n* nodes
  give a result of length *n*.
- Text nodes are maximal: adjacent character data is always one node,
  whatever the input chunk boundaries were and whether or not `comments`
  or `pis` dropped a node that sat in the middle of it.
- Names are matched on `(namespace, local name)` only. Prefixes are
  retained for serialization and diagnostics but never decide identity,
  so two prefixes bound to one URI are the same name.
- Nodesets behave like vectors: `[`, `[[`,
  [`c()`](https://rdrr.io/r/base/c.html),
  [`rev()`](https://rdrr.io/r/base/rev.html),
  [`length()`](https://rdrr.io/r/base/length.html) and
  [`format()`](https://rdrr.io/r/base/format.html) methods are provided.
- [`xml_version()`](https://pedrobtz.github.io/zuxml/reference/xml_metadata.md),
  [`xml_encoding()`](https://pedrobtz.github.io/zuxml/reference/xml_metadata.md)
  and
  [`xml_standalone()`](https://pedrobtz.github.io/zuxml/reference/xml_metadata.md)
  read the XML declaration.

### Writing

- [`xml_serialize()`](https://pedrobtz.github.io/zuxml/reference/xml_serialize.md)
  returns XML text and
  [`xml_write()`](https://pedrobtz.github.io/zuxml/reference/xml_serialize.md)
  sends it to a file. Order, attributes, text and namespace semantics
  round-trip; original formatting (quote style, inter-attribute
  whitespace, CDATA boundaries) does not.
- Output is always UTF-8, and a prepended declaration says so whatever
  the source document declared. `declaration = TRUE` applies to a single
  node, so it cannot produce a file carrying one declaration per node.

### Security

- Document type declarations are rejected by default.
  `allow_doctype = TRUE` accepts one, but still rejects an internal
  subset, which is the only place a document can declare entities.
- External entity resolution is not compiled in at all, so no file or
  network access is reachable from a parse regardless of input or
  options.
- `max_depth`, `max_nodes`, `max_attrs`, `max_text` and `max_memory`
  bound what a hostile document can cost. Each raises its own condition,
  and all of them inherit from `zuxml_limit_error`. A limit must be a
  positive whole number, or `Inf` for the largest the parser can
  represent; anything else, including a value above that, is an error,
  never replaced by the default.
- Every error is a typed condition under a `zuxml_error` parent. Parse
  failures carry line, column, byte offset, the C status and Expat’s
  error code; limit failures also name the limit and its value. Unusable
  arguments raise `zuxml_invalid_argument`. See
  [`?"zuxml-conditions"`](https://pedrobtz.github.io/zuxml/reference/zuxml-conditions.md).
- [`zuxml_info()`](https://pedrobtz.github.io/zuxml/reference/zuxml_info.md)
  reports the policy compiled into the installed build.

### For package authors

- A registered C function table lets other packages parse XML without
  linking against Expat themselves: `Imports: zuxml` plus
  `LinkingTo: zuxml`, an `importFrom(zuxml, ...)` directive in
  `NAMESPACE` (without it zuxml’s namespace is never loaded and the
  table is never registered), then `zuxml_api_get()` from `<zuxml.h>`.
  The header documents the string-lifetime contract and the versioning
  rules, and compiles cleanly as C and C++ under
  `-Wall -Wextra -Werror`.
- Tree construction, traversal, text concatenation, serialization and
  freeing are all iterative, so arbitrarily deep documents cannot
  overflow the C stack.
- An installed zuxml also ships `lib/libzuxml.a` together with Expat’s
  `expat.h` and `expat_external.h`, so a package whose C code is written
  against Expat itself can link the parser statically through
  `LinkingTo` rather than being rewritten around the function table. The
  table remains the recommended interface; see “Using zuxml from C” in
  the README for the differences that come with the archive, the parser
  policy compiled into it among them.

### Bundled software

- Expat 2.8.4 is bundled under `src/vendor/expat/`, so no system XML
  library is required. See `LICENSE.note` and `inst/COPYRIGHTS`.
