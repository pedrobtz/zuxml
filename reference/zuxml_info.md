# Report the zuxml build configuration

Reports the vendored 'Expat' version and the parser policy compiled into
this build. Intended for diagnostics and for security audits: in a
correctly built `zuxml`, `dtd` and `general_entities` are both `FALSE`
and `entropy` names a real operating-system entropy source.

## Usage

``` r
zuxml_info()
```

## Value

An object of class `zuxml_info`: a list with elements `zuxml_version`,
`expat_version`, `namespaces`, `dtd`, `general_entities`,
`context_bytes`, `xml_char_bytes`, `byteorder`, `entropy` and
`parser_ok`.

## Examples

``` r
zuxml_info()
#> zuxml 0.0.0.9000
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
