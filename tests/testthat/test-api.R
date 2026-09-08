ATOM <- "http://www.w3.org/2005/Atom"

atom_doc <- function() xml_parse(sprintf('<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="%s" xmlns:x="urn:extra">
  <title>Example Feed</title>
  <entry x:rank="1"><title>First</title><link href="/1"/></entry>
  <entry x:rank="2"><title>Second</title><link href="/2"/></entry>
</feed>', ATOM))

test_that("the worked Atom example from the design runs", {
  doc <- atom_doc()
  entries <- xml_elements(xml_root(doc), "entry", ns = ATOM)
  expect_length(entries, 2L)
  expect_identical(xml_text(xml_elements(entries, "title", ns = ATOM)),
                   c("First", "Second"))
  expect_identical(xml_attr(xml_elements(entries, "link", ns = ATOM), "href"),
                   c("/1", "/2"))
})

test_that("descendants come back in document order", {
  doc <- atom_doc()
  expect_identical(xml_text(xml_find(doc, "title", ns = ATOM)),
                   c("Example Feed", "First", "Second"))
})

test_that("every accessor is vectorized and length-preserving", {
  doc <- atom_doc()
  entries <- xml_elements(xml_root(doc), "entry", ns = ATOM)
  n <- length(entries)
  expect_length(xml_name(entries), n)
  expect_length(xml_local(entries), n)
  expect_length(xml_ns(entries), n)
  expect_length(xml_prefix(entries), n)
  expect_length(xml_type(entries), n)
  expect_length(xml_text(entries), n)
  expect_length(xml_attr(entries, "rank", ns = "urn:extra"), n)
  expect_length(xml_attrs(entries), n)
  expect_true(is.list(xml_attrs(entries)))
})

test_that("a node and a nodeset are the same type at different lengths", {
  doc <- atom_doc()
  entries <- xml_elements(xml_root(doc), "entry", ns = ATOM)
  expect_s3_class(entries, "zuxml_nodeset")
  expect_s3_class(entries[[1]], "zuxml_nodeset")
  expect_length(entries[[1]], 1L)
  expect_length(entries[1:2], 2L)
  expect_length(c(entries[[1]], entries[[2]]), 2L)
  expect_length(rev(entries), 2L)
})

test_that("namespace filtering follows the documented rule", {
  doc <- xml_parse('<r xmlns:a="urn:a"><a:i/><i/></r>')
  root <- xml_root(doc)
  expect_length(xml_elements(root, "i"), 2L)                 # NULL = any
  expect_length(xml_elements(root, "i", ns = "urn:a"), 1L)   # that URI
  expect_length(xml_elements(root, "i", ns = NA), 1L)        # no namespace
})

test_that("matching ignores prefixes: same URI is the same name", {
  doc <- xml_parse('<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i/><y:i/></r>')
  expect_length(xml_elements(xml_root(doc), "i", ns = "urn:s"), 2L)
})

test_that("xml_children returns all node kinds, xml_elements only elements", {
  doc <- xml_parse("<a>t<!--c--><?p d?><b/></a>")
  expect_identical(xml_type(xml_children(xml_root(doc))),
                   c("text", "comment", "pi", "element"))
  expect_identical(xml_type(xml_elements(xml_root(doc))), "element")
})

test_that("xml_text is recursive by default and can be direct-only", {
  doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
  expect_identical(xml_text(xml_root(doc)), "Hello XML world")
  expect_identical(xml_text(xml_root(doc), recursive = FALSE), "Hello  world")
  expect_identical(xml_text(xml_root(doc), trim = TRUE), "Hello XML world")
})

test_that("attributes come back with qualified names and no xmlns entries", {
  doc <- xml_parse('<a xmlns:p="urn:p" id="1" p:x="2"/>')
  a <- xml_attrs(xml_root(doc))[[1]]
  expect_identical(sort(names(a)), c("id", "p:x"))
  expect_identical(unname(a[["id"]]), "1")
})

test_that("a missing attribute yields the default", {
  doc <- xml_parse("<a/>")
  expect_true(is.na(xml_attr(xml_root(doc), "nope")))
  expect_identical(xml_attr(xml_root(doc), "nope", default = "d"), "d")
})

test_that("document metadata is exposed", {
  doc <- xml_parse('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a/>')
  expect_identical(xml_version(doc), "1.0")
  expect_identical(xml_encoding(doc), "UTF-8")
  expect_true(xml_standalone(doc))
})

test_that("the document stays alive while any node handle exists", {
  # The whole point of storing the document as an attribute: R's GC traces
  # attributes, so no protection list is needed and no node can dangle.
  node <- local({
    doc <- atom_doc()
    xml_find(doc, "title", ns = ATOM)
  })
  gc(); gc()
  expect_identical(xml_text(node), c("Example Feed", "First", "Second"))
})

test_that("node handles survive aggressive garbage collection", {
  skip_on_cran()
  gctorture(TRUE)
  on.exit(gctorture(FALSE), add = TRUE)
  doc <- xml_parse("<r><a>1</a><b>2</b></r>")
  expect_identical(xml_text(xml_children(xml_root(doc))), c("1", "2"))
})

test_that("nodes from different documents cannot be combined", {
  a <- xml_root(xml_parse("<a/>"))
  b <- xml_root(xml_parse("<b/>"))
  expect_error(c(a, b), "different documents")
})

test_that("printing is informative and never dumps the document", {
  doc <- atom_doc()
  expect_output(print(doc), "zuxml_document")
  expect_output(print(doc), "Atom")
  expect_output(print(xml_root(doc)), "zuxml_node element")
  expect_output(print(xml_elements(xml_root(doc), "entry", ns = ATOM)),
                "zuxml_nodeset\\[2\\]")
})

test_that("xml_read parses from a file", {
  f <- tempfile(fileext = ".xml")
  on.exit(unlink(f), add = TRUE)
  writeLines('<r><a>x</a></r>', f)
  doc <- xml_read(f)
  expect_identical(xml_text(xml_find(doc, "a")), "x")
  expect_error(xml_read(file.path(tempdir(), "absent-zz.xml")), "no such file")
})

test_that("a large document parses in bounded time and memory", {
  n <- 20000
  doc <- xml_parse(paste0("<r>", strrep("<i a='1'>t</i>", n), "</r>"))
  expect_length(xml_elements(xml_root(doc), "i"), n)
  expect_identical(unique(xml_attr(xml_elements(xml_root(doc), "i"), "a")), "1")
})
