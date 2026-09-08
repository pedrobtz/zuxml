# Serialize XML

Writes a node and its subtree back to XML text.

## Usage

``` r
xml_serialize(x, declaration = FALSE)

xml_write(x, path, declaration = TRUE)

# S3 method for class 'zuxml_nodeset'
as.character(x, ...)

# S3 method for class 'zuxml_document'
as.character(x, ...)
```

## Arguments

- x:

  A `zuxml_document`, node, or nodeset.

- declaration:

  Prepend an XML declaration.

- path:

  File to write to.

- ...:

  Ignored.

## Value

`xml_serialize()` returns a character vector, one element per node.
`xml_write()` returns `path` invisibly.

## Details

Element order, attribute order, text order, mixed-content interleaving
and namespace semantics are preserved. The original *formatting* is not:
parsing does not retain quote style, whitespace between attributes,
CDATA boundaries, entity spelling, or whether an empty element was
written as `<a/>` or `<a></a>`. `zuxml` is not a lossless source editor.

## Examples

``` r
doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
xml_serialize(doc)
#> [1] "<p>Hello <em>XML</em> world</p>"
```
