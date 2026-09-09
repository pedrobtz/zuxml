# Parse an XML document

`xml_parse()` parses XML held in memory; `xml_read()` parses a file.

## Usage

``` r
xml_parse(
  x,
  encoding = NULL,
  comments = TRUE,
  pis = TRUE,
  allow_doctype = FALSE,
  max_depth = 256L,
  max_nodes = 1e+07,
  max_attrs = 4096L,
  max_text = 64 * 1024^2,
  max_memory = 1024 * 1024^2
)

xml_read(path, encoding = NULL, ...)
```

## Arguments

- x:

  A character string or a raw vector containing XML.

- encoding:

  Encoding of the input. `NULL` (default) lets the parser detect it from
  a byte-order mark or the XML declaration. An explicit value overrides
  the declaration, which is what an HTTP `charset` should do. Encodings
  that Expat cannot handle natively are transcoded with
  [`iconv()`](https://rdrr.io/r/base/iconv.html).

- comments, pis:

  Retain comment and processing-instruction nodes.

- allow_doctype:

  Accept a `DOCTYPE` declaration. An internal subset is rejected even
  when this is `TRUE`, because it is the only place a document can
  declare entities.

- max_depth, max_nodes, max_attrs, max_text, max_memory:

  Resource limits. Each has its own error condition.

- path:

  Path to a file.

- ...:

  Passed on to `xml_parse()`.

## Value

A `zuxml_document`.

## Details

Parsing is strict and secure by default: document type declarations are
rejected, general entities are not compiled in at all, and the limits
below bound what a hostile document can cost. See `vignette("security")`
once written, or
[`zuxml_info()`](https://pedrobtz.github.io/zuxml/reference/zuxml_info.md)
for the compiled-in policy.

## Examples

``` r
doc <- xml_parse("<catalog><book id='1'><title>XML</title></book></catalog>")
xml_text(xml_find(doc, "title"))
#> [1] "XML"
```
