# xml_read() beyond what the shared byte source guarantees (see
# test-source.R): that the parser's position, limits, options and encoding
# handling survive the trip through a connection.

# rawConnection() is born open, so xml_read() leaves it open; close it here
# rather than let the GC warn about an unused connection.
read_raw <- function(bytes, ...) {
  con <- rawConnection(bytes)
  on.exit(close(con), add = TRUE)
  xml_read(con, ...)
}

big_doc <- function(n = 20000L) {
  # Well over three feed chunks, so the connection loop reads more than once.
  paste0("<r>", strrep("<i a='1'>text</i>", n), "</r>")
}

test_that("a stream error carries the same position as the buffered parse", {
  # The error sits past the first feed chunk, so the offset is only right if
  # the parser's position survives across connection reads.
  bad <- paste0(big_doc(5000L), "<unclosed>")
  bad <- sub("</r>", "", bad, fixed = TRUE)
  expect_gt(nchar(bad), 65536)
  buffered <- tryCatch(xml_parse(bad), zuxml_error = identity)
  streamed <- tryCatch(read_raw(charToRaw(bad)), zuxml_error = identity)
  expect_s3_class(streamed, "zuxml_parse_error")
  expect_identical(class(streamed), class(buffered))
  expect_identical(streamed$byte_offset, buffered$byte_offset)
  expect_identical(streamed$line, buffered$line)
  expect_identical(streamed$column, buffered$column)
})

test_that("limits apply to a stream", {
  expect_error(read_raw(charToRaw(big_doc(1000L)), max_nodes = 10),
               class = "zuxml_limit_error")
})

test_that("options reach the stream parser", {
  doc <- read_raw(charToRaw("<r><!-- c --><a/></r>"), comments = FALSE)
  expect_identical(xml_type(xml_children(xml_root(doc))), "element")
  expect_error(read_raw(charToRaw("<r/>"), no_such = 1), "unused argument")
})

test_that("an encoding iconv() must handle is read whole, then transcoded", {
  raw1252 <- as.raw(c(0x3c, 0x61, 0x3e, 0x93, 0x71, 0x94, 0x97,
                      0x3c, 0x2f, 0x61, 0x3e))
  doc <- read_raw(raw1252, encoding = "windows-1252")
  txt <- xml_text(xml_root(doc))
  expect_true(grepl("“", txt))
  expect_true(grepl("—", txt))
  expect_error(read_raw(raw1252, encoding = "definitely-not-real"),
               class = "zuxml_encoding_error")
})

test_that("a native encoding override streams without buffering", {
  raw <- c(charToRaw('<?xml version="1.0" encoding="UTF-8"?><a>'),
           as.raw(0xe9), charToRaw("</a>"))
  doc <- read_raw(raw, encoding = "ISO-8859-1")
  expect_identical(xml_text(xml_root(doc)), "é")
})

test_that("an empty stream is a syntax error, not a crash", {
  expect_error(read_raw(raw()), class = "zuxml_parse_error")
})

