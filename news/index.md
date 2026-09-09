# Changelog

## zuxml 0.1.0

First release.

### Parsing

- [`xml_parse()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
  parses XML from a character string or a raw vector, and
  [`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
  from a file. Both build an immutable document tree.
- Encodings Expat handles natively are passed through; anything else is
  transcoded with [`iconv()`](https://rdrr.io/r/base/iconv.html), after
  which the (now stale) encoding declaration is overridden so it cannot
  mislead the parser.

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

### Security

- Document type declarations are rejected by default.
  `allow_doctype = TRUE` accepts one, but still rejects an internal
  subset, which is the only place a document can declare entities.
- External entity resolution is not compiled in at all, so no file or
  network access is reachable from a parse regardless of input or
  options.
- `max_depth`, `max_nodes`, `max_attrs`, `max_text` and `max_memory`
  bound what a hostile document can cost. Each raises its own condition,
  and all of them inherit from `zuxml_limit_error`.
- Parse failures are typed conditions carrying line, column and byte
  offset, under a `zuxml_error` parent.
- [`zuxml_info()`](https://pedrobtz.github.io/zuxml/reference/zuxml_info.md)
  reports the policy compiled into the installed build.

### For package authors

- A registered C function table lets other packages parse XML without
  linking against Expat themselves: `Imports: zuxml` plus
  `LinkingTo: zuxml`, then `zuxml_api_get()` from `<zuxml.h>`. The
  header documents the string-lifetime contract and the versioning
  rules.
- Tree construction, traversal, text concatenation, serialization and
  freeing are all iterative, so arbitrarily deep documents cannot
  overflow the C stack.

### Bundled software

- Expat 2.8.4 is bundled under `src/vendor/expat/`, so no system XML
  library is required. See `LICENSE.note` and `inst/COPYRIGHTS`.
