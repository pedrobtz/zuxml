test_that("UTF-8 round-trips including astral characters", {
  doc <- xml_parse("<a>naïve café 中文 \U0001F600</a>")
  expect_identical(xml_text(xml_root(doc)), "naïve café 中文 \U0001F600")
  expect_identical(Encoding(xml_text(xml_root(doc))), "UTF-8")
})

test_that("windows-1252 is transcoded through iconv", {
  # Expat handles only UTF-8/UTF-16/ISO-8859-1/US-ASCII, and windows-1252 is
  # common in real RSS. Design section 10.
  raw1252 <- as.raw(c(0x3c, 0x61, 0x3e,             # <a>
                      0x93, 0x71, 0x94,             # curly-quoted q
                      0x97,                         # em dash
                      0x3c, 0x2f, 0x61, 0x3e))      # </a>
  doc <- xml_parse(raw1252, encoding = "windows-1252")
  txt <- xml_text(xml_root(doc))
  expect_identical(Encoding(txt), "UTF-8")
  expect_true(grepl("“", txt))
  expect_true(grepl("—", txt))
})

test_that("ISO-8859-1 is handled natively by the parser", {
  raw <- c(charToRaw('<?xml version="1.0" encoding="ISO-8859-1"?><a>'),
           as.raw(0xe9), charToRaw("</a>"))
  doc <- xml_parse(raw)
  expect_identical(xml_text(xml_root(doc)), "é")
})

test_that("UTF-16 input is detected from its byte-order mark", {
  utf16 <- iconv(list(charToRaw("<a>hi</a>")), from = "UTF-8",
                 to = "UTF-16", toRaw = TRUE)[[1]]
  doc <- xml_parse(utf16)
  expect_identical(xml_text(xml_root(doc)), "hi")
})

test_that("an unusable encoding name is a clean encoding error", {
  expect_error(xml_parse(charToRaw("<a/>"), encoding = "definitely-not-real"),
               class = "zuxml_encoding_error")
})

test_that("malformed UTF-8 is rejected, never silently replaced", {
  bad <- c(charToRaw("<a>"), as.raw(0xff), as.raw(0xfe), charToRaw("</a>"))
  expect_error(xml_parse(bad), class = "zuxml_error")
})

test_that("a truncated multibyte sequence is rejected", {
  bad <- c(charToRaw("<a>"), as.raw(0xe4), as.raw(0xb8), charToRaw("</a>"))
  expect_error(xml_parse(bad), class = "zuxml_error")
})
