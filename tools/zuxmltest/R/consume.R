consume_xml <- function(x, chunk = 0L) {
  if (is.character(x)) x <- charToRaw(paste(x, collapse = ""))
  .Call(C_consume, x, as.integer(chunk))
}
