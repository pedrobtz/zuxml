ev  <- function(...) zuxml:::zux_event_log(...)
evs <- function(...) zuxml:::zux_event_log(...)$events
st  <- function(...) zuxml:::zux_event_log(...)$status

test_that("a minimal document produces the expected event sequence", {
  r <- ev("<a/>")
  expect_identical(r$status, "ok")
  expect_identical(r$events, c("start|{}a^|n=0", "end|{}a^"))
})

test_that("mixed content preserves child and text ordering exactly", {
  expect_identical(
    evs("<p>Hello <em>XML</em> world</p>"),
    c("start|{}p^|n=0", "text|Hello ", "start|{}em^|n=0", "text|XML",
      "end|{}em^", "text| world", "end|{}p^")
  )
})

test_that("CDATA becomes ordinary text with no distinct event", {
  expect_identical(evs("<a><![CDATA[x<y&z]]></a>"),
                   c("start|{}a^|n=0", "text|x<y&z", "end|{}a^"))
})

test_that("adjacent character data is coalesced into one text event", {
  # Entity references force Expat to emit several character-data callbacks
  # for what is logically one text run; the seam must merge them.
  expect_identical(evs("<a>x&amp;y&lt;z</a>"),
                   c("start|{}a^|n=0", "text|x&y<z", "end|{}a^"))
})

test_that("the five built-in entities and numeric references resolve", {
  expect_identical(evs("<a>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;</a>"),
                   c("start|{}a^|n=0", "text|&<>\"'AB", "end|{}a^"))
})

test_that("comments and processing instructions are retained by default", {
  r <- evs("<a><!-- hi --><?tgt data?></a>")
  expect_true("comment| hi " %in% r)
  expect_true("pi|tgt|data" %in% r)
})

test_that("comments and PIs can be suppressed independently", {
  r <- evs("<a><!-- hi --><?tgt data?></a>", comments = FALSE)
  expect_false(any(grepl("^comment", r)))
  expect_true(any(grepl("^pi", r)))

  r <- evs("<a><!-- hi --><?tgt data?></a>", pis = FALSE)
  expect_true(any(grepl("^comment", r)))
  expect_false(any(grepl("^pi", r)))
})

test_that("the XML declaration is reported", {
  r <- evs('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a/>')
  expect_identical(r[[1]], "decl|1.0|UTF-8|1")
})

test_that("malformed XML fails rather than producing partial nonsense", {
  expect_identical(st("<a><b></a>"), "invalid XML")
  expect_identical(st("<a>"), "invalid XML")
  expect_identical(st("not xml at all"), "invalid XML")
  expect_identical(st(""), "invalid XML")
})
