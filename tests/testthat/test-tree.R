ti <- function(...) zuxml:::zux_tree_info(...)

test_that("the document node always exists and holds the root", {
  r <- ti("<a/>")
  expect_identical(r$status, "ok")
  expect_identical(r$dump, c("document", "  element|{}a^|n=0"))
})

test_that("mixed content keeps document order in the tree", {
  r <- ti("<p>Hello <em>XML</em> world</p>")
  expect_identical(r$dump, c(
    "document",
    "  element|{}p^|n=0",
    "    text|Hello ",
    "    element|{}em^|n=0",
    "      text|XML",
    "    text| world"))
})

test_that("the tree agrees with the event stream it was built from", {
  docs <- c("<a><b><c>x</c></b></a>",
            "<p>a <b>c</b> d</p>",
            '<r xmlns="urn:d"><i a="1"/><i a="2"/></r>',
            "<a><!--c--><?p d?>t</a>")
  for (doc in docs) {
    ev <- zuxml:::zux_event_log(doc)$events
    tr <- ti(doc)$dump
    n_start <- sum(grepl("^start\\|", ev))
    n_elem  <- sum(grepl("element\\|", tr))
    expect_identical(n_start, n_elem, info = doc)
    n_text_ev <- sum(grepl("^text\\|", ev))
    n_text_tr <- sum(grepl("text\\|", tr))
    expect_identical(n_text_ev, n_text_tr, info = doc)
  }
})

test_that("CDATA and adjacent runs coalesce into single text nodes", {
  r <- ti("<a>x&amp;y<![CDATA[<z>]]>w</a>")
  expect_identical(r$dump, c("document", "  element|{}a^|n=0",
                             "    text|x&y<z>w"))
})

test_that("names are interned, so repetition costs nothing", {
  n <- 5000
  doc <- paste0("<r>", strrep('<item k="v">t</item>', n), "</r>")
  r <- ti(doc)
  expect_identical(r$status, "ok")
  # r, item, k  -> three distinct qnames regardless of repetition count.
  expect_identical(r$n_names, 3)
  expect_identical(r$n_nodes, 2 + n * 2)   # document + r + n items + n texts
  expect_identical(r$n_attrs, n)
})

test_that("memory stays within the stated per-node budget", {
  n <- 20000
  doc <- paste0("<r>", strrep("<i/>", n), "</r>")
  r <- ti(doc)
  # Design section 5 budgets ~40 bytes/node plus text and attributes. Allow
  # headroom for geometric growth slack, but catch an order-of-magnitude
  # regression.
  expect_lt(r$bytes / r$n_nodes, 120)
})

test_that("attributes are attached to their element, not made children", {
  r <- ti('<a id="1" lang="en"/>')
  expect_identical(r$dump, c("document", "  element|{}a^|n=2"))
  expect_identical(r$n_attrs, 2)
})

test_that("namespaces survive into the tree", {
  r <- ti('<f:a xmlns:f="urn:a"><b xmlns="urn:d"/></f:a>')
  expect_true(any(grepl("element\\|\\{urn:a\\}a\\^f", r$dump)))
  expect_true(any(grepl("element\\|\\{urn:d\\}b\\^", r$dump)))
})

test_that("comments and PIs can be excluded from the tree", {
  r <- ti("<a><!--c--><?p d?>t</a>", comments = FALSE, pis = FALSE)
  expect_false(any(grepl("comment", r$dump)))
  expect_false(any(grepl("pi\\|", r$dump)))
  expect_true(any(grepl("text\\|t", r$dump)))
})

test_that("the XML declaration is recorded on the document", {
  r <- ti('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a/>')
  expect_identical(r$encoding, "UTF-8")
  expect_identical(r$standalone, 1L)
})

test_that("limits still apply when building a tree", {
  deep <- paste0(strrep("<a>", 500), strrep("</a>", 500))
  expect_identical(ti(deep, max_depth = 10)$status,
                   "maximum nesting depth exceeded")
  expect_identical(ti("<r><a/><b/><c/><d/></r>", max_nodes = 3)$status,
                   "maximum node count exceeded")
  expect_identical(ti(sprintf("<a>%s</a>", strrep("x", 5000)), max_text = 100)$status,
                   "maximum text size exceeded")
  expect_identical(ti("<r><a/></r>", max_memory = 64)$status,
                   "memory limit exceeded")
})

test_that("a failed parse yields no document rather than a partial one", {
  r <- ti("<a><b></a>")
  expect_identical(r$status, "invalid XML")
  expect_identical(r$n_nodes, 0)
  expect_length(r$dump, 0L)
})

test_that("deep nesting builds and frees without recursion", {
  # 100k deep. Construction, traversal and teardown are all iterative; the
  # standalone small-stack check in tools/run-sanitizers proves it for the C
  # layer under a 1 MB stack.
  deep <- paste0(strrep("<a>", 100000), strrep("</a>", 100000))
  # dump = FALSE: this test is about node counts, and rendering a 100k-deep
  # tree as indented text is a harness cost, not a library one.
  r <- ti(deep, max_depth = 200000L, max_memory = 512 * 1024^2, dump = FALSE)
  expect_identical(r$status, "ok")
  expect_identical(r$n_nodes, 100001)
  expect_identical(r$n_names, 1)
})

test_that("a wide document is handled as easily as a deep one", {
  wide <- paste0("<r>", strrep("<a/>", 50000), "</r>")
  r <- ti(wide, dump = FALSE)
  expect_identical(r$status, "ok")
  expect_identical(r$n_nodes, 50002)
})
