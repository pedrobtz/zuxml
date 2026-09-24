# zuxml

zuxml reads, navigates and writes XML in R, using a bundled copy of the
[Expat](https://github.com/libexpat/libexpat) parser, so no system XML
library is required. Documents are parsed into an immutable tree exposed
through a small vectorized navigation API. It is built for untrusted
input: document type declarations are rejected, external entity
resolution is not compiled in at all, and configurable limits bound
nesting depth and memory use.

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

[`xml_parse()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
takes a string or a raw vector and returns a document;
[`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
takes a file path.

``` r

library(zuxml)

doc <- xml_parse("<catalog>
  <book id='b1'><title>The Annotated XML</title><price>29.99</price></book>
  <book id='b2'><title>Parsing for Fun</title><price>17.50</price></book>
</catalog>")
```

[`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
searches descendants in document order and returns a nodeset
([`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
looks only at direct element children):

``` r

xml_find(doc, "title")
#> <zuxml_nodeset[2]>
#> [1] <title> [2] <title>
```

Every accessor is vectorized over a nodeset, so *n* nodes give a result
of length *n* and there is usually no loop to write:

``` r

books <- xml_elements(xml_root(doc), "book")

xml_attr(books, "id")
#> [1] "b1" "b2"

xml_text(xml_find(doc, "title"))
#> [1] "The Annotated XML" "Parsing for Fun"

as.numeric(xml_text(xml_find(doc, "price")))
#> [1] 29.99 17.50
```

Tables and lists come out as data frames and nested lists:

``` r

page <- xml_parse("<body>
  <table>
    <tr><th>fruit</th><th>price</th></tr>
    <tr><td>apple</td><td>1.20</td></tr>
    <tr><td>pear</td><td>0.90</td></tr>
  </table>
  <ul><li>fruit<ul><li>apple</li><li>pear</li></ul></li><li>bread</li></ul>
</body>")

xml_table(xml_find(page, "table"))[[1]]
#>   fruit price
#> 1 apple  1.20
#> 2  pear  0.90

# xml_elements(), not xml_find(): the nested <ul> is a descendant too.
str(xml_list(xml_elements(xml_root(page), "ul"))[[1]])
#> List of 2
#>  $ :List of 2
#>   ..$ text : chr "fruit"
#>   ..$ items:List of 2
#>   .. ..$ : chr "apple"
#>   .. ..$ : chr "pear"
#>  $ : chr "bread"
```

Note that this is XML, not HTML: Expat is strict and non-recovering, so
`<br>` and friends are an error, not something to recover from. The
[getting started
article](https://pedrobtz.github.io/zuxml/articles/zuxml.html) covers
namespaces, serialization, the resource limits and the C interface for
package authors.

## Using zuxml from C

There are two ways for another package to reach the parser, and they
suit different consumers.

**The registered function table** is the one to prefer. Declare

    Imports:    zuxml
    LinkingTo:  zuxml

in `DESCRIPTION`, and `importFrom(zuxml, zuxml_info)` in `NAMESPACE`.
The import is required: `Imports:` alone does not load zuxml, and the
table is registered only when it loads. Then include `<zuxml.h>`, which
resolves `zuxml_api_get()` through `R_GetCCallable()`. Nothing links
against Expat, and no Expat type appears in the consumer’s code. A zuxml
update that keeps the table’s version reaches the consumer without a
rebuild. One that changes it, which renames the registered table
(`zuxml_api_v2` to `zuxml_api_v3`), makes the lookup fail with an R
error until the consumer is rebuilt. That is deliberate: it is how a
changed struct layout is kept from being read with the old one. The
[getting started
article](https://pedrobtz.github.io/zuxml/articles/zuxml.html) documents
the table and the string-lifetime rules that go with it.

**The static archive** is for the case the table cannot serve: an
existing C library written against Expat’s own API, which would have to
be rewritten to use anything else. An installed zuxml carries

    zuxml/include/expat.h
    zuxml/include/expat_external.h
    zuxml/lib${R_ARCH}/libzuxml.a

where the archive holds the Expat implementation and no R code. `R_ARCH`
is empty on most platforms, so the archive is usually in `zuxml/lib`.
`LinkingTo: zuxml` puts the headers on the include path. A `configure`
script finds the archive, asking for `lib/<arch>` first and falling back
to `lib`, and writes its path into `src/Makevars` without adding an
`Imports:` dependency:

``` sh
ZUXML_LIB=$("${R_HOME}/bin/Rscript" --vanilla -e "arch <- .Platform\$r_arch; d <- if (nzchar(arch)) system.file('lib', arch, package = 'zuxml') else ''; if (!nzchar(d)) d <- system.file('lib', package = 'zuxml'); cat(d)")
sed "s|@ZUXML_LIB@|${ZUXML_LIB}|" src/Makevars.in > src/Makevars
```

``` make
PKG_CPPFLAGS = -DXML_STATIC
PKG_LIBS = '@ZUXML_LIB@/libzuxml.a'
```

The path is quoted because it comes from
[`system.file()`](https://rdrr.io/r/base/system.file.html), and on
Windows the user library often has a space in its path.

Four things to know before taking this route:

- **The build configuration is zuxml’s, not stock Expat’s.** `XML_GE` is
  0 and `XML_DTD` is undefined, so general entities, parameter entities
  and the external-entity machinery are compiled out rather than
  switched off. Do not define `XML_GE=1` on your own command line: you
  would get declarations for limiter functions the archive does not
  contain.
- **The rest of zuxml’s policy is not in the archive.** DOCTYPE
  rejection and the depth, node, attribute and text limits live in
  zuxml’s own parser, which an archive consumer does not call. In
  particular, if a document declares an entity in an internal subset, a
  reference to it is not an error: it reaches your handler as literal
  text such as `&e;`. Install a DOCTYPE handler and limits yourself, as
  [`vignette("linking")`](https://pedrobtz.github.io/zuxml/articles/linking.md)
  shows.
- **`-DXML_STATIC` is recommended, not required.** Stock
  `expat_external.h` adds `__declspec(dllimport)` only under Microsoft’s
  compiler, which Rtools is not. The define is still accurate, and costs
  nothing.
- **You get your own copy of Expat**, linked into your shared object. It
  shares no state with the one inside `zuxml.so`, and a zuxml update,
  security fixes included, does not reach your users until you rebuild
  and re-release.
