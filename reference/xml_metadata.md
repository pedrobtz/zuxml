# Document metadata

Document metadata

## Usage

``` r
xml_version(x)

xml_encoding(x)

xml_standalone(x)
```

## Arguments

- x:

  A `zuxml_document`.

## Value

A length-1 vector: a character string for `xml_version()` and
`xml_encoding()`, a logical for `xml_standalone()`. Each is `NA` when
the XML declaration did not state that property.

## Examples

``` r
xml_encoding(xml_parse('<?xml version="1.0" encoding="UTF-8"?><a/>'))
#> [1] "UTF-8"
```
