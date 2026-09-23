# Conditions raised by zuxml

Every error zuxml raises carries a condition class, so that it can be
caught by kind rather than by matching the message, which is not stable.
Every class below is a subclass of `zuxml_error`.

## Details

- `zuxml_invalid_argument`:

  An argument was not usable: an `x` that is not a single string or a
  raw vector, an `encoding` other than UTF-8 for character input, a
  limit that is not a positive whole number, or a flag that is not
  `TRUE` or `FALSE`.

- `zuxml_parse_error`:

  The input is not well-formed XML, ends too early, or references an
  undefined entity.

- `zuxml_encoding_error`:

  The input is not valid in its encoding, or names an encoding that
  neither Expat nor [`iconv()`](https://rdrr.io/r/base/iconv.html) can
  read.

- `zuxml_doctype_error`:

  The document has a `DOCTYPE` declaration and `allow_doctype` is
  `FALSE`, or it has an internal subset, which is refused either way.

- `zuxml_limit_error`:

  A resource limit was reached. The subclasses `zuxml_depth_limit`,
  `zuxml_node_limit`, `zuxml_attr_limit`, `zuxml_text_limit` and
  `zuxml_memory_limit` name which one.
  [`xml_serialize()`](https://pedrobtz.github.io/zuxml/reference/xml_serialize.md)
  raises the parent class alone when a node's text is longer than an R
  string can hold.

- `zuxml_memory_error`:

  An allocation failed.

- `zuxml_cancelled`:

  A handler stopped the parse. It can only happen through the C API,
  where a downstream package supplies the handler; no exported R
  function raises it.

A condition raised by a parse carries `line`, `column` and
`byte_offset`, the position where the parser stopped; `status`, the C
status's enumerator name, such as `"ZUX_ERR_DEPTH_LIMIT"`; and
`expat_code`, Expat's own error code, which is `NA` when the failure was
not Expat's. It is there for diagnostics: do not branch on it. A limit
error also carries `limit`, the argument's name, such as `"max_depth"`,
and `limit_value`, the value it was given. A `zuxml_invalid_argument`
condition carries `arg`, the name of the argument at fault.

## Examples

``` r
tryCatch(
  xml_parse("<a><b></a>"),
  zuxml_parse_error = function(e) c(line = e$line, column = e$column)
)
#>   line column 
#>      1      8 
tryCatch(
  xml_parse("<a><b/></a>", max_depth = 1),
  zuxml_limit_error = function(e) e$limit
)
#> [1] "max_depth"
```
