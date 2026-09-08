ev  <- function(...) zuxml:::zux_event_log(...)
evs <- function(...) zuxml:::zux_event_log(...)$events
st  <- function(...) zuxml:::zux_event_log(...)$status

# These are permanent regression tests. If one of them starts passing for a
# different reason than the one stated, that is a finding, not a convenience.

test_that("XXE: an external entity never reaches the filesystem", {
  secret <- tempfile(fileext = ".txt")
  on.exit(unlink(secret), add = TRUE)
  writeLines("CANARY-8f3a2b-DO-NOT-LEAK", secret)

  doc <- sprintf('<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file://%s">]><foo>&xxe;</foo>',
                 secret)
  r <- ev(doc)

  expect_identical(r$status, "document type declaration is not allowed")
  expect_false(any(grepl("CANARY", r$events, fixed = TRUE)))
  expect_length(r$events, 0L)
})

test_that("XXE: a reference to a nonexistent path fails the same way", {
  # Proves rejection happens at the DOCTYPE, before any resolution attempt.
  # A file-not-found style failure here would mean we had tried to open it.
  missing <- file.path(tempdir(), "definitely-absent-a91f.dtd")
  expect_false(file.exists(missing))
  r <- ev(sprintf('<!DOCTYPE foo SYSTEM "file://%s"><foo/>', missing))
  expect_identical(r$status, "document type declaration is not allowed")
})

test_that("XXE: a network SYSTEM identifier is rejected without a request", {
  r <- ev('<!DOCTYPE foo [<!ENTITY x SYSTEM "http://127.0.0.1:1/x">]><foo>&x;</foo>')
  expect_identical(r$status, "document type declaration is not allowed")
})

test_that("allow_doctype accepts bare and PUBLIC/SYSTEM declarations", {
  # These are what real feeds actually carry, and they declare no entities.
  expect_identical(st("<!DOCTYPE a><a>hi</a>", allow_doctype = TRUE), "ok")
  expect_identical(
    st('<!DOCTYPE a PUBLIC "-//X//EN" "http://x/a.dtd"><a>hi</a>',
       allow_doctype = TRUE), "ok")
})

test_that("an internal subset is rejected even when allow_doctype is set", {
  # With XML_GE 0 Expat does not record entity declarations, and a reference
  # to one is then passed through as LITERAL TEXT rather than erroring --
  # "&e;" would arrive as four characters of content, silently wrong, and a
  # later serialize would re-escape it to "&amp;e;". The internal subset is
  # the only place a document can declare entities, so it is refused
  # outright. This test exists because that corruption was real, not
  # theoretical.
  secret <- tempfile(fileext = ".txt")
  on.exit(unlink(secret), add = TRUE)
  writeLines("CANARY-8f3a2b-DO-NOT-LEAK", secret)

  r <- ev('<!DOCTYPE a [<!ENTITY e "X">]><a>x&e;y</a>', allow_doctype = TRUE)
  expect_identical(r$status, "document type declaration is not allowed")
  expect_false(any(grepl("&e;", r$events, fixed = TRUE)))

  r <- ev(sprintf('<!DOCTYPE a [<!ENTITY e SYSTEM "file://%s">]><a>&e;</a>',
                  secret), allow_doctype = TRUE)
  expect_identical(r$status, "document type declaration is not allowed")
  expect_false(any(grepl("CANARY", r$events, fixed = TRUE)))
})

test_that("an undeclared entity still errors under allow_doctype", {
  expect_identical(st("<!DOCTYPE a><a>x&nbsp;y</a>", allow_doctype = TRUE),
                   "undefined entity reference")
})

test_that("built-in entities still work alongside an accepted DOCTYPE", {
  expect_identical(evs("<!DOCTYPE a><a>x&amp;y</a>", allow_doctype = TRUE),
                   c("start|{}a^|n=0", "text|x&y", "end|{}a^"))
})

test_that("billion laughs is stopped before any expansion", {
  bomb <- paste0(
    '<!DOCTYPE lolz [',
    '<!ENTITY lol "lol">',
    '<!ENTITY lol1 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">',
    '<!ENTITY lol2 "&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;&lol1;">',
    '<!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">',
    ']><lolz>&lol3;</lolz>')

  # Rejected on the DOCTYPE either way: the bomb needs an internal subset to
  # declare its entities, and internal subsets are always refused.
  expect_identical(st(bomb), "document type declaration is not allowed")
  expect_identical(st(bomb, allow_doctype = TRUE),
                   "document type declaration is not allowed")
})

test_that("a recursive entity cannot be declared into existence", {
  expect_identical(st('<!DOCTYPE a [<!ENTITY e "&e;">]><a>&e;</a>',
                      allow_doctype = TRUE),
                   "document type declaration is not allowed")
})

test_that("an undefined entity is a hard error, including HTML names", {
  # Documented v1 limitation: &nbsp; in a feed that never declared it is not
  # well-formed XML and is rejected. See design section 22, question 4.
  expect_identical(st("<a>&nbsp;</a>"), "undefined entity reference")
  expect_identical(st("<a>&mdash;</a>"), "undefined entity reference")
  expect_identical(st('<a t="&nbsp;"/>'), "undefined entity reference")
})

test_that("unterminated and malformed lexical constructs fail cleanly", {
  expect_identical(st("<a><![CDATA[unterminated</a>"), "invalid XML")
  expect_identical(st("<!DOCTYPE"), "invalid XML")
  expect_identical(st("<a><!-- unterminated </a>"), "invalid XML")
})

test_that("no test in this file performs network or file I/O on parse", {
  # Guard against a future refactor quietly enabling resolution.
  info <- zuxml_info()
  expect_false(info$dtd)
  expect_false(info$general_entities)
})
