# A whole play in XML

Small examples make a parser look easy. This one uses a real document:
Jon Bosak’s XML edition of *Hamlet*, part of the Shakespeare collection
that has been a standard XML test corpus since 1998. It is 280 KB and
about 20,000 nodes — small enough to fetch in a second, structured
enough that navigating it is a real question rather than a
demonstration.

``` r

library(zuxml)

url  <- "https://www.ibiblio.org/xml/examples/shakespeare/hamlet.xml"
path <- file.path(tempdir(), "hamlet.xml")
download.file(url, path, quiet = TRUE)

file.size(path)
#> [1] 279663
```

## It does not parse, and that is the point

``` r

xml_read(path)
#> Error : document type declaration is not allowed (at line 2, column 32)
```

The file opens with `<!DOCTYPE PLAY SYSTEM "play.dtd">`. `zuxml` rejects
document type declarations by default, because a DTD is the entry point
for entity-expansion attacks and for pulling in external files, and a
parser pointed at an untrusted body should not accept one on the
reader’s behalf.

*Hamlet* is not untrusted, so say so:

``` r

doc <- xml_read(path, allow_doctype = TRUE)
doc
#> <zuxml_document>
#> root:     PLAY
#> nodes:    19840   attributes: 0
#> memory:   1.5 Mb
#> encoding: not declared
```

Worth being precise about what that flag does and does not do. It allows
the declaration to be *present*. It does not enable entity expansion or
external entity resolution — neither is compiled into the build at all,
so `play.dtd` is never fetched and no `&entity;` in the document body
would be substituted. The flag moves one specific check, not the
security model.

## Walking the structure

The play is five acts of scenes of speeches of lines, which is what the
markup says:

``` r

root <- xml_root(doc)
table(xml_name(xml_elements(root)))
#>      ACT       FM PERSONAE PLAYSUBT SCNDESCR    TITLE
#>        5        1        1        1        1        1

c(acts     = length(xml_elements(root, "ACT")),
  scenes   = length(xml_find(doc, "SCENE")),
  speeches = length(xml_find(doc, "SPEECH")),
  lines    = length(xml_find(doc, "LINE")))
#>     acts   scenes speeches    lines
#>        5       20     1138     4014
```

[`xml_elements()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
looks only at direct element children, so it answers “what is
immediately inside the play”;
[`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
searches all descendants in document order, so it answers “how many
speeches are there anywhere”. The distinction is the whole navigation
API in one line.

## Every accessor is vectorized

There is no loop here.
[`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
returns a nodeset of 1,138 speakers and
[`xml_text()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
turns all of them into a character vector at once:

``` r

speakers <- xml_text(xml_find(doc, "SPEAKER"))

length(unique(speakers))
#> [1] 35

head(sort(table(speakers), decreasing = TRUE), 8)
#> speakers
#>         HAMLET        HORATIO  KING CLAUDIUS  LORD POLONIUS QUEEN GERTRUDE
#>            359            112            102             86             69
#>        LAERTES        OPHELIA    ROSENCRANTZ
#>             62             58             49
```

Hamlet has 359 of the 1,138 speeches — very nearly a third of the play,
which is the sort of thing the shape of the data tells you once it is in
R.

## Nodesets compose

A nodeset indexes like a vector, so per-act figures are the same two
calls applied to a subset:

``` r

acts <- xml_elements(root, "ACT")

data.frame(
  act      = xml_text(xml_elements(acts, "TITLE")),
  scenes   = vapply(seq_along(acts),
                    function(i) length(xml_elements(acts[i], "SCENE")), 1L),
  speeches = vapply(seq_along(acts),
                    function(i) length(xml_find(acts[i], "SPEECH")), 1L)
)
#>       act scenes speeches
#> 1   ACT I      5      251
#> 2  ACT II      2      201
#> 3 ACT III      4      250
#> 4  ACT IV      7      179
#> 5   ACT V      2      257
```

Note `xml_elements(acts, "TITLE")` — one call across all five acts,
giving five titles. That is the vectorization again: a nodeset in, a
nodeset out.

## Finding one thing

``` r

speeches <- xml_find(doc, "SPEECH")
first_line <- vapply(seq_along(speeches),
                     function(i) xml_text(xml_elements(speeches[i], "LINE"))[1],
                     "")

i <- grep("^To be, or not to be", first_line)
i
#> [1] 471

xml_text(xml_elements(speeches[i], "SPEAKER"))
#> [1] "HAMLET"

head(xml_text(xml_elements(speeches[i], "LINE")), 3)
#> [1] "To be, or not to be: that is the question:"
#> [2] "Whether 'tis nobler in the mind to suffer"
#> [3] "The slings and arrows of outrageous fortune,"
```

And the longest speech in the play, by line count:

``` r

n_lines <- vapply(seq_along(speeches),
                  function(i) length(xml_elements(speeches[i], "LINE")), 1L)

xml_text(xml_elements(speeches[which.max(n_lines)], "SPEAKER"))
#> [1] "HAMLET"

max(n_lines)
#> [1] 60
```

## What this cost

Parsing 280 KB into a 19,840-node tree took about 7 milliseconds and 1.5
MB. The tree is immutable and the accessors are vectorized over it, so
the analysis above is a handful of passes over a structure that was
built once.

For a document you did not write, keep the limits in mind rather than
the timings: `max_nodes`, `max_depth`, `max_attrs`, `max_text` and
`max_memory` all have defaults, each raises its own catchable condition,
and
[`zuxml_info()`](https://pedrobtz.github.io/zuxml/reference/zuxml_info.md)
reports what your build actually enforces.
