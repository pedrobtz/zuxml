# zuxml

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml)
[![hardening](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml)
[![native-checks](https://github.com/pedrobtz/zuxml/actions/workflows/native-checks.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/native-checks.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zuxml/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/coverage.yaml)
<!-- badges: end -->

zuxml reads, navigates and writes XML in R, using a bundled copy of the
[Expat](https://github.com/libexpat/libexpat) parser, so no system XML library is
required. Documents are parsed into an immutable tree exposed through a small
vectorized navigation API. It is built for untrusted input: document type
declarations are rejected, external entity resolution is not compiled in at all,
and configurable limits bound nesting depth and memory use.

## Installation

``` r
install.packages("zuxml")
```

Or the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("pedrobtz/zuxml")
```

## Usage

`xml_parse()` takes a string or a raw vector and returns a document; `xml_read()`
takes a file path.

``` r
library(zuxml)

doc <- xml_parse("<catalog>
  <book id='b1'><title>The Annotated XML</title><price>29.99</price></book>
  <book id='b2'><title>Parsing for Fun</title><price>17.50</price></book>
</catalog>")
```

`xml_find()` searches descendants in document order and returns a nodeset
(`xml_elements()` looks only at direct element children):

``` r
xml_find(doc, "title")
#> <zuxml_nodeset[2]>
#> [1] <title> [2] <title>
```

Every accessor is vectorized over a nodeset, so *n* nodes give a result of length
*n* and there is usually no loop to write:

``` r
books <- xml_elements(xml_root(doc), "book")

xml_attr(books, "id")
#> [1] "b1" "b2"

xml_text(xml_find(doc, "title"))
#> [1] "The Annotated XML" "Parsing for Fun"

as.numeric(xml_text(xml_find(doc, "price")))
#> [1] 29.99 17.50
```

Note that this is XML, not HTML: Expat is strict and non-recovering, so `<br>` and
friends are an error, not something to recover from. The [getting started
article](https://pedrobtz.github.io/zuxml/articles/zuxml.html) covers namespaces,
serialization, the resource limits and the C interface for package authors.

## Using zuxml from C

There are two ways for another package to reach the parser, and they suit
different consumers.

**The registered function table** is the one to prefer. Declare

```
Imports:    zuxml
LinkingTo:  zuxml
```

and include `<zuxml.h>`, which resolves `zuxml_api_get()` through
`R_GetCCallable()`. Nothing links against Expat, no Expat type appears in the
consumer's code, and a zuxml update reaches it without a rebuild. The
[getting started article](https://pedrobtz.github.io/zuxml/articles/zuxml.html)
documents the table and the string-lifetime rules that go with it.

**The static archive** is for the case the table cannot serve: an existing C
library written against Expat's own API, which would have to be rewritten to
use anything else. An installed zuxml carries

```
zuxml/include/expat.h
zuxml/include/expat_external.h
zuxml/lib/libzuxml.a
```

where the archive holds the Expat implementation and no R code. `LinkingTo:
zuxml` puts the headers on the include path; the archive's location comes from
`system.file("lib", package = "zuxml")`, which a `configure` script can resolve
into `src/Makevars` without adding an `Imports:` dependency:

``` sh
ZUXML_LIB=$("${R_HOME}/bin/Rscript" -e 'cat(system.file("lib", package = "zuxml"))')
sed "s|@ZUXML_LIB@|${ZUXML_LIB}|" src/Makevars.in > src/Makevars
```

``` make
PKG_CPPFLAGS = -DXML_STATIC
PKG_LIBS = @ZUXML_LIB@/libzuxml.a
```

Three things to know before taking this route:

- **The build configuration is zuxml's, not stock Expat's.** `XML_GE` is 0 and
  `XML_DTD` is undefined, so general entities, parameter entities and the
  external-entity machinery are compiled out rather than switched off. Any
  entity reference beyond the five built-ins and numeric character references
  is a parse error. Do not define `XML_GE=1` on your own command line: you
  would get declarations for limiter functions the archive does not contain.
- **`-DXML_STATIC` is required on Windows**, where `expat_external.h` would
  otherwise mark every declaration `__declspec(dllimport)`.
- **You get your own copy of Expat**, linked into your shared object. It shares
  no state with the one inside `zuxml.so`, and a zuxml update does not reach it
  until you rebuild.

