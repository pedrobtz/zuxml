books_doc <- function() xml_parse(
  "<r>
     <book id='a'><title>A</title><price>1</price></book>
     <book id='b'><price>2</price></book>
     <book id='c'><section><title>C</title></section><title>late</title></book>
   </r>")

test_that("xml_find_first() keeps one result per input, in order", {
  books <- xml_elements(xml_root(books_doc()), "book")
  titles <- xml_find_first(books, "title")
  expect_length(titles, 3L)
  # The trap it fixes: the flat search loses the second book's slot.
  expect_identical(xml_text(xml_find(books, "title")), c("A", "C", "late"))
  expect_identical(xml_text(titles), c("A", NA, "C"))
  # First in document order is the nested one, as a descendant search.
  expect_identical(xml_text(xml_find_first(books[3], "title")), "C")
})

test_that("xml_find_first() filters by name and namespace like xml_find()", {
  doc <- xml_parse("<r xmlns:a='urn:a'><x/><a:x/></r>")
  root <- xml_root(doc)
  expect_identical(xml_ns(xml_find_first(root, "x", ns = "urn:a")), "urn:a")
  expect_identical(xml_name(xml_find_first(root, "x", ns = NA)), "x")
  expect_identical(xml_name(xml_find_first(root)), "x")
  expect_identical(xml_name(xml_find_first(doc, "x")), "x")
  expect_identical(xml_type(xml_find_first(root, "nothing")), NA_character_)
})

test_that("every accessor gives NA for a missing node", {
  books <- xml_elements(xml_root(books_doc()), "book")
  t <- xml_find_first(books, "title")
  expect_identical(xml_name(t),   c("title", NA, "title"))
  expect_identical(xml_local(t),  c("title", NA, "title"))
  expect_identical(xml_ns(t),     c(NA_character_, NA, NA))
  expect_identical(xml_prefix(t), c(NA_character_, NA, NA))
  expect_identical(xml_type(t),   c("element", NA, "element"))
  expect_identical(xml_text(t, recursive = FALSE), c("A", NA, "C"))
  expect_identical(xml_text(t, trim = TRUE), c("A", NA, "C"))
  expect_identical(xml_attr(t, "id"), rep(NA_character_, 3))
  expect_identical(xml_serialize(t), c("<title>A</title>", NA, "<title>C</title>"))
})

test_that("a missing node has no attributes, and default applies to it", {
  books <- xml_elements(xml_root(books_doc()), "book")
  t <- xml_find_first(books, "title")
  a <- xml_attrs(t)
  expect_length(a, 3L)
  expect_identical(a[[2]], structure(character(), names = character()))
  expect_identical(xml_attr(t, "id", default = "none"), rep("none", 3))
})

test_that("traversals skip a missing node", {
  books <- xml_elements(xml_root(books_doc()), "book")
  t <- xml_find_first(books, "title")
  expect_length(xml_parent(t), 2L)
  expect_identical(xml_attr(xml_parent(t), "id"), c("a", NA))
  expect_length(xml_children(t), 2L)
  expect_length(xml_elements(t), 0L)
  expect_length(xml_find(t, "title"), 0L)
  # Chained: a missing input stays missing, and keeps its slot.
  p <- xml_find_first(xml_find_first(books, "section"), "title")
  expect_identical(xml_text(p), c(NA, NA, "C"))
})

test_that("missing nodes survive subsetting and combining, and print", {
  books <- xml_elements(xml_root(books_doc()), "book")
  t <- xml_find_first(books, "title")
  expect_identical(xml_text(t[2]), NA_character_)
  expect_identical(xml_text(rev(t)), c("C", NA, "A"))
  expect_identical(xml_text(c(t, t[1])), c("A", NA, "C", "A"))
  expect_identical(format(t), c("<title>", "<missing>", "<title>"))
  expect_output(print(t[2]), "missing")
  expect_output(print(t), "<missing>")
})

test_that("what has no answer for a missing node refuses it", {
  books <- xml_elements(xml_root(books_doc()), "book")
  t <- xml_find_first(books, "title")
  expect_error(xml_write(t[2], tempfile()), class = "zuxml_invalid_argument")
  expect_error(xml_table(t[2]), class = "zuxml_invalid_argument")
  expect_error(xml_list(t[2]), class = "zuxml_invalid_argument")
})
