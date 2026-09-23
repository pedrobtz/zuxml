structure_of <- function(doc) zuxml:::zux_tree_info(xml_serialize(doc))$dump

test_that("parse -> serialize -> parse is structurally identical", {
  for (nm in names(corpus)) {
    d1 <- xml_parse(corpus[[nm]])
    s1 <- xml_serialize(d1)
    d2 <- xml_parse(s1)
    expect_identical(zuxml:::zux_tree_info(corpus[[nm]])$dump,
                     zuxml:::zux_tree_info(s1)$dump, info = nm)
    expect_identical(xml_serialize(d2), s1, info = nm)
  }
})

test_that("serialization is a fixed point after one round trip", {
  for (nm in names(corpus)) {
    s1 <- xml_serialize(xml_parse(corpus[[nm]]))
    s2 <- xml_serialize(xml_parse(s1))
    s3 <- xml_serialize(xml_parse(s2))
    expect_identical(s2, s1, info = nm)
    expect_identical(s3, s2, info = nm)
  }
})

test_that("text is escaped minimally but correctly", {
  expect_identical(xml_serialize(xml_parse("<a>x &amp; y</a>")), "<a>x &amp; y</a>")
  expect_identical(xml_serialize(xml_parse("<a>x &lt; y</a>")), "<a>x &lt; y</a>")
  # A bare '>' is legal text and is left alone ...
  expect_identical(xml_serialize(xml_parse("<a>x > y</a>")), "<a>x > y</a>")
  # ... but not where it would close a CDATA section.
  expect_identical(xml_serialize(xml_parse("<a>x ]]&gt; y</a>")),
                   "<a>x ]]&gt; y</a>")
})

test_that("attribute values escape quotes and whitespace", {
  # Tabs and newlines must become character references: attribute-value
  # normalization would otherwise turn them into spaces on re-parse.
  d <- xml_parse('<a t="x&#10;y&#9;z" q="he said &quot;hi&quot;"/>')
  s <- xml_serialize(d)
  expect_true(grepl("&#10;", s, fixed = TRUE))
  expect_true(grepl("&#9;", s, fixed = TRUE))
  expect_true(grepl("&quot;", s, fixed = TRUE))
  expect_identical(xml_attr(xml_root(xml_parse(s)), "t"), "x\ny\tz")
})

test_that("namespaces survive round-tripping semantically", {
  d <- xml_parse('<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i a="1"/><y:i a="2"/></r>')
  d2 <- xml_parse(xml_serialize(d))
  items <- xml_find(d2, "i", ns = "urn:s")
  expect_length(items, 2L)
  expect_identical(xml_attr(items, "a"), c("1", "2"))
})

test_that("a default-namespace reset survives", {
  d2 <- xml_parse(xml_serialize(xml_parse('<a xmlns="urn:d"><b xmlns=""/></a>')))
  expect_identical(xml_ns(xml_root(d2)), "urn:d")
  expect_true(is.na(xml_ns(xml_elements(xml_root(d2), "b"))))
})

test_that("CDATA becomes escaped text, as documented", {
  expect_identical(xml_serialize(xml_parse("<a><![CDATA[x<y]]></a>")),
                   "<a>x&lt;y</a>")
})

test_that("serializing a nodeset returns one string per node", {
  d <- xml_parse("<r><a>1</a><b>2</b></r>")
  s <- xml_serialize(xml_children(xml_root(d)))
  expect_identical(s, c("<a>1</a>", "<b>2</b>"))
})

test_that("as.character and xml_write agree with xml_serialize", {
  d <- xml_parse("<a>x</a>")
  expect_identical(as.character(d), xml_serialize(d))
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  xml_write(d, f)
  expect_true(grepl("<a>x</a>", paste(readLines(f, warn = FALSE), collapse = "")))
  expect_identical(xml_text(xml_root(xml_read(f))), "x")
})

test_that("a declaration can be prepended", {
  s <- xml_serialize(xml_parse('<?xml version="1.0" encoding="UTF-8"?><a/>'),
                     declaration = TRUE)
  expect_match(s, "^<\\?xml version=\"1\\.0\" encoding=\"UTF-8\"\\?>")
})

test_that("a deep document serializes without recursion", {
  deep <- paste0(strrep("<a>", 20000), "x", strrep("</a>", 20000))
  d <- xml_parse(deep, max_depth = 50000L)
  s <- xml_serialize(d)
  expect_identical(nchar(s), nchar(deep))
  expect_identical(xml_serialize(xml_parse(s, max_depth = 50000L)), s)
})

test_that("UTF-8 survives round-tripping byte for byte", {
  txt <- "naïve café 中文 \U0001F600"
  d2 <- xml_parse(xml_serialize(xml_parse(paste0("<a>", txt, "</a>"))))
  expect_identical(xml_text(xml_root(d2)), txt)
})

test_that("a carriage return in text is escaped, not emitted literally", {
  # Escaping it in attribute values but not in text left the round trip
  # lossy: XML 1.0 section 2.11 rewrites a literal CR in content to LF.
  d <- xml_parse("<a>x&#13;y</a>")
  expect_identical(xml_text(xml_root(d)), "x\ry")

  s <- xml_serialize(d)
  expect_match(s, "&#13;", fixed = TRUE)
  expect_false(grepl("\r", s, fixed = TRUE))

  expect_identical(xml_text(xml_root(xml_parse(s))), "x\ry")
  expect_identical(xml_serialize(xml_parse(s)), s)
})

