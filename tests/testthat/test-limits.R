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

test_that("nonsensical limits are rejected rather than silently clamped", {
  expect_identical(st("<a/>", max_depth = 0), "ok")  # 0 falls back to default
})
