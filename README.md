
# zuxml

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml)
[![hardening](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml)
<!-- badges: end -->

Read, navigate and write XML in R. `zuxml` bundles a copy of the
[Expat](https://libexpat.github.io/) parser, so it needs no system XML
library, and parses documents into an immutable tree with a small vectorized
navigation API.

It is built for untrusted input. Document type declarations are rejected,
general entities are not compiled in at all, external entity resolution is
absent from the build rather than merely switched off, and every resource
limit raises its own error condition.

## This is XML, not HTML

Worth saying before you try it: **`zuxml` does not parse HTML**, and no option
changes that.

Expat is a strict, non-recovering XML parser. Real-world HTML — `<br>`,
unquoted attributes, `&nbsp;`, unclosed `<li>` — is not well-formed XML, so it
is an error, not something to recover from:

``` r
xml_parse("<p>a <br> b</p>")
#> Error : XML parse error at line 1, column 13: mismatched tag
```

Only XHTML served as well-formed XML will parse. HTML is planned for a sibling
package that reuses this one's tree and navigation API.

## Installation

``` r
# install.packages("pak")
pak::pak("pedrobtz/zuxml")
```

## Usage

``` r
library(zuxml)

doc <- xml_parse("
<catalog>
  <book id='b1'><title>The Annotated XML</title><price>29.99</price></book>
  <book id='b2'><title>Parsing for Fun</title><price>17.50</price></book>
</catalog>")

books <- xml_elements(xml_root(doc), "book")
```

Every accessor is vectorized over a nodeset, so a set of *n* nodes gives a
result of length *n* and there is usually no loop to write:

``` r
xml_attr(books, "id")
#> [1] "b1" "b2"

xml_text(xml_elements(books, "title"))
#> [1] "The Annotated XML" "Parsing for Fun"

as.numeric(xml_text(xml_elements(books, "price")))
#> [1] 29.99 17.50
```

`xml_children()` returns every child node, `xml_elements()` only element
children, and `xml_find()` searches descendants in document order:

``` r
xml_find(doc, "title")
#> <zuxml_nodeset[2]>
#> [1] <title> [2] <title>
```

Names are matched on `(namespace, local name)`; prefixes are reported but
never decide identity. `xml_serialize()` and `xml_write()` go back out to
text, preserving order, attributes and namespace semantics.

## Secure by default

The protections are structural, not settings you have to remember:

``` r
xml_parse('<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><foo>&xxe;</foo>')
#> Error : document type declaration is not allowed (at line 1, column 14)
```

No file is opened and no entity is expanded, because neither capability is
compiled in. Resource limits bound what a hostile document can cost — nesting
depth, node count, attribute count, text size and total memory — and each
raises a distinct, catchable condition:

``` r
e <- tryCatch(xml_parse("<r><a/><b/></r>", max_nodes = 2),
              zuxml_limit_error = function(e) e)
class(e)[1:3]
#> [1] "zuxml_node_limit"  "zuxml_limit_error" "zuxml_error"

conditionMessage(e)
#> [1] "maximum node count exceeded (at line 1, column 7)"
```

`zuxml_info()` reports the policy actually compiled into your build.

## For package authors

`zuxml` exposes its parser to other packages as a registered C function table,
so a downstream package can parse XML without linking against Expat itself:

``` r
# in DESCRIPTION
Imports:    zuxml
LinkingTo:  zuxml
```

``` c
#define ZUXML_DEFINE_API_GET
#include "zuxml.h"

const zuxml_api *api = zuxml_api_get();
```

`Imports:` alone is not enough — the consumer's `NAMESPACE` needs a real
import directive (`importFrom(zuxml, zuxml_info)`), or zuxml's namespace is
never loaded and `R_GetCCallable()` resolves nothing. The header
([`inst/include/zuxml.h`](inst/include/zuxml.h)) documents the string-lifetime
contract and the versioning rules; read it before you keep any pointer a
handler hands you.

## License

MIT. The bundled Expat sources under `src/vendor/expat/` are also MIT but held
by different copyright holders — see `LICENSE.note` and `inst/COPYRIGHTS`.
