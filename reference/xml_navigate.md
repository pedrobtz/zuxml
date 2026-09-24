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

xml_find_first(x, name = NULL, ns = NULL)
```

## Arguments

- x:

  A `zuxml_document`, node, or nodeset.

- name:

  Local name to match, or `NULL` for any.

- ns:

  Namespace URI, `NA` for none, `NULL` for any.

## Value

`xml_root()`, `xml_parent()`, `xml_children()`, `xml_elements()`,
`xml_find()` and `xml_find_first()` return a nodeset.
`xml_find_first()`'s has the length of `x`.

## Details

Filtering is uniform. `name` matches the *local* name. `ns = NULL`
matches any namespace, `ns = NA` matches only nodes in no namespace, and
a string matches that namespace URI. Matching never considers the
prefix: two prefixes bound to one URI are the same name.

`xml_elements()` and `xml_find()` return elements only, including when
`name` is `NULL`: they search by name, and only elements have one. Use
`xml_children()` to reach text, comment and processing-instruction
nodes, which it returns along with elements.

`xml_find()` returns one flat nodeset, so it cannot keep results aligned
with its input: if one `<book>` has no `<title>`, the titles no longer
line up with the books. `xml_find_first()` returns exactly one node per
input node, its first matching descendant in document order, or a
**missing node** when there is none.

A missing node gives `NA` from every accessor
([`xml_name()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
[`xml_text()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
[`xml_attr()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md),
[`xml_type()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
and the rest) and from
[`xml_serialize()`](https://pedrobtz.github.io/zuxml/reference/xml_serialize.md),
and an empty named vector from
[`xml_attrs()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md).
Traversals skip it: it has no parent, children or descendants.
[`xml_attr()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)'s
`default` applies to it, as to any node lacking the attribute.

## Examples

``` r
doc <- xml_parse("<r><a><b>1</b></a><b>2</b></r>")
xml_name(xml_children(xml_root(doc)))
#> [1] "a" "b"
xml_text(xml_find(doc, "b"))
#> [1] "1" "2"

# One result per book, NA where a book has no title.
books <- xml_elements(xml_root(xml_parse(
  "<r><book><title>A</title></book><book/><book><title>C</title></book></r>")))
xml_text(xml_find_first(books, "title"))
#> [1] "A" NA  "C"
```
