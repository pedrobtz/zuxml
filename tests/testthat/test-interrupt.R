# Stage 7's interrupt criterion: an interrupt during a long xml_parse() frees
# the partly built document and leaves the package usable. It was checked by
# hand with Ctrl-C, because signals did not reach R where the stage was
# developed (#37).
#
# setTimeLimit() reaches the same place a real interrupt does. Between 64 KiB
# feeds, parse_body() calls R_CheckUserInterrupt(), which calls
# R_ProcessEvents(), which enforces the time limit by raising an R error. That
# longjmp leaves R_UnwindProtect() exactly as Ctrl-C's does, so the cleanup
# under test is the same.
#
# The limit is set inside the same expression as the parse: a transient limit
# set as a separate top-level expression is reset before the next one runs.

big_doc <- function(mib) {
  item <- "<item id='1'><name>widget</name><price>9.99</price></item>"
  n <- ceiling(mib * 1024^2 / nchar(item))
  paste0("<items>", strrep(item, n), "</items>")
}

test_that("an interrupted parse frees its arena and leaves zuxml usable", {
  # Not skipped on CRAN: the sanitizer and valgrind jobs run R CMD check
  # --as-cran, and a skip there would leave the unwind path unexercised under
  # exactly the tools that can see a leak. 32 MiB in 20 ms would be over
  # 1.6 GB/s, several times what Expat manages, so a parse that finishes means
  # the interrupt was not honoured -- a failure, never a skip.
  x <- big_doc(32)
  gc()
  before <- zuxml:::zux_live_arenas()

  e <- tryCatch(local({
    setTimeLimit(elapsed = 0.02, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)
    xml_parse(x)
  }), error = function(e) e)

  # If this fires, the parse finished inside the limit and nothing was
  # interrupted: the test proves nothing, so it must not pass.
  expect_s3_class(e, "error")
  expect_false(inherits(e, "zuxml_error"))
  expect_match(conditionMessage(e), "time limit")

  # The partly built document went back when the stack unwound, not at the
  # next garbage collection: no gc() between the interrupt and this line.
  expect_identical(zuxml:::zux_live_arenas(), before)

  # And the package still parses, the same input included.
  doc <- xml_parse(x)
  expect_identical(xml_name(xml_root(doc)), "items")
  expect_identical(zuxml:::zux_live_arenas(), before + 1)
  rm(doc)
  gc()
  expect_identical(zuxml:::zux_live_arenas(), before)
})

test_that("the arena count follows every way a parse can end", {
  gc()
  before <- zuxml:::zux_live_arenas()
  # a document, then its release
  doc <- xml_parse("<a/>")
  expect_identical(zuxml:::zux_live_arenas(), before + 1)
  rm(doc)
  gc()
  expect_identical(zuxml:::zux_live_arenas(), before)
  # a failure while feeding, at the end, and before a builder exists
  try(xml_parse("<a><b></a>"), silent = TRUE)
  try(xml_parse("<a>", max_depth = 1), silent = TRUE)
  try(xml_parse("<a/>", max_memory = 1), silent = TRUE)
  expect_identical(zuxml:::zux_live_arenas(), before)
})
