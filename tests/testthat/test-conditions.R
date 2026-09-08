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

test_that("the message is prose, not an Expat constant", {
  e <- tryCatch(xml_parse("<a><b></a>"), error = function(e) e)
  expect_false(grepl("XML_ERROR", conditionMessage(e)))
})

`%||%` <- function(a, b) if (is.null(a)) b else a
