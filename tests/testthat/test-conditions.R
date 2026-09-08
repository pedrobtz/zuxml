test_that("every documented condition class is reachable with metadata", {
  cases <- list(
    list(x = "<a><b></a>",                      cls = "zuxml_parse_error"),
    list(x = "<a>&nbsp;</a>",                   cls = "zuxml_parse_error"),
    list(x = "<!DOCTYPE a><a/>",                cls = "zuxml_doctype_error"),
    list(x = '<!DOCTYPE a [<!ENTITY e "x">]><a/>', cls = "zuxml_doctype_error",
         args = list(allow_doctype = TRUE)),
    list(x = paste0(strrep("<a>", 50), strrep("</a>", 50)),
         cls = "zuxml_depth_limit", args = list(max_depth = 5)),
    list(x = "<r><a/><b/><c/></r>",
         cls = "zuxml_node_limit", args = list(max_nodes = 2)),
    list(x = "<r a='1' b='2' c='3'/>",
         cls = "zuxml_attr_limit", args = list(max_attrs = 2)),
    list(x = sprintf("<a>%s</a>", strrep("x", 5000)),
         cls = "zuxml_text_limit", args = list(max_text = 10)),
    list(x = "<r><a/></r>",
         cls = "zuxml_memory_limit", args = list(max_memory = 64))
  )
  for (cs in cases) {
    e <- tryCatch(do.call(xml_parse, c(list(cs$x), cs$args %||% list())),
                  error = function(e) e)
    expect_s3_class(e, cs$cls)
    expect_s3_class(e, "zuxml_error")
    expect_true(nzchar(conditionMessage(e)), info = cs$cls)
  }
})

test_that("limit errors share a catchable parent class", {
  e <- tryCatch(xml_parse("<r><a/><b/></r>", max_nodes = 1),
                zuxml_limit_error = function(e) e)
  expect_s3_class(e, "zuxml_limit_error")
})

test_that("parse errors carry line, column and byte offset", {
  e <- tryCatch(xml_parse("<a>\n  <b>\n</a>"), error = function(e) e)
  expect_identical(e$line, 3)
  expect_gt(e$byte_offset, 0)
  expect_match(conditionMessage(e), "line 3")
})

test_that("every error message is non-empty prose", {
  # Regression: zux_error.message used to be a pointer into the parser, but
  # zux_tree_end() and the R error path both free the parser before the
  # caller reads it, so every message was read from freed memory and
  # arrived empty. It is an inline buffer now. Caught by writing the
  # vignette, not by the fuzzers -- they never read the message.
  cases <- list(
    list(x = "<a>\n  <b>\n</a>"),
    list(x = "<a><b></a>"),
    list(x = "<a>&nbsp;</a>"),
    list(x = '<!DOCTYPE foo [<!ENTITY e SYSTEM "file:///etc/passwd">]><foo>&e;</foo>'),
    list(x = "<r><a/><b/></r>", args = list(max_nodes = 2)),
    list(x = paste0(strrep("<a>", 20), strrep("</a>", 20)),
         args = list(max_depth = 3))
  )
  for (cs in cases) {
    e <- tryCatch(do.call(xml_parse, c(list(cs$x), cs$args %||% list())),
                  error = function(e) e)
    msg <- conditionMessage(e)
    expect_true(nzchar(msg), info = cs$x)
    # not just punctuation left over from an empty interpolation
    expect_match(msg, "[A-Za-z]{4,}", info = cs$x)
    expect_false(grepl(": *$", msg), info = cs$x)
  }
})

test_that("the message is prose, not an Expat constant", {
  e <- tryCatch(xml_parse("<a><b></a>"), error = function(e) e)
  expect_false(grepl("XML_ERROR", conditionMessage(e)))
})

`%||%` <- function(a, b) if (is.null(a)) b else a
