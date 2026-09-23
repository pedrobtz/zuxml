test_that("a character x of any length but one is refused", {
  # It used to be pasted with "": the lines of readLines() ran together,
  # changing text nodes and reporting every error at line 1.
  lines <- c("<r>", "  <a>1</a>", "</r>")
  e <- tryCatch(xml_parse(lines), error = function(e) e)
  expect_s3_class(e, "zuxml_invalid_argument")
  expect_identical(e$arg, "x")
  expect_error(xml_parse(character()), class = "zuxml_invalid_argument")

  # Joined by the caller, the lines parse, and positions are real.
  doc <- xml_parse(paste(lines, collapse = "\n"))
  expect_identical(xml_text(xml_find(doc, "a")), "1")
  e <- tryCatch(xml_parse(paste(c("<r>", "<a>", "</r>"), collapse = "\n")),
                error = function(e) e)
  expect_identical(e$line, 3)
})

test_that("x must be a string or raw, and not NA", {
  expect_error(xml_parse(NA_character_), class = "zuxml_invalid_argument")
  expect_error(xml_parse(1L), class = "zuxml_invalid_argument")
  expect_error(xml_parse(list("<a/>")), class = "zuxml_invalid_argument")
  expect_error(xml_parse(NULL), class = "zuxml_invalid_argument")
})

test_that("encoding other than UTF-8 is refused for character x", {
  # A character string is already decoded. Transcoding its UTF-8 bytes as
  # latin1 used to turn "é" into "Ã©" without a word.
  x <- "<a>é</a>"
  e <- tryCatch(xml_parse(x, encoding = "latin1"), error = function(e) e)
  expect_s3_class(e, "zuxml_invalid_argument")
  expect_identical(e$arg, "encoding")
  expect_error(xml_parse(x, encoding = "windows-1252"),
               class = "zuxml_invalid_argument")

  for (enc in list(NULL, "UTF-8", "utf-8", "UTF8")) {
    doc <- xml_parse(x, encoding = enc)
    expect_identical(xml_text(xml_root(doc)), "é")
  }

  # Raw input still takes any encoding.
  raw <- iconv(x, from = "UTF-8", to = "latin1", toRaw = TRUE)[[1L]]
  expect_identical(xml_text(xml_root(xml_parse(raw, encoding = "latin1"))),
                   "é")
})

test_that("encoding must be a single string or NULL", {
  for (enc in list(NA_character_, c("UTF-8", "latin1"), 8L, character())) {
    expect_error(xml_parse(charToRaw("<a/>"), encoding = enc),
                 class = "zuxml_invalid_argument")
  }
})

test_that("parse flags must be TRUE or FALSE", {
  # opt_flag() in C read NA as FALSE.
  for (arg in c("comments", "pis", "allow_doctype")) {
    for (v in list(NA, "yes", c(TRUE, FALSE), NULL)) {
      e <- tryCatch(do.call(xml_parse, c(list("<a/>"),
                                         stats::setNames(list(v), arg))),
                    error = function(e) e)
      expect_s3_class(e, "zuxml_invalid_argument")
      expect_identical(e$arg, arg)
    }
  }
})

test_that("every argument error is a zuxml_invalid_argument", {
  doc <- xml_parse("<r><a/><b/></r>")
  root <- xml_root(doc)
  expect_error(xml_find(root, c("a", "b")), class = "zuxml_invalid_argument")
  expect_error(xml_name(1:3), class = "zuxml_invalid_argument")
  expect_error(xml_read(tempfile()), class = "zuxml_invalid_argument")
  expect_error(xml_serialize(root, declaration = NA),
               class = "zuxml_invalid_argument")

  e <- tryCatch(xml_parse(1L), error = function(e) e)
  expect_s3_class(e, "zuxml_error")
})
