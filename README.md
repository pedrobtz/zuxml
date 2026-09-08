# zuxml

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/R-CMD-check.yaml)
[![hardening](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml/badge.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/hardening.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zuxml/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zuxml/actions/workflows/coverage.yaml)
<!-- badges: end -->

zuxml reads, navigates and writes XML in R, using a bundled copy of the
[Expat](https://github.com/libexpat/libexpat) parser, so no system XML library is
required. Documents are parsed into an immutable tree exposed through a small
vectorized navigation API. It is built for untrusted input: document type
declarations are rejected, external entity resolution is not compiled in at all,
and configurable limits bound nesting depth and memory use.

## Installation

Install the development version from GitHub:

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
