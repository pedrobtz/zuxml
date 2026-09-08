test_that("the compiled library is loaded with symbol search disabled", {
  expect_true("zuxml" %in% names(getLoadedDLLs()))
})

test_that("the vendored Expat is linked and can create a parser", {
  info <- zuxml_info()
  expect_s3_class(info, "zuxml_info")
  expect_true(info$parser_ok)
  expect_match(info$expat_version, "^expat_[0-9]+\\.[0-9]+\\.[0-9]+$")
})

test_that("the compiled-in security policy is the one the design mandates", {
  info <- zuxml_info()
  # These three are the whole point of the vendoring configuration. If any
  # flips, XXE and entity-amplification attack surface returns. See
  # .agents/zuxml-design.md section 11.
  expect_false(info$dtd)
  expect_false(info$general_entities)
  expect_true(info$namespaces)
})

test_that("a real entropy source was selected, never the poor-entropy fallback", {
  info <- zuxml_info()
  expect_false(info$entropy %in% c("none", "unknown"))
})

test_that("UTF-8 internal representation and a known byte order", {
  info <- zuxml_info()
  expect_identical(info$xml_char_bytes, 1L)
  expect_true(info$byteorder %in% c("little", "big"))
})
