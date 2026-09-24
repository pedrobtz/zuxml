# Tests for src/zu_source.h and R/zu_source.R, the byte source shared with
# sibling packages. They exercise it through this package's reader, so the
# one line below is all a copy has to change. Everything here is about how
# input reaches the parser -- paths, URLs, connections, chunking -- not
# about the format, which tests/testthat/test-read.R covers.

read_input <- xml_read
prefix <- "zuxml"
msg <- function(x) paste0("^", prefix, ": ", x)

big_doc <- function(n = 20000L) {
  # Well over three feed chunks, so the connection loop reads more than once.
  paste0("<r>", strrep("<i a='1'>text</i>", n), "</r>")
}

test_that("read_input() parses a path, a file:// URL and a connection alike", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines(big_doc(), f)
  expect_gt(file.info(f)$size, 3 * 65536)

  from_path <- read_input(f)
  from_url <- read_input(paste0("file://", f))
  from_con <- read_input(file(f))
  from_raw <- xml_parse(readBin(f, "raw", file.info(f)$size))

  for (doc in list(from_path, from_url, from_con)) {
    expect_identical(xml_serialize(doc), xml_serialize(from_raw))
    expect_length(xml_elements(xml_root(doc), "i"), 20000L)
  }
})

test_that("a URL string is recognised by scheme, case-insensitively", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines("<r><a>x</a></r>", f)
  expect_identical(xml_text(xml_find(read_input(paste0("FILE://", f)), "a")), "x")
  # Not a scheme: an ordinary relative path that merely contains "://".
  d <- tempfile()
  dir.create(file.path(d, "http:"), recursive = TRUE)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  p <- file.path(d, "http:", "x.xml")
  writeLines("<r><a>y</a></r>", p)
  expect_identical(xml_text(xml_find(read_input(p), "a")), "y")
})

test_that("an unopened connection is opened in binary mode and closed", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines("<r><a>x</a></r>", f)
  before <- nrow(showConnections(all = FALSE))
  con <- file(f)
  expect_identical(xml_text(xml_find(read_input(con), "a")), "x")
  # close() destroys the connection object, so it no longer exists.
  expect_error(isOpen(con), "invalid connection")
  expect_identical(nrow(showConnections(all = FALSE)), before)
})

test_that("an open binary connection is read from its position and left open", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeBin(charToRaw("junk<r><a>x</a></r>"), f)
  con <- file(f, "rb")
  on.exit(close(con), add = TRUE)
  expect_identical(readBin(con, "raw", 4L), charToRaw("junk"))
  expect_identical(xml_text(xml_find(read_input(con), "a")), "x")
  expect_true(isOpen(con))
  expect_length(readBin(con, "raw", 1L), 0L)
})

test_that("a compressed file streams through gzfile()", {
  f <- tempfile(fileext = ".xml.gz")
  on.exit(unlink(f), add = TRUE)
  con <- gzfile(f, "wb")
  writeLines(big_doc(), con)
  close(con)
  doc <- read_input(gzfile(f))
  expect_length(xml_elements(xml_root(doc), "i"), 20000L)
})

test_that("an open text-mode connection is rejected", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines("<r/>", f)
  con <- file(f, "r")
  on.exit(close(con), add = TRUE)
  expect_error(read_input(con), msg("an open connection must be in binary mode"))
})

test_that("a non-blocking connection is rejected", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines("<r/>", f)
  con <- file(f, "rb", blocking = FALSE)
  on.exit(close(con), add = TRUE)
  expect_error(read_input(con), msg("the connection must be blocking"))
})

test_that("a closed connection handle is an error, not a crash", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines("<r/>", f)
  con <- file(f, "rb")
  close(con)
  expect_error(read_input(con), "invalid connection")
})

test_that("a bad input is a classed, prefixed error", {
  expect_error(read_input(1L), msg("`path` must be"))
  expect_error(read_input(c("a.xml", "b.xml")), msg("`path` must be"))
  expect_error(read_input(NA_character_), msg("`path` must be"))
})
