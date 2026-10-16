# For test-source.R, the suite of the byte source shared with sibling
# packages, and test-read.R. A sibling package copies this file with
# test-source.R and changes only read_input and prefix below.
read_input <- xml_read
prefix <- "zuxml"
msg <- function(x) paste0("^", prefix, ": ", x)

big_doc <- function(n = 20000L) {
  # Well over three feed chunks, so the connection loop reads more than once.
  paste0("<r>", strrep("<i a='1'>text</i>", n), "</r>")
}
