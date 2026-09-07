test_that("the compiled library is loaded with symbol search disabled", {
  expect_true("zuxml" %in% names(getLoadedDLLs()))
})
