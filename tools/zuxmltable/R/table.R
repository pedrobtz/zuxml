as_bytes <- function(x) {
  if (is.character(x)) charToRaw(paste(x, collapse = "")) else x
}

# Which of the table's members the running zuxml provides, and the table's
# size as registered versus as this fixture's header declares it.
table_members <- function() .Call(C_members)

# A streaming parse through parser_new/feed/finish/error/free, fed `chunk`
# bytes at a time (0 = the whole buffer at once). Returns the event log.
table_events <- function(x, chunk = 0L) {
  .Call(C_events, as_bytes(x), as.integer(chunk))
}

# The same document built twice -- incrementally through tree_begin/feed/end,
# and whole through tree_parse -- then walked with every accessor and
# serialized, so the two can be compared.
table_tree <- function(x, chunk = 0L) {
  .Call(C_tree, as_bytes(x), as.integer(chunk))
}

# tree_begin, feed the first `after` bytes, then tree_abort a live builder.
table_abort <- function(x, after) {
  .Call(C_abort, as_bytes(x), as.integer(after))
}

# How a consumer built against this header behaves on an older zuxml whose
# table ends before set_message: ZUXML_API_HAS() must say so, and the
# consumer must fall back instead of calling past the end.
table_degrade <- function() .Call(C_degrade)
