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

# The bug these guard only shows outside a UTF-8 locale, where paste() has to
# fall back to the native encoding. Both strings are built from explicit bytes
# so the fixture does not depend on how this file itself is decoded.
latin1_str <- function(bytes) {
  s <- rawToChar(as.raw(bytes))
  Encoding(s) <- "latin1"
  s
}

in_c_locale <- function(code) {
  old <- Sys.getlocale("LC_CTYPE")
  if (identical(Sys.setlocale("LC_CTYPE", "C"), "")) skip("cannot set the C locale")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  force(code)
}

test_that("a latin1-marked string parses to the same bytes in any locale", {
  # charToRaw() hands back bytes in the string's own encoding, and paste()
  # falls back to the native one when it has to pick, so declaring the result
  # UTF-8 corrupted non-ASCII content everywhere except a UTF-8 locale.
  # <a>caf.</a> with a latin1 e-acute.
  latin1 <- latin1_str(c(0x3c, 0x61, 0x3e, 0x63, 0x61, 0x66, 0xe9,
                         0x3c, 0x2f, 0x61, 0x3e))
  expect_identical(Encoding(latin1), "latin1")

  utf8 <- as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))
  expect_identical(charToRaw(xml_text(xml_root(xml_parse(latin1)))), utf8)
  in_c_locale(
    expect_identical(charToRaw(xml_text(xml_root(xml_parse(latin1)))), utf8))
})

test_that("a latin1-marked string cannot smuggle markup into content", {
  # In a C locale paste() rendered the unrepresentable byte as the literal
  # escape "<e9>", which the parser then read as an element: text silently
  # became structure. The comment keeps the document well-formed either way,
  # which is what made the old failure silent rather than an error.
  # <a><!--caf.--><b>x</b></a> with a latin1 e-acute.
  latin1 <- latin1_str(c(0x3c, 0x61, 0x3e, 0x3c, 0x21, 0x2d, 0x2d, 0x63,
                         0x61, 0x66, 0xe9, 0x2d, 0x2d, 0x3e, 0x3c, 0x62,
                         0x3e, 0x78, 0x3c, 0x2f, 0x62, 0x3e, 0x3c, 0x2f,
                         0x61, 0x3e))
  check <- function() {
    kids <- xml_children(xml_root(xml_parse(latin1)))
    expect_identical(xml_type(kids), c("comment", "element"))
    expect_identical(charToRaw(xml_text(kids[1])),
                     as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  }
  check()
  in_c_locale(check())
})

test_that("common aliases of Expat's encodings are accepted", {
  # Expat knows only its own spelling of each name, and the aliases were
  # passed through untranslated, so encoding = "latin1" failed as unknown.
  latin1 <- as.raw(c(charToRaw("<a>"), 0xe9, charToRaw("</a>")))
  for (enc in c("latin1", "LATIN1", "ISO-8859-1", "iso-8859-1")) {
    doc <- xml_parse(latin1, encoding = enc)
    expect_identical(xml_text(xml_root(doc)), "é", info = enc)
  }
  for (enc in c("UTF8", "utf-8", "ASCII", "us-ascii")) {
    expect_s3_class(xml_parse(charToRaw("<a>x</a>"), encoding = enc),
                    "zuxml_document")
  }
})
