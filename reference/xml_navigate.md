# Navigate an XML document

Every accessor is vectorized: given a nodeset of length `n` it returns a
result of length `n`, and the traversal functions return a single flat
nodeset.

## Usage

``` r
xml_root(x)

xml_parent(x)

xml_children(x)

xml_elements(x, name = NULL, ns = NULL)

xml_find(x, name = NULL, ns = NULL)
```

## Arguments

- x:

  A `zuxml_document`, node, or nodeset.

- name:

  Local name to match, or `NULL` for any.

- ns:

  Namespace URI, `NA` for none, `NULL` for any.

## Value

`xml_root()`, `xml_parent()`, `xml_children()`, `xml_elements()` and
`xml_find()` return a nodeset.

## Details

Filtering is uniform. `name` matches the *local* name. `ns = NULL`
matches any namespace, `ns = NA` matches only nodes in no namespace, and
a string matches that namespace URI. Matching never considers the
prefix: two prefixes bound to one URI are the same name.

## Examples

``` r
doc <- xml_parse("<r><a><b>1</b></a><b>2</b></r>")
xml_name(xml_children(xml_root(doc)))
#> [1] "a" "b"
xml_text(xml_find(doc, "b"))
#> [1] "1" "2"
```
