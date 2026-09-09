# zuxml 0.1.0

First release.

## Parsing

* `xml_parse()` parses XML from a character string or a raw vector, and
  `xml_read()` from a file. Both build an immutable document tree.
* Encodings Expat handles natively are passed through; anything else is
  transcoded with `iconv()`, after which the (now stale) encoding declaration
  is overridden so it cannot mislead the parser.

## Navigation and accessors

* `xml_root()`, `xml_parent()`, `xml_children()`, `xml_elements()` and
  `xml_find()` walk the tree. `xml_elements()` and `xml_find()` take an
  optional name and namespace filter.
* `xml_name()`, `xml_local()`, `xml_ns()`, `xml_prefix()`, `xml_attr()`,
  `xml_attrs()`, `xml_text()` and `xml_type()` read node properties. All are
  vectorized over a nodeset, so *n* nodes give a result of length *n*.
* Names are matched on `(namespace, local name)` only. Prefixes are retained
  for serialization and diagnostics but never decide identity, so two
  prefixes bound to one URI are the same name.
* Nodesets behave like vectors: `[`, `[[`, `c()`, `rev()`, `length()` and
  `format()` methods are provided.
* `xml_version()`, `xml_encoding()` and `xml_standalone()` read the XML
  declaration.

## Writing

* `xml_serialize()` returns XML text and `xml_write()` sends it to a file.
  Order, attributes, text and namespace semantics round-trip; original
  formatting (quote style, inter-attribute whitespace, CDATA boundaries) does
  not.

## Security

* Document type declarations are rejected by default. `allow_doctype = TRUE`
  accepts one, but still rejects an internal subset, which is the only place a
  document can declare entities.
* External entity resolution is not compiled in at all, so no file or network
  access is reachable from a parse regardless of input or options.
* `max_depth`, `max_nodes`, `max_attrs`, `max_text` and `max_memory` bound
  what a hostile document can cost. Each raises its own condition, and all of
  them inherit from `zuxml_limit_error`.
* Parse failures are typed conditions carrying line, column and byte offset,
  under a `zuxml_error` parent.
* `zuxml_info()` reports the policy compiled into the installed build.

## For package authors

* A registered C function table lets other packages parse XML without linking
  against Expat themselves: `Imports: zuxml` plus `LinkingTo: zuxml`, then
  `zuxml_api_get()` from `<zuxml.h>`. The header documents the string-lifetime
  contract and the versioning rules.
* Tree construction, traversal, text concatenation, serialization and freeing
  are all iterative, so arbitrarily deep documents cannot overflow the C
  stack.

## Bundled software

* Expat 2.8.4 is bundled under `src/vendor/expat/`, so no system XML library
  is required. See `LICENSE.note` and `inst/COPYRIGHTS`.
