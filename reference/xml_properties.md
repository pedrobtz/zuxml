# Read properties of XML nodes

All of these are vectorized over a nodeset.

## Usage

``` r
xml_name(x)

xml_local(x)

xml_ns(x)

xml_prefix(x)

xml_type(x)

xml_attrs(x)

xml_attr(x, name, ns = NULL, default = NA_character_)

xml_text(x, recursive = TRUE, trim = FALSE)
```

## Arguments

- x:

  A node or nodeset.

- name:

  Attribute local name.

- ns:

  Namespace URI, `NA` for none, `NULL` for any.

- default:

  Value for nodes lacking the attribute.

- recursive:

  Concatenate text of all descendants (default) or only direct text
  children.

- trim:

  Trim leading and trailing whitespace from the result.

## Value

A character vector, except `xml_attrs()` which returns a list of named
character vectors.

## Examples

``` r
doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
xml_text(xml_root(doc))
#> [1] "Hello XML world"
xml_text(xml_root(doc), recursive = FALSE)
#> [1] "Hello  world"
```
