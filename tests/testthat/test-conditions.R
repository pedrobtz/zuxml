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
  # article, not by the fuzzers -- they never read the message.
  #
  # This asserts on the C field, NOT on conditionMessage(): zux_abort()
  # wraps "<msg> (at line L, column C)" around most statuses, and that
  # suffix on its own is non-empty and contains the word "line", so a
  # wrapped message passes every check below even when the C message is "".
  c_parse <- function(x, ...) {
    .Call(zuxml:::C_zux_parse, charToRaw(x),
          c(list(encoding = "UTF-8"), list(...)))
  }
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
    res <- do.call(c_parse, c(list(cs$x), cs$args %||% list()))
    expect_false(identical(res$status, "ok"), info = cs$x)
    expect_true(nzchar(res$message), info = cs$x)
    # not a stray fragment: real words, from the C layer
    expect_match(res$message, "[A-Za-z]{4,}", info = cs$x)

    # and the condition zux_abort() builds from it is prose too
    e <- tryCatch(do.call(xml_parse, c(list(cs$x), cs$args %||% list())),
                  error = function(e) e)
    expect_true(grepl(res$message, conditionMessage(e), fixed = TRUE),
                info = cs$x)
    expect_false(grepl(": *$", conditionMessage(e)), info = cs$x)
  }
})

test_that("the message is prose, not an Expat constant", {
  e <- tryCatch(xml_parse("<a><b></a>"), error = function(e) e)
  expect_false(grepl("XML_ERROR", conditionMessage(e)))
})


test_that("every C status maps to a class by enumerator name", {
  # The map used to match the English status string, so rewording a message
  # in C would have silently turned, say, a limit error into a parse error.
  names <- .Call(zuxml:::C_zux_status_names)
  expect_true(all(c("ZUX_OK", "ZUX_ERR_DEPTH_LIMIT", "ZUX_ERR_INTERNAL") %in%
                    names))
  failures <- setdiff(names, c("ZUX_OK", "ZUX_DONE", "ZUX_ERR_INTERNAL"))
  for (nm in failures) {
    expect_true(length(zuxml:::zux_condition_class(nm)) > 0L, info = nm)
  }
  # And the map names nothing C does not have.
  expect_true(all(names(zuxml:::zux_status_class) %in% names))
})

test_that("statuses no exported R call can reach still raise their class", {
  # zuxml_cancelled needs a C handler, and zuxml_memory_error a failed
  # allocation. Neither can be provoked from R, so the mapping is checked
  # on a C result of the shape C_zux_parse() returns.
  res <- function(name) list(name = name, status = "x", message = "m",
                             line = 0, column = 0, byte_offset = 0,
                             expat_code = NA_integer_)
  for (cs in list(c("ZUX_ERR_CANCELLED", "zuxml_cancelled"),
                  c("ZUX_ERR_MEMORY", "zuxml_memory_error"),
                  c("ZUX_ERR_INVALID_ARGUMENT", "zuxml_invalid_argument"))) {
    e <- tryCatch(zuxml:::zux_abort(res(cs[[1]])), error = function(e) e)
    expect_s3_class(e, cs[[2]])
    expect_s3_class(e, "zuxml_error")
    expect_identical(e$status, cs[[1]])
  }
  # An internal error, or a status the map does not know, is still a
  # zuxml_error, and is not passed off as a parse error.
  for (nm in c("ZUX_ERR_INTERNAL", "ZUX_ERR_UNKNOWN")) {
    e <- tryCatch(zuxml:::zux_abort(res(nm)), error = function(e) e)
    expect_s3_class(e, "zuxml_error")
    expect_false(inherits(e, "zuxml_parse_error"))
  }
})

test_that("conditions carry the metadata design section 12 promises", {
  e <- tryCatch(xml_parse("<a><b></a>"), error = function(e) e)
  expect_identical(e$status, "ZUX_ERR_INVALID_XML")
  expect_type(e$expat_code, "integer")
  expect_false(is.na(e$expat_code))
  expect_null(e$limit)

  limits <- list(
    list(x = paste0(strrep("<a>", 50), strrep("</a>", 50)),
         arg = "max_depth", value = 5),
    list(x = "<r><a/><b/><c/></r>", arg = "max_nodes", value = 2),
    list(x = "<r a='1' b='2' c='3'/>", arg = "max_attrs", value = 2),
    list(x = sprintf("<a>%s</a>", strrep("x", 5000)), arg = "max_text",
         value = 10),
    list(x = "<r><a/></r>", arg = "max_memory", value = 64))
  for (cs in limits) {
    e <- tryCatch(do.call(xml_parse, c(list(cs$x),
                                       stats::setNames(list(cs$value), cs$arg))),
                  error = function(e) e)
    expect_s3_class(e, "zuxml_limit_error")
    expect_identical(e$limit, cs$arg)
    expect_identical(e$limit_value, cs$value)
    # A limit is not Expat's failure.
    expect_identical(e$expat_code, NA_integer_, info = cs$arg)
  }
})

test_that("a serializer failure is classed", {
  e <- tryCatch(zuxml:::zux_serialize_abort(
    list(name = "R_STRING_LIMIT", index = 2)), error = function(e) e)
  expect_s3_class(e, "zuxml_limit_error")
  e <- tryCatch(zuxml:::zux_serialize_abort(
    list(name = "ZUX_ERR_MEMORY", index = 1)), error = function(e) e)
  expect_s3_class(e, "zuxml_memory_error")
})
