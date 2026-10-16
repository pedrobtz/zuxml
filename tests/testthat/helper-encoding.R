# For test-encoding.R. The bug these guard only shows outside a UTF-8 locale,
# where paste() has to fall back to the native encoding. Both strings are
# built from explicit bytes so the fixture does not depend on how this file
# itself is decoded.
latin1_str <- function(bytes) {
  s <- rawToChar(as.raw(bytes))
  Encoding(s) <- "latin1"
  s
}

in_c_locale <- function(code) {
  old <- Sys.getlocale("LC_CTYPE")
  if (identical(Sys.setlocale("LC_CTYPE", "C"), "")) skip("cannot set the C locale")
  on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
  force(code)
}
