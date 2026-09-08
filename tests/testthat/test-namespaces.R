evs <- function(...) zuxml:::zux_event_log(...)$events
st  <- function(...) zuxml:::zux_event_log(...)$status

test_that("a default namespace applies to elements", {
  expect_identical(evs('<a xmlns="urn:d"/>'),
                   c("start|{urn:d}a^|n=0", "end|{urn:d}a^"))
})

test_that("a prefix is reported but identity is the URI", {
  expect_identical(evs('<p:a xmlns:p="urn:d"/>'),
                   c("start|{urn:d}a^p|n=0", "end|{urn:d}a^p"))
})

test_that("the same local name in different namespaces stays distinct", {
  r <- evs('<r xmlns:a="urn:a" xmlns:b="urn:b"><a:item/><b:item/></r>')
  expect_true("start|{urn:a}item^a|n=0" %in% r)
  expect_true("start|{urn:b}item^b|n=0" %in% r)
})

test_that("two prefixes bound to one URI are the same name", {
  r <- evs('<r xmlns:x="urn:same" xmlns:y="urn:same"><x:i/><y:i/></r>')
  starts <- grep("^start\\|\\{urn:same\\}i", r, value = TRUE)
  expect_length(starts, 2)
  expect_identical(sub("\\^.*$", "", starts[1]), sub("\\^.*$", "", starts[2]))
})

test_that("nested namespace shadowing resolves innermost-first", {
  r <- evs('<a xmlns="urn:one"><b xmlns="urn:two"><c/></b></a>')
  expect_true("start|{urn:one}a^|n=0" %in% r)
  expect_true("start|{urn:two}b^|n=0" %in% r)
  expect_true("start|{urn:two}c^|n=0" %in% r)
})

test_that("unqualified attributes are in NO namespace, not the default one", {
  # A classic XML bug: the default namespace never applies to attributes.
  r <- evs('<a xmlns="urn:d" id="1"/>')
  expect_true("  attr|{}id^|1" %in% r)
})

test_that("prefixed attributes carry their own namespace", {
  r <- evs('<a xmlns:p="urn:p" p:id="1"/>')
  expect_true("  attr|{urn:p}id^p|1" %in% r)
})

test_that("xmlns declarations are not reported as attributes", {
  r <- evs('<a xmlns="urn:d" xmlns:p="urn:p"/>')
  expect_identical(r[[1]], "start|{urn:d}a^|n=0")
  expect_false(any(grepl("attr\\|.*xmlns", r)))
})

test_that("the namespace separator cannot be injected through a URI", {
  # 0x0C is not a legal XML 1.0 Char, so it can reach neither a literal URI
  # nor one built with a character reference. That impossibility is what
  # makes the triplet split unambiguous -- see design section 8.
  expect_identical(st('<a xmlns="urn:a&#12;b"/>'), "invalid XML")
  expect_identical(st("<a xmlns=\"urn:a\fb\"/>"), "invalid XML")
})
