# Streaming large documents

``` r

library(zuxml)
```

## Who this is for

Read this if you are writing a package that receives XML in pieces — an
HTTP response arriving in chunks, a decompressor emitting blocks — and
you would rather not hold the whole body in memory before parsing it.

**In 0.1.0 the incremental interface is a C interface.** From R there is
[`xml_parse()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
for a string or raw vector and
[`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
for a file, URL or connection.
[`xml_read()`](https://pedrobtz.github.io/zuxml/reference/xml_parse.md)
does stream – it feeds the connection to the parser as it reads it, so a
[`url()`](https://rdrr.io/r/base/connections.html) or
[`gzfile()`](https://rdrr.io/r/base/connections.html) body is never
materialized – but what comes back is still the complete tree. An
R-level pull or callback API, which would hand you events instead of a
tree, is planned but is deliberately not in this release; the C seam it
would sit on is what exists today, and it is what a downstream package
uses. If you are working purely in R, this vignette will not give you
anything to call — the [getting started
article](https://pedrobtz.github.io/zuxml/articles/zuxml.html) covers
the surface you want.

## Why the seam is C, not R

Parsing builds the tree in a C arena with no R allocation at all; R
handles are created lazily when you first touch a node. A
callback-per-event API in R would undo exactly that property, because
every event would have to materialize an R object to hand to the
callback. Putting the seam in C keeps the cost where it belongs and lets
a consumer decide for itself whether an event is worth representing.

## The contract that makes chunking safe

The guarantee worth stating first, because everything else depends on
it: **the result is byte-for-byte independent of how the input is
split.** Feeding a document as one 1 MiB buffer, as 4 KiB blocks, or one
byte at a time produces an identical tree.

That is not an aspiration. It is an acceptance criterion for the
package, tested by feeding every fixture at sizes 1, 2, 3, 7, 31 and
4096 bytes and at random boundaries, and asserting the tree matches the
whole-buffer parse — including splits placed inside a tag name, inside
an attribute value, inside a UTF-8 multibyte sequence, inside an entity
reference and inside a CDATA marker. One of the fuzz targets does the
same with the chunk size chosen adversarially by the fuzzer rather than
enumerated.

So you may feed whatever your transport hands you. There is no buffering
you need to do first, and no minimum chunk size for correctness.
(Throughput is a different question: below about 4 KiB per call the
per-call overhead starts to show.)

## Using it from C

A consumer declares `Imports: zuxml` and `LinkingTo: zuxml` in its
`DESCRIPTION`, and an import directive such as
`importFrom(zuxml, zuxml_info)` in its `NAMESPACE`. The directive is
required: the function table is registered when zuxml’s namespace is
loaded, and `Imports:` alone only guarantees that zuxml is installed.
Without it, every lookup fails with “function ‘zuxml_api_v2’ not
provided by package ‘zuxml’”.

In exactly one source file, the consumer defines `ZUXML_DEFINE_API_GET`
before including the header, which emits `zuxml_api_get()`:

``` c
#include <R.h>
#include <R_ext/Rdynload.h>
#define ZUXML_DEFINE_API_GET
#include <zuxml.h>

SEXP mypkg_parse(SEXP x) {
  const zuxml_api *api = zuxml_api_get();
  /* ... */
}
```

Call `zuxml_api_get()` where the table is needed, not in
`R_init_mypkg()`. It looks the table up once and caches it. If zuxml’s
namespace is not loaded, or the installed zuxml no longer provides this
table version, the lookup raises an ordinary R error, and raising one
while your package is still loading would make the package fail to load.
Members added after the table was first published are guarded with
`ZUXML_API_HAS(api, member)`.

The header exposes no Expat type, and a table consumer never links
against Expat. That separation is checked on every CI run by a fixture
package, `tools/zuxmltable`, built and installed exactly the way a real
consumer would be. Its compiled object is asserted to contain no Expat
symbol and no zuxml-internal one, and it calls every member of the
table.

To parse incrementally, create a tree builder, feed it, and finish:

``` c
zux_tree_builder *b;
zux_document *doc;
zux_error err;
zux_options opt;

api->options_init(&opt);
opt.max_depth = 256;

if (api->tree_begin(&b, &opt) != ZUX_OK) { /* handle */ }

while ((n = read_some(buf, sizeof buf)) > 0) {
  if (api->tree_feed(b, buf, n) != ZUX_OK) break;   /* stop on first error */
}

if (api->tree_end(b, &doc, &err) != ZUX_OK) { /* handle */ }
```

Two things to note. Buffers passed to `tree_feed()` are caller-owned and
are never retained, so you may reuse a single stack buffer for the whole
stream. And an error is sticky: once a feed fails, the parse is over,
and `tree_end()` reports the same failure rather than a second,
confusing one.

If you want events rather than a tree — to count elements, or to pull
out one field without building anything — `parser_feed()` is the lower
seam and calls your handlers directly.

## Errors and limits behave the same as from R

The limits in `zux_options` are enforced during feeding, not at the end,
so a hostile document fails as soon as it crosses a bound rather than
after you have paid for it. `zux_error` carries the same status,
message, line and column that the R conditions are built from, so a
downstream package can map them onto its own conditions and lose
nothing:

``` r

# What the R side makes of the same failures
tryCatch(xml_parse(paste0(strrep("<a>", 300), strrep("</a>", 300))),
         zuxml_error = function(e) class(e)[1:2])
```

Everything in
[`vignette("security")`](https://pedrobtz.github.io/zuxml/articles/security.md)
applies unchanged to the streaming path. It is the same parser and the
same guards; only the way bytes arrive differs. In particular the
`DOCTYPE` policy is enforced on the first chunk that contains the
declaration, so a hostile document is refused early rather than after
the whole body has been read.

## A note on memory

Streaming bounds the memory used for the *input*, not for the result.
The tree is still built in full, so a 100 MiB document still produces a
100 MiB-ish tree. What you avoid is holding the raw bytes and the tree
at the same time, which for a large response is the difference that
matters.

`max_memory` bounds the arena, so a document that would build an
unreasonable tree fails with a classed error rather than exhausting the
session — and it fails partway through feeding, not at the end.

If you want neither the bytes nor the tree, use `parser_feed()` and keep
only what you need.
