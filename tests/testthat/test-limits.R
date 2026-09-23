ev <- function(...) zuxml:::zux_event_log(...)
st <- function(...) zuxml:::zux_event_log(...)$status

nest <- function(n) paste0(paste(rep("<a>", n), collapse = ""),
                           paste(rep("</a>", n), collapse = ""))

test_that("each limit reports its own distinct status", {
  expect_identical(st(nest(50), max_depth = 10), "maximum nesting depth exceeded")

  expect_identical(st("<r><a/><b/><c/><d/></r>", max_nodes = 3),
                   "maximum node count exceeded")

  attrs <- paste(sprintf('a%d="1"', 1:40), collapse = " ")
  expect_identical(st(sprintf("<r %s/>", attrs), max_attrs = 10),
                   "maximum attribute count exceeded")

  expect_identical(st(sprintf("<a>%s</a>", strrep("x", 5000)), max_text = 100),
                   "maximum text size exceeded")

  # Isolate max_memory by leaving max_text generous: the allocation charge
  # then trips first, proving the two limits are independent.
  expect_identical(
    st(sprintf("<a>%s</a>", strrep("x", 500000)),
       max_text = 10e6, max_memory = 8192),
    "memory limit exceeded")
})

test_that("limits do not fire on input that is within them", {
  expect_identical(st(nest(10), max_depth = 10), "ok")
  expect_identical(st("<r><a/></r>", max_nodes = 3), "ok")
  expect_identical(st('<r a="1" b="2"/>', max_attrs = 2), "ok")
  expect_identical(st("<a>hello</a>", max_text = 5), "ok")
})

test_that("depth is measured on nesting, not on document length", {
  wide <- paste0("<r>", strrep("<a/>", 500), "</r>")
  expect_identical(st(wide, max_depth = 3), "ok")
})

test_that("the text limit is enforced during coalescing, not after", {
  # Text arrives in many callbacks here. If the check happened only once the
  # run was complete, an attacker could allocate freely before it tripped.
  chunked <- paste0("<a>", strrep("x&amp;", 20000), "</a>")
  expect_identical(st(chunked, max_text = 1000), "maximum text size exceeded")
})

test_that("limit failures report a position", {
  r <- ev(nest(50), max_depth = 10)
  expect_gt(r$byte_offset, 0)
  expect_gte(r$line, 1)
})

test_that("Inf asks for each limit's largest value", {
  wide <- paste0("<r>", strrep("<i/>", 50), "</r>")
  deep <- paste0(strrep("<d>", 40), strrep("</d>", 40))
  for (arg in c("max_depth", "max_nodes", "max_attrs", "max_text",
                "max_memory")) {
    args <- stats::setNames(list(Inf), arg)
    expect_s3_class(do.call(xml_parse, c(list(wide), args)), "zuxml_document")
    expect_s3_class(do.call(xml_parse, c(list(deep), args)), "zuxml_document")
  }
})

test_that("a finite limit above its cap is refused, not clamped or wrapped", {
  # max_depth, max_nodes and max_attrs are uint32_t in C. A bare cast once
  # wrapped max_nodes = 2^32 + 10 to 10; a clamp then hid the value instead.
  # max_nodes stops at INT_MAX, because node ids are R integers.
  wide <- paste0("<r>", strrep("<i/>", 50), "</r>")
  expect_s3_class(xml_parse(wide, max_nodes = .Machine$integer.max),
                  "zuxml_document")
  expect_s3_class(xml_parse(wide, max_depth = 2^32 - 1), "zuxml_document")

  expect_error(xml_parse(wide, max_nodes = 2^31), class = "zuxml_invalid_argument")
  expect_error(xml_parse(wide, max_nodes = 2^32 + 10),
               class = "zuxml_invalid_argument")
  expect_error(xml_parse(wide, max_depth = 2^32), class = "zuxml_invalid_argument")
  expect_error(xml_parse(wide, max_attrs = 2^40), class = "zuxml_invalid_argument")
  expect_error(xml_parse(wide, max_text = 2^60), class = "zuxml_invalid_argument")

  # Limits below the cap are still enforced exactly.
  deep <- paste0(strrep("<d>", 40), strrep("</d>", 40))
  expect_error(xml_parse(wide, max_nodes = 5), class = "zuxml_node_limit")
  expect_error(xml_parse(deep, max_depth = 5), class = "zuxml_depth_limit")
})

test_that("a limit that is not a positive whole number is refused", {
  # Each of these used to become the default silently (-1, 0, NA, "10"), or
  # was truncated and then reported as a parse error (0.5).
  bad <- list(-1, 0, 0.5, NA, NA_real_, NaN, -Inf, "10", c(10, 20),
              numeric(), NULL, TRUE)
  for (arg in c("max_depth", "max_nodes", "max_attrs", "max_text",
                "max_memory")) {
    for (v in bad) {
      e <- tryCatch(do.call(xml_parse, c(list("<a/>"),
                                         stats::setNames(list(v), arg))),
                    error = function(e) e)
      expect_s3_class(e, "zuxml_invalid_argument")
      expect_identical(e$arg, arg, info = paste(arg, deparse(v)))
    }
  }
  # A whole number held as a double, or as an integer, is fine.
  expect_s3_class(xml_parse("<a/>", max_depth = 3), "zuxml_document")
  expect_s3_class(xml_parse("<a/>", max_depth = 3L), "zuxml_document")
})
