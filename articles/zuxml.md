# Getting started with zuxml

``` r

library(zuxml)
```

`zuxml` parses XML into an immutable tree and gives you a small,
vectorized API to walk it. This article covers the whole public surface
— there are only about twenty functions.

## This is XML, not HTML

Worth saying before you try it: **`zuxml` does not parse HTML**, and no
option changes that.

Expat is a strict, non-recovering XML parser. Real-world HTML — `<br>`,
unquoted attributes, `&nbsp;`, unclosed `<li>` — is not well-formed XML,
so it is an error, not something to recover from:

``` r

xml_parse("<p>a <br> b</p>")
#> Error:
#> ! XML parse error at line 1, column 13: mismatched tag
```

Only XHTML served as well-formed XML will parse. HTML is planned for a
sibling package that reuses this one’s tree and navigation API.

## Parsing

[`xml_parse()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
takes a string or a raw vector;
[`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
takes a file path.

``` r

doc <- xml_parse("
<catalog>
  <book id='b1'><title>The Annotated XML</title><price>29.99</price></book>
  <book id='b2'><title>Parsing for Fun</title><price>17.50</price></book>
</catalog>")

doc
#> <zuxml_document>
#> root:     catalog
#> nodes:    15   attributes: 2
#> memory:   4.9 Kb
#> encoding: not declared
```

## Navigating

Five functions cover traversal.
[`xml_root()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
gets the document element and
[`xml_parent()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
goes back up.
[`xml_children()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
returns *every* child node, including text and comments;
[`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
returns only element children;
[`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
searches descendants. The last two take an optional name filter —
[`xml_children()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
does not, because it is the “everything directly under here” call.

``` r

root <- xml_root(doc)
books <- xml_elements(root, "book")
books
#> <zuxml_nodeset[2]>
#> [1] <book> [2] <book>

xml_find(doc, "title")      # descendants, in document order
#> <zuxml_nodeset[2]>
#> [1] <title> [2] <title>
xml_name(xml_parent(books)) # and back up again
#> [1] "catalog" "catalog"
```

Note that
[`xml_children()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
and
[`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
differ — the whitespace between the tags above is real text content:

``` r

xml_type(xml_children(root))
#> [1] "text"    "element" "text"    "element" "text"
xml_type(xml_elements(root))
#> [1] "element" "element"
```

## Reading values

**Every accessor is vectorized.** Given a nodeset of length *n* you get
a result of length *n*, so there is usually no need to loop.

``` r

xml_name(books)
#> [1] "book" "book"
xml_attr(books, "id")
#> [1] "b1" "b2"
xml_text(xml_elements(books, "title"))
#> [1] "The Annotated XML" "Parsing for Fun"
as.numeric(xml_text(xml_elements(books, "price")))
#> [1] 29.99 17.50
```

[`xml_attrs()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
returns the full attribute set per node, as a list of named character
vectors:

``` r

xml_attrs(books)
#> [[1]]
#>   id 
#> "b1" 
#> 
#> [[2]]
#>   id 
#> "b2"
```

A node and a nodeset are the same object at different lengths, so the
usual vector operations work:

``` r

length(books)
#> [1] 2
books[[1]]
#> <zuxml_node element>
#> book 
#> attributes: 1   children: 2
xml_text(rev(books))
#> [1] "Parsing for Fun17.50"   "The Annotated XML29.99"
```

## Text and mixed content

[`xml_text()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
concatenates all descendant text by default. Set `recursive = FALSE` to
get only the node’s own direct text children — the distinction that
matters for mixed content.

``` r

p <- xml_root(xml_parse("<p>Hello <em>XML</em> world</p>"))

xml_text(p)
#> [1] "Hello XML world"
xml_text(p, recursive = FALSE)
#> [1] "Hello  world"
xml_text(p, trim = TRUE)
#> [1] "Hello XML world"
```

## Namespaces

Names are matched on `(namespace, local name)`. Prefixes are reported
but never decide identity, so two prefixes bound to the same URI are the
same name.

``` r

feed <- xml_parse('
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><title>First</title></entry>
  <entry><title>Second</title></entry>
</feed>')

ATOM <- "http://www.w3.org/2005/Atom"
entries <- xml_elements(xml_root(feed), "entry", ns = ATOM)
xml_text(xml_elements(entries, "title", ns = ATOM))
#> [1] "First"  "Second"
```

The `ns` argument has three modes:

``` r

ns_doc <- xml_parse('<r xmlns:a="urn:a"><a:i/><i/></r>')
r <- xml_root(ns_doc)

length(xml_elements(r, "i"))                # NULL: any namespace
#> [1] 2
length(xml_elements(r, "i", ns = "urn:a"))  # that URI
#> [1] 1
length(xml_elements(r, "i", ns = NA))       # no namespace at all
#> [1] 1
```

Individual parts of a name are available separately:

``` r

item <- xml_elements(r, "i", ns = "urn:a")
c(name = xml_name(item), local = xml_local(item),
  ns = xml_ns(item), prefix = xml_prefix(item))
#>    name   local      ns  prefix 
#>   "a:i"     "i" "urn:a"     "a"
```

## Writing

``` r

xml_serialize(books[[1]])
#> [1] "<book id=\"b1\"><title>The Annotated XML</title><price>29.99</price></book>"
```

Order, attributes, text and namespace *semantics* are preserved, so a
round trip is stable. Original formatting is not preserved — quote
style, whitespace between attributes and CDATA boundaries are not
retained.

``` r

once  <- xml_serialize(xml_parse("<a><b x='1'/></a>"))
twice <- xml_serialize(xml_parse(once))
identical(once, twice)
#> [1] TRUE
```

[`xml_write()`](https://pedrobtz.github.io/zuxml/reference/xml_serialize.md)
sends the same output to a file, and
[`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
reads one back:

``` r

f <- tempfile(fileext = ".xml")
xml_write(doc, f)
identical(xml_serialize(xml_read(f)), xml_serialize(doc))
#> [1] TRUE
```

## Document metadata

The XML declaration is kept, so its three fields are readable off the
document:

``` r

decl <- xml_parse('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a/>')
c(version = xml_version(decl), encoding = xml_encoding(decl))
#>  version encoding 
#>    "1.0"  "UTF-8"
xml_standalone(decl)
#> [1] TRUE
```

## Errors are typed

Parse failures carry a position and a specific condition class, so you
can catch exactly the case you care about.

``` r

xml_parse("<a>\n  <b>\n</a>")
#> Error:
#> ! XML parse error at line 3, column 2: mismatched tag
```

``` r

e <- tryCatch(xml_parse("<r><a/><b/></r>", max_nodes = 2),
              zuxml_limit_error = function(e) e)
class(e)[1:3]
#> [1] "zuxml_node_limit"  "zuxml_limit_error" "zuxml_error"
```

## Secure by default

`zuxml` is built for untrusted input. Document type declarations are
rejected, general-entity support is not compiled in at all, and every
resource limit has its own error class.

``` r

xml_parse('<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><foo>&xxe;</foo>')
#> Error:
#> ! document type declaration is not allowed (at line 1, column 14)
```

That means external entities cannot be expanded and no file is ever
opened — the protection is structural, not a setting you have to
remember. It also means a reference to an entity the document never
declared, such as `&nbsp;`, is an error rather than silently dropped
content.

[`zuxml_info()`](https://pedrobtz.github.io/zuxml/reference/zuxml_info.md)
reports the policy actually compiled into your build:

``` r

zuxml_info()
#> zuxml 0.1.0
#> Expat:             expat_2.8.4
#> Namespaces:        yes
#> DTD:               disabled
#> General entities:  disabled
#> External entities: not compiled in
#> Encoding:          UTF-8 internal (XML_Char = 1 byte)
#> Byte order:        little-endian
#> Entropy:           syscall(SYS_getrandom)
#> Context bytes:     1024
```

## For package authors

`zuxml` exposes its parser to other packages as a registered C function
table, so a downstream package can parse XML without linking against
Expat itself:

    # in DESCRIPTION
    Imports:    zuxml
    LinkingTo:  zuxml

``` c
#define ZUXML_DEFINE_API_GET
#include "zuxml.h"

const zuxml_api *api = zuxml_api_get();
```

`Imports:` alone is not enough — the consumer’s `NAMESPACE` needs a real
import directive (`importFrom(zuxml, zuxml_info)`), or zuxml’s namespace
is never loaded and `R_GetCCallable()` resolves nothing. The header
([`inst/include/zuxml.h`](https://github.com/pedrobtz/zuxml/blob/main/inst/include/zuxml.h))
documents the string-lifetime contract and the versioning rules; read it
before you keep any pointer a handler hands you.
