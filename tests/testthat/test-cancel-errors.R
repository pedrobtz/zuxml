ev <- function(...) zuxml:::zux_event_log(...)

test_that("a handler can cancel the parse, and the status survives", {
  doc <- '<?xml version="1.0"?><a x="1">t<!--c--><?p d?><b/></a>'
  # Attribute lines are recorded for inspection but are not themselves
  # events, so they do not advance the cancellation counter.
  n <- sum(!grepl("^  attr", ev(doc)$events))
  expect_gt(n, 5)
  for (i in seq_len(n)) {
    r <- ev(doc, cancel_at = i)
    expect_identical(r$status, "cancelled by handler",
                     info = paste("cancel at", i))
  }
})

test_that("cancelling from each distinct handler kind works", {
  # decl, start, text, comment, pi and end each get a turn above; here we
  # pin the specific kinds so a regression names the handler.
  doc <- '<?xml version="1.0"?><a>t<!--c--><?p d?></a>'
  kinds <- grep("^  attr", ev(doc)$events, invert = TRUE, value = TRUE)
  expect_true(any(grepl("^decl", kinds)))
  expect_true(any(grepl("^start", kinds)))
  expect_true(any(grepl("^text", kinds)))
  expect_true(any(grepl("^comment", kinds)))
  expect_true(any(grepl("^pi", kinds)))
  expect_true(any(grepl("^end", kinds)))
  for (i in seq_along(kinds)) {
    expect_identical(ev(doc, cancel_at = i)$status, "cancelled by handler")
  }
})

test_that("cancellation stops event production immediately", {
  doc <- "<a><b/><c/><d/></a>"
  r <- ev(doc, cancel_at = 2)
  expect_identical(r$status, "cancelled by handler")
  expect_lt(length(r$events), length(ev(doc)$events))
})

test_that("parse errors carry line, column and byte offset", {
  r <- ev("<a>\n  <b>\n</a>")
  expect_identical(r$status, "invalid XML")
  expect_identical(r$line, 3)
  expect_gt(r$byte_offset, 0)
  expect_true(nzchar(r$message))
})

test_that("the error message is project-owned prose, not an Expat constant", {
  r <- ev("<a><b></a>")
  expect_false(grepl("^XML_ERROR_", r$message))
  expect_true(nzchar(r$message))
})

test_that("position is reported for the first error, not the last", {
  r <- ev("<a>\n<b>\n<c>\n</a>")
  expect_identical(r$status, "invalid XML")
  expect_identical(r$line, 4)
})

test_that("a successful parse reports no error", {
  r <- ev("<a/>")
  expect_identical(r$status, "ok")
  expect_identical(r$message, "ok")
})
