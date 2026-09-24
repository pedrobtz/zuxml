# Extract tables and lists

`xml_table()` turns `table` elements into data frames, and `xml_list()`
turns `ul` and `ol` elements into R lists. Both read well-formed XML,
such as XHTML or a table embedded in another XML format. They do not
apply HTML parsing rules: a `table` without `tbody` has exactly the rows
it contains.

## Usage

``` r
xml_table(x, header = NA, trim = TRUE, ns = NULL, max_cells = 1e+07)

xml_list(x, trim = TRUE, ns = NULL)
```

## Arguments

- x:

  A node or nodeset of `table` elements for `xml_table()`, or of `ul`
  and `ol` elements for `xml_list()`. A document stands for its root.

- header:

  Use the first row as column names. `NA`, the default, does so when
  every cell of the first row is a `th`.

- trim:

  Trim leading and trailing whitespace from each value.

- ns:

  Namespace URI of the table or list elements, `NA` for none, `NULL` for
  any.

- max_cells:

  The most cells one table may expand to. A positive whole number, or
  `Inf`.

## Value

A list with one element per node in `x`: a data frame for `xml_table()`,
a list of items for `xml_list()`.

## Details

**Tables.** The rows are the `tr` elements that are children of the
`table`, or of its `thead`, `tbody` or `tfoot`, in document order. A
table nested inside a cell is not descended into; extract it separately.
The cells are the `td` and `th` elements of a row, and a cell's value is
its text, as
[`xml_text()`](https://pedrobtz.github.io/zuxml/reference/xml_properties.md)
gives it. Every column is character: convert types yourself, for example
with `type.convert(df, as.is = TRUE)`.

`colspan` and `rowspan` are expanded by repeating the cell's value. A
span that is not a positive whole number counts as 1, and spans are
capped at HTML's own limits, 1000 columns and 65534 rows. A row span
never adds rows past the end of the table. Short rows are padded with
`NA`.

Expansion can make a small document produce a very large table, so the
expanded size of each table is bounded by `max_cells`, and exceeding it
is a `zuxml_limit_error`.

**Lists.** Each `li` child of a `ul` or `ol` becomes one item. An item
is its text as a string or, when the `li` has `ul` or `ol` children, a
list with two elements: `text`, the item's own text without the nested
lists', and `items`, the items of its nested lists, extracted the same
way. Only direct `ul` and `ol` children of an `li` count as nested
lists. Comments and processing instructions inside an item are ignored.

## See also

[`xml_find()`](https://pedrobtz.github.io/zuxml/reference/xml_navigate.md)
to locate the tables or lists in a document, and
[zuxml-conditions](https://pedrobtz.github.io/zuxml/reference/zuxml-conditions.md)
for the errors these raise.

## Examples

``` r
doc <- xml_parse("<table>
  <tr><th>fruit</th><th>price</th></tr>
  <tr><td>apple</td><td>1.20</td></tr>
  <tr><td>pear</td><td>0.90</td></tr>
</table>")
xml_table(xml_root(doc))[[1]]
#>   fruit price
#> 1 apple  1.20
#> 2  pear  0.90

doc <- xml_parse("<ul>
  <li>fruit<ul><li>apple</li><li>pear</li></ul></li>
  <li>bread</li>
</ul>")
str(xml_list(xml_root(doc))[[1]])
#> List of 2
#>  $ :List of 2
#>   ..$ text : chr "fruit"
#>   ..$ items:List of 2
#>   .. ..$ : chr "apple"
#>   .. ..$ : chr "pear"
#>  $ : chr "bread"
```