test_that("a literal CR in the source is still normalized to LF", {
  # The parser side of section 2.11 is unchanged: only a character reference
  # is meant to survive.
  expect_identical(xml_text(xml_root(xml_parse("<a>x\ry</a>"))), "x\ny")
})

test_that("the declaration states the encoding actually emitted", {
  # The serializer always emits UTF-8. Echoing the source document's
  # declared encoding produced a file whose declaration contradicted its
  # own bytes, so xml_write() -> xml_read() silently corrupted text.
  lat <- c(charToRaw('<?xml version="1.0" encoding="ISO-8859-1"?><a>caf'),
           as.raw(0xe9), charToRaw("</a>"))
  d <- xml_parse(lat)
  expect_identical(xml_encoding(d), "ISO-8859-1")

  s <- xml_serialize(d, declaration = TRUE)
  expect_match(s, '^<\\?xml version="1\\.0" encoding="UTF-8"\\?>')

  f <- tempfile(fileext = ".xml")
  xml_write(d, f)
  expect_identical(xml_text(xml_root(xml_read(f))), xml_text(xml_root(d)))
})

test_that("a declaration is refused for a multi-node nodeset", {
  # paste0() is vectorized, so this used to prepend one declaration per node
  # and write a file that zuxml itself could not re-parse.
  ns <- xml_children(xml_root(xml_parse("<r><a>1</a><b>2</b></r>")))
  expect_length(ns, 2L)
  expect_error(xml_serialize(ns, declaration = TRUE), class = "zuxml_invalid_argument")
  expect_error(xml_write(ns, tempfile(fileext = ".xml")),
               class = "zuxml_invalid_argument")

  # Writing a fragment without a declaration stays allowed.
  f <- tempfile(fileext = ".xml")
  xml_write(ns, f, declaration = FALSE)
  expect_identical(readChar(f, file.size(f), useBytes = TRUE),
                   "<a>1</a><b>2</b>")
})

test_that("']]>' is escaped across a text node split by a dropped node", {
  # esc_text() decided whether a '>' needed escaping by looking two bytes back
  # in the *current* text node. Dropping a comment or PI leaves two text nodes
  # adjacent in the output, so the ']]' sat in the previous node and neither
  # node contained ']]>' on its own -- zuxml emitted a document it could not
  # itself re-parse. The test is now against the bytes already written.
  seams <- c(
    "<a>]]<!--c-->></a>",
    "<a>]<!--c-->]></a>",
    "<a>]]<?p d?>></a>",
    "<a>]<?p d?>]></a>",
    "<a>]]<!--c--><!--d-->></a>",
    "<a><![CDATA[]]]]><!--c--><![CDATA[>]]></a>",
    "<a>]]<!--c-->]]<?p d?>></a>"
  )
  for (xml in seams) {
    for (drop in list(list(comments = FALSE), list(pis = FALSE),
                      list(comments = FALSE, pis = FALSE))) {
      d <- do.call(xml_parse, c(list(xml), drop))
      s <- xml_serialize(d)
      # Whatever zuxml writes, zuxml must read back -- and to a fixed point.
      d2 <- do.call(xml_parse, c(list(s), drop))
      expect_identical(xml_serialize(d2), s, info = paste(xml, names(drop)))
      # The escape has to be present, not merely tolerated.
      expect_false(grepl("]]>", s, fixed = TRUE), info = paste(xml, names(drop)))
    }
  }
})

test_that("a bare '>' is still left alone after the seam fix", {
  # Escaping against the output buffer must not start over-escaping: '>' only
  # needs an escape where it would close a CDATA section.
  expect_identical(xml_serialize(xml_parse("<a>x > y</a>")), "<a>x > y</a>")
  expect_identical(xml_serialize(xml_parse("<a>]> y</a>")), "<a>]> y</a>")
  expect_identical(xml_serialize(xml_parse("<a>&gt;</a>")), "<a>></a>")
  expect_identical(xml_serialize(xml_parse("<a>]]</a>")), "<a>]]</a>")
  # An attribute value ending in ']]' is followed by its own quote, so a '>'
  # in the following text must not pick it up.
  expect_identical(xml_serialize(xml_parse('<a v="]]">&gt;</a>')),
                   '<a v="]]">></a>')
})

test_that("the round trip holds under every comment and PI setting", {
  # fuzz_roundtrip.c only ever ran with both kept, which is why the seam above
  # survived 2.5M executions. Cover the option matrix here too.
  for (nm in names(corpus)) {
    for (keep_c in c(TRUE, FALSE)) for (keep_p in c(TRUE, FALSE)) {
      d <- xml_parse(corpus[[nm]], comments = keep_c, pis = keep_p)
      s1 <- xml_serialize(d)
      s2 <- xml_serialize(xml_parse(s1, comments = keep_c, pis = keep_p))
      expect_identical(s2, s1,
                       info = sprintf("%s comments=%s pis=%s", nm, keep_c, keep_p))
    }
  }
})
