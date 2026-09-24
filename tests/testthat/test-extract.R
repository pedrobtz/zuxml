tbl <- function(xml, ...) xml_table(xml_parse(xml), ...)[[1]]
lst <- function(xml, ...) xml_list(xml_parse(xml), ...)[[1]]

test_that("a table with a th header row becomes a named data frame", {
  d <- tbl("<table>
    <tr><th>fruit</th><th>price</th></tr>
    <tr><td>apple</td><td>1.20</td></tr>
    <tr><td>pear</td><td>0.90</td></tr>
  </table>")
  expect_s3_class(d, "data.frame")
  expect_identical(names(d), c("fruit", "price"))
  expect_identical(d$fruit, c("apple", "pear"))
  # Values stay character; converting is the caller's choice.
  expect_identical(d$price, c("1.20", "0.90"))
})

test_that("rows come from table, thead, tbody and tfoot in document order", {
  d <- tbl("<table>
    <thead><tr><th>h</th></tr></thead>
    <tbody><tr><td>1</td></tr><tr><td>2</td></tr></tbody>
    <tfoot><tr><td>total</td></tr></tfoot>
  </table>")
  expect_identical(d$h, c("1", "2", "total"))
})

test_that("header detection follows the first row, and can be forced", {
  td_only <- "<table><tr><td>a</td><td>b</td></tr><tr><td>1</td><td>2</td></tr></table>"
  expect_identical(names(tbl(td_only)), c("X1", "X2"))
  expect_identical(nrow(tbl(td_only)), 2L)
  expect_identical(names(tbl(td_only, header = TRUE)), c("a", "b"))

  th_row <- "<table><tr><th>a</th><th>b</th></tr><tr><td>1</td><td>2</td></tr></table>"
  expect_identical(nrow(tbl(th_row, header = FALSE)), 2L)
  expect_identical(tbl(th_row, header = FALSE)$X1, c("a", "1"))

  # A mixed first row is not a header.
  mixed <- "<table><tr><th>a</th><td>b</td></tr></table>"
  expect_identical(names(tbl(mixed)), c("X1", "X2"))
})

test_that("blank and duplicate header names are repaired", {
  d <- tbl("<table><tr><th>a</th><th></th><th>a</th></tr><tr><td>1</td><td>2</td><td>3</td></tr></table>")
  expect_identical(names(d), c("a", "X2", "a.1"))
})

test_that("colspan and rowspan repeat the cell's value", {
  d <- tbl("<table>
    <tr><th>a</th><th>b</th><th>c</th></tr>
    <tr><td rowspan='2'>1</td><td colspan='2'>wide</td></tr>
    <tr><td>x</td><td>y</td></tr>
    <tr><td colspan='3'>all</td></tr>
  </table>")
  expect_identical(d$a, c("1", "1", "all"))
  expect_identical(d$b, c("wide", "x", "all"))
  expect_identical(d$c, c("wide", "y", "all"))
})

test_that("a row span in a later column is carried past a short row", {
  d <- tbl("<table>
    <tr><td>1</td><td rowspan='3'>tall</td></tr>
    <tr><td>2</td></tr>
    <tr><td>3</td></tr>
  </table>")
  expect_identical(d$X2, c("tall", "tall", "tall"))
  expect_identical(d$X1, c("1", "2", "3"))
})

test_that("a row span stops at the end of the table", {
  d <- tbl("<table><tr><td rowspan='50'>x</td></tr><tr/></table>")
  expect_identical(nrow(d), 2L)
})

test_that("ragged rows are padded with NA", {
  d <- tbl("<table><tr><td>1</td><td>2</td><td>3</td></tr><tr><td>4</td></tr></table>")
  expect_identical(d$X3, c("3", NA))
})

test_that("unusable spans count as 1", {
  for (v in c("0", "-2", "1.5", "abc", "")) {
    d <- tbl(sprintf("<table><tr><td colspan='%s'>x</td><td>y</td></tr></table>", v))
    expect_identical(ncol(d), 2L, info = v)
  }
})

test_that("a span bomb is refused as a limit error", {
  # One row of 100 cells, each colspan 1000 and rowspan 65534, then 2000
  # empty rows: 7 KB of XML that would expand to 200 million cells.
  x <- paste0("<table><tr>",
              strrep("<td colspan='1000' rowspan='65534'>x</td>", 100),
              "</tr>", strrep("<tr/>", 2000), "</table>")
  # No timing assertion: valgrind and gctorture slow this by an order of
  # magnitude. Work follows the expanded width, which max_cells bounds; the
  # span values themselves never drive a loop (design section 7).
  e <- tryCatch(tbl(x), error = function(e) e)
  expect_s3_class(e, "zuxml_limit_error")
  expect_identical(e$limit, "max_cells")
  expect_identical(e$limit_value, 1e7)

  # A smaller bound refuses a legitimate table, and Inf lifts it.
  x <- "<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>"
  expect_error(tbl(x, max_cells = 3), class = "zuxml_limit_error")
  expect_identical(nrow(tbl(x, max_cells = 4)), 2L)
  expect_identical(nrow(tbl(x, max_cells = Inf)), 2L)
})

test_that("cell text includes mixed content and can be left untrimmed", {
  d <- tbl("<table><tr><td> a <b>bold</b> c </td></tr></table>")
  expect_identical(d$X1, "a bold c")
  d <- tbl("<table><tr><td> a <b>bold</b> c </td></tr></table>", trim = FALSE)
  expect_identical(d$X1, " a bold c ")
})

test_that("a table nested in a cell is not descended into", {
  x <- xml_parse("<table>
    <tr><td>outer<table><tr><td>inner</td></tr></table></td><td>2</td></tr>
  </table>")
  outer <- xml_table(xml_root(x))[[1]]
  expect_identical(dim(outer), c(1L, 2L))
  inner <- xml_table(xml_find(xml_root(x), "table"))[[1]]
  expect_identical(inner$X1, "inner")
})

test_that("namespaced XHTML tables work, with or without ns", {
  x <- xml_parse("<h:table xmlns:h='http://www.w3.org/1999/xhtml'>
    <h:tr><h:th>k</h:th></h:tr><h:tr><h:td>v</h:td></h:tr></h:table>")
  expect_identical(xml_table(x)[[1]]$k, "v")
  expect_identical(xml_table(x, ns = "http://www.w3.org/1999/xhtml")[[1]]$k, "v")
  expect_error(xml_table(x, ns = NA), class = "zuxml_invalid_argument")
})

test_that("xml_table() takes a nodeset and returns one data frame per table", {
  doc <- xml_parse("<r><table><tr><td>1</td></tr></table><table><tr><td>2</td></tr></table></r>")
  out <- xml_table(xml_find(doc, "table"))
  expect_length(out, 2L)
  expect_identical(out[[2]]$X1, "2")
  expect_identical(xml_table(xml_find(doc, "nothing")), list())
})

test_that("empty tables are empty data frames", {
  expect_identical(dim(tbl("<table/>")), c(0L, 0L))
  d <- tbl("<table><tr><th>h</th></tr></table>")
  expect_identical(dim(d), c(0L, 1L))
  expect_identical(names(d), "h")
})

test_that("xml_table() rejects what is not a table", {
  expect_error(tbl("<ul/>"), class = "zuxml_invalid_argument")
  expect_error(xml_table("<table/>"), class = "zuxml_invalid_argument")
  x <- "<table/>"
  expect_error(tbl(x, header = "yes"), class = "zuxml_invalid_argument")
  expect_error(tbl(x, trim = NA), class = "zuxml_invalid_argument")
  for (v in list(0, -1, 0.5, NA, "10")) {
    expect_error(tbl(x, max_cells = v), class = "zuxml_invalid_argument")
  }
})

test_that("a flat list is a list of strings", {
  out <- lst("<ul><li>a</li><li> b </li><li/></ul>")
  expect_identical(out, list("a", "b", ""))
  expect_identical(lst("<ol><li> b </li></ol>", trim = FALSE), list(" b "))
})

test_that("nested lists nest, and an item's text excludes its sublists", {
  out <- lst("<ol>
    <li>fruit <b>ripe</b>
      <ul><li>apple</li><li>pear<ul><li>conference</li></ul></li></ul>
    </li>
    <li>bread</li>
  </ol>")
  expect_length(out, 2L)
  expect_identical(out[[1]]$text, "fruit ripe")
  expect_identical(out[[1]]$items[[1]], "apple")
  expect_identical(out[[1]]$items[[2]]$text, "pear")
  expect_identical(out[[1]]$items[[2]]$items, list("conference"))
  expect_identical(out[[2]], "bread")
})

test_that("two sublists in one item are concatenated in order", {
  out <- lst("<ul><li>x<ul><li>1</li></ul><ol><li>2</li></ol></li></ul>")
  expect_identical(out[[1]]$items, list("1", "2"))
})

test_that("comments and processing instructions do not reach item text", {
  out <- lst("<ul><li>a<!-- note --><?pi data?>b</li></ul>")
  expect_identical(out, list("ab"))
})

test_that("only direct ul and ol children of an item are sublists", {
  out <- lst("<ul><li>x<div><ul><li>deep</li></ul></div></li></ul>")
  expect_identical(out, list("xdeep"))
})

test_that("xml_list() takes a nodeset and rejects what is not a list", {
  doc <- xml_parse("<r><ul><li>1</li></ul><ol><li>2</li></ol></r>")
  out <- xml_list(xml_elements(xml_root(doc)))
  expect_identical(out, list(list("1"), list("2")))
  expect_error(xml_list(xml_root(doc)), class = "zuxml_invalid_argument")
  expect_error(lst("<ul/>", trim = "no"), class = "zuxml_invalid_argument")
})

test_that("namespaced XHTML lists work", {
  x <- xml_parse("<h:ul xmlns:h='http://www.w3.org/1999/xhtml'><h:li>a<h:ol><h:li>b</h:li></h:ol></h:li></h:ul>")
  out <- xml_list(x)[[1]]
  expect_identical(out[[1]]$text, "a")
  expect_identical(out[[1]]$items, list("b"))
})
