# zu_source.R -- reading what a user passes: a path, a URL or a connection.
#
# Origin: zuxml 0.1.0, R/zu_source.R. This file is meant to be copied
# verbatim into sibling packages (zuhtml, zujson, zuyaml); keep this line
# current so drift between copies is visible. It knows nothing about the
# format being read: the package supplies a `feed` that takes each raw
# chunk, typically a .Call into an incremental parser.
#
# The reading is done here, in R, with readBin(), and not in C: the C
# entry points for connections (R_GetConnection, R_ReadConnection) are not
# part of R's API and R CMD check reports them as such.

# The kinds of input a reader accepts, resolved to a connection:
#
# - a connection is used as is;
# - a string with an http, https, ftp, ftps or file scheme is a url();
# - any other string is a path, checked here so the errors name the problem
#   rather than surfacing as a base R message about a non-regular file.
#
# Follows readBin()'s convention: an unopened connection is opened in "rb"
# and must be closed by the caller once done (the `close` flag says so);
# an open one must already be binary, is read from its current position,
# and is left open. The caller registers close() with on.exit() itself so
# the connection lives exactly as long as the caller's frame.
#
# `what` names the argument in error messages. `abort(arg, message)` raises
# the package's own classed invalid-argument condition; the default is a
# plain error with `prefix`, for a package that has none.
zu_open_input <- function(x, what = "path", prefix = "zuxml",
                          abort = function(arg, message)
                            stop(paste0(prefix, ": ", message), call. = FALSE)) {
  if (!inherits(x, "connection")) {
    if (!is.character(x) || length(x) != 1L || is.na(x))
      abort(what, sprintf("`%s` must be a single file path, URL or connection",
                          what))
    if (grepl("^(https?|ftps?|file)://", x, ignore.case = TRUE)) {
      # A scheme is case-insensitive by RFC 3986, but url() rejects "HTTP://".
      x <- url(sub("^([A-Za-z]+)://", "\\L\\1://", x, perl = TRUE))
    } else {
      # file.exists() is TRUE for a directory.
      if (dir.exists(x)) abort(what, sprintf("not a file: %s", x))
      if (!file.exists(x)) abort(what, sprintf("no such file: %s", x))
      x <- file(x)
    }
  }
  if (!isOpen(x)) {
    open(x, "rb")
    return(list(con = x, close = TRUE))
  }
  if (!identical(summary(x)$text, "binary"))
    abort(what, "an open connection must be in binary mode (\"rb\")")
  list(con = x, close = FALSE)
}

# Reads an open binary connection in `chunk`-byte pieces and hands each to
# `feed(bytes)`, until the input ends or `feed` returns FALSE (the parser
# has failed and the rest is not worth reading). R checks for a user
# interrupt between iterations, so a feed that calls into C need not.
#
# readBin() returns nothing both at end of input and, on a non-blocking
# connection, when no data has arrived yet. isIncomplete() tells the two
# apart; the second is refused rather than parsed as a truncated document.
zu_read_chunks <- function(con, feed, chunk = 65536L, what = "path",
                           prefix = "zuxml",
                           abort = function(arg, message)
                             stop(paste0(prefix, ": ", message), call. = FALSE)) {
  repeat {
    b <- readBin(con, "raw", n = chunk)
    if (length(b) == 0L) {
      if (isIncomplete(con))
        abort(what, paste0("the connection has no data available yet; ",
                           "a non-blocking connection cannot be read to the end"))
      break
    }
    if (!isTRUE(feed(b))) break
  }
  invisible(NULL)
}

# The rest of a connection as one raw vector, for the cases that cannot be
# streamed -- an encoding that must be transcoded whole, for instance.
zu_read_all <- function(con, chunk = 65536L, ...) {
  chunks <- list()
  zu_read_chunks(con, function(b) {
    chunks[[length(chunks) + 1L]] <<- b
    TRUE
  }, chunk = chunk, ...)
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}
