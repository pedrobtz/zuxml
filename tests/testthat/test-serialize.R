corpus <- c(
  empty_elem  = "<a/>",
  nested      = "<a><b><c>x</c></b></a>",
  mixed       = "<p>Hello <em>XML</em> world</p>",
  attrs       = '<a id="1" lang="en" k="a b c"/>',
  esc_attr    = '<a x="a&amp;b&lt;c&quot;d"/>',
  esc_text    = "<a>a &amp; b &lt; c &gt; d</a>",
  cdata       = "<a><![CDATA[x<y&z]]>tail</a>",
  ns_prefix   = '<f:a xmlns:f="urn:a"><f:b/></f:a>',
  ns_default  = '<a xmlns="urn:d"><b><c/></b></a>',
  ns_shadow   = '<a xmlns="urn:one"><b xmlns="urn:two"><c/></b></a>',
  ns_reset    = '<a xmlns="urn:d"><b xmlns=""><c/></b></a>',
  ns_same_uri = '<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i/><y:i/></r>',
  ns_attr     = '<a xmlns:p="urn:p" p:k="v" plain="w"/>',
  comment_pi  = "<a><!-- note --><?target data?>t</a>",
  utf8        = "<a>naïve café 中文 \U0001F600</a>",
  whitespace  = "<a>  leading and trailing  <b/>  </a>",
  wide        = paste0("<r>", strrep('<i a="1">t</i>', 30), "</r>"),
  deep        = paste0(strrep("<a>", 60), "x", strrep("</a>", 60)),
  attr_ws     = '<a t="line1&#10;line2&#9;tab"/>',
  cdata_close = "<a>a ]]&gt; b</a>"
)

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
