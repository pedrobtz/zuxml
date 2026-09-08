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

A length-1 vector.

## Examples

``` r
xml_encoding(xml_parse('<?xml version="1.0" encoding="UTF-8"?><a/>'))
#> [1] "UTF-8"
```
