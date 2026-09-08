# Internal harness over the event seam, used by the test suite. Not exported:
# the supported R streaming interface is a phase-2 concern (design section 47).
zux_event_log <- function(x, chunk = 0L, cancel_at = 0L, ...) {
  if (is.character(x)) x <- charToRaw(paste(x, collapse = ""))
  stopifnot(is.raw(x))
  .Call(C_zux_event_log, x, as.integer(chunk), list(...), as.integer(cancel_at))
}

zux_events <- function(x, ...) zux_event_log(x, ...)$events
zux_status <- function(x, ...) zux_event_log(x, ...)$status

# Internal Stage 3 harness: build a tree and describe it.
zux_tree_info <- function(x, ...) {
  if (is.character(x)) x <- charToRaw(paste(x, collapse = ""))
  stopifnot(is.raw(x))
  .Call(C_zux_tree_info, x, list(...))
}
