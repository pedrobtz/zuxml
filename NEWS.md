# zuxml 0.1.0

First release.

## Parsing

* `xml_parse()` parses XML from a single string or a raw vector, and
  `xml_read()` from a file, a URL or a connection. Both build an immutable
  document tree. A character vector of another length is an error rather
  than being joined silently: join the lines of `readLines()` with `"\n"`
  first.
* `xml_read()` streams: a string starting with `http://`, `https://`,
  `ftp://`, `ftps://` or `file://` is opened with `url()`, anything else
  with `file()`, and a connection (`gzfile()`, `rawConnection()`, a socket)
  is accepted as is. Bytes are fed to the parser as they are read, so the
  body is never held whole; only an encoding that must go through
  `iconv()` is read in full first. An unopened connection is opened in
  binary mode and closed afterwards; an open one must be binary, and is
  left open.
* Encodings Expat handles natively are passed through, under any of their
  common spellings (`"latin1"`, `"UTF8"`, `"ASCII"`); anything else is
  transcoded with `iconv()`, after which the (now stale) encoding declaration
  is overridden so it cannot mislead the parser. A character string is
  already decoded, so `encoding` must be `NULL` or UTF-8 for one.

## Navigation and accessors

* `xml_root()`, `xml_parent()`, `xml_children()`, `xml_elements()` and
  `xml_find()` walk the tree. `xml_elements()` and `xml_find()` take an
  optional name and namespace filter.
* `xml_find_first()` returns one node per input: the first matching
  descendant, or a missing node where there is none. Every accessor gives
  `NA` for a missing node, so per-record lookups stay aligned when a field
  is absent, which a flat `xml_find()` cannot do.
* `xml_name()`, `xml_local()`, `xml_ns()`, `xml_prefix()`, `xml_attr()`,
  `xml_attrs()`, `xml_text()` and `xml_type()` read node properties. All are
  vectorized over a nodeset, so *n* nodes give a result of length *n*.
* Text nodes are maximal: adjacent character data is always one node,
  whatever the input chunk boundaries were and whether or not `comments` or
  `pis` dropped a node that sat in the middle of it.
* Names are matched on `(namespace, local name)` only. Prefixes are retained
  for serialization and diagnostics but never decide identity, so two
  prefixes bound to one URI are the same name.
* Nodesets behave like vectors: `[`, `[[`, `c()`, `rev()`, `length()` and
  `format()` methods are provided.
* `xml_version()`, `xml_encoding()` and `xml_standalone()` read the XML
  declaration.

## Extracting tables and lists

* `xml_table()` turns `table` elements into data frames: rows from the table
  and its `thead`, `tbody` and `tfoot`, `colspan` and `rowspan` expanded,
  header detected from a row of `th` cells, every column character. The
  expanded size is bounded by `max_cells`, so a hostile span cannot become a
  huge allocation.
* `xml_list()` turns `ul` and `ol` elements into lists, with nested lists
  as nested items.
* Both read XML, XHTML included, and apply no HTML parsing rules.

## Writing

* `xml_serialize()` returns XML text and `xml_write()` sends it to a file.
  Order, attributes, text and namespace semantics round-trip; original
  formatting (quote style, inter-attribute whitespace, CDATA boundaries) does
  not.
* Output is always UTF-8, and a prepended declaration says so whatever the
  source document declared. `declaration = TRUE` applies to a single node, so
  it cannot produce a file carrying one declaration per node.

## Security

* Document type declarations are rejected by default. `allow_doctype = TRUE`
  accepts one, but still rejects an internal subset, which is the only place a
  document can declare entities.
* External entity resolution is not compiled in at all, so no file or network
  access is reachable from a parse regardless of input or options.
* `max_depth`, `max_nodes`, `max_attrs`, `max_text` and `max_memory` bound
  what a hostile document can cost. Each raises its own condition, and all of
  them inherit from `zuxml_limit_error`. A limit must be a positive whole
  number, or `Inf` for the largest the parser can represent; anything else,
  including a value above that, is an error, never replaced by the default.
* Every error is a typed condition under a `zuxml_error` parent. Parse
  failures carry line, column, byte offset, the C status and Expat's error
  code; limit failures also name the limit and its value. Unusable arguments
  raise `zuxml_invalid_argument`. See `?"zuxml-conditions"`.
* `zuxml_info()` reports the policy compiled into the installed build.

## For package authors

* A registered C function table lets other packages parse XML without linking
  against Expat themselves: `Imports: zuxml` plus `LinkingTo: zuxml`, an
  `importFrom(zuxml, ...)` directive in `NAMESPACE` (without it zuxml's
  namespace is never loaded and the table is never registered), then
  `zuxml_api_get()` from `<zuxml.h>`. The header documents the string-lifetime
  contract and the versioning rules, and compiles cleanly as C and C++ under
  `-Wall -Wextra -Werror`.
* Tree construction, traversal, text concatenation, serialization and freeing
  are all iterative, so arbitrarily deep documents cannot overflow the C
  stack.
* An installed zuxml also ships `lib${R_ARCH}/libzuxml.a` (plain `lib/` where
  R sets no architecture) together with Expat's
  `expat.h` and `expat_external.h`, so a package whose C code is written
  against Expat itself can link the parser statically through `LinkingTo`
  rather than being rewritten around the function table. The table remains
  the recommended interface; see "Using zuxml from C" in the README for the
  differences that come with the archive, the parser policy compiled into it
  among them.

## Bundled software

* Expat 2.8.4 is bundled under `src/vendor/expat/`, so no system XML library
  is required. See `LICENSE.note` and `inst/COPYRIGHTS`.
