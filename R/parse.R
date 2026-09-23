# Encodings Expat handles natively, keyed by the upper-cased spelling a
# caller may use and valued by the name Expat knows. The aliases must be
# translated: Expat recognises only its own spelling, so "latin1" passed
# through as it was failed as an unknown encoding. Anything else is
# transcoded to UTF-8 with iconv() before parsing, and the declaration is
# then overridden so the (now stale) encoding attribute cannot mislead the
# parser. Design section 10.
zux_native_encodings <- c(
  "UTF-8" = "UTF-8", "UTF8" = "UTF-8",
  "UTF-16" = "UTF-16", "UTF-16LE" = "UTF-16LE", "UTF-16BE" = "UTF-16BE",
  "ISO-8859-1" = "ISO-8859-1", "LATIN1" = "ISO-8859-1",
  "US-ASCII" = "US-ASCII", "ASCII" = "US-ASCII")

#' Parse an XML document
#'
#' `xml_parse()` parses XML held in memory; `xml_read()` parses a file.
#'
#' Parsing is strict and secure by default: document type declarations are
#' rejected, general entities are not compiled in at all, and the limits below
#' bound what a hostile document can cost. See `vignette("security")` for the
#' threat model, or `zuxml_info()` for the compiled-in policy.
#'
#' @param x A single string, or a raw vector, containing XML. A character
#'   vector of any other length is an error: to parse lines read with
#'   [readLines()], join them first with `paste(x, collapse = "\n")`.
#' @param path Path to a file.
#' @param encoding Encoding of the input. `NULL` (default) lets the parser
#'   detect it from a byte-order mark or the XML declaration. An explicit
#'   value overrides the declaration, which is what an HTTP `charset` should
#'   do. Encodings that Expat cannot handle natively are transcoded with
#'   [iconv()]. A character `x` is always UTF-8 by the time it is parsed, so
#'   for one, `encoding` must be `NULL` or `"UTF-8"`.
#' @param comments,pis Retain comment and processing-instruction nodes.
#' @param allow_doctype Accept a `DOCTYPE` declaration. An internal subset is
#'   rejected even when this is `TRUE`, because it is the only place a
#'   document can declare entities.
#' @param max_depth,max_nodes,max_attrs,max_text,max_memory Resource limits:
#'   the nesting depth, the number of nodes, the attributes on one element,
#'   the bytes in one text node, and the bytes the document may allocate.
#'   Each must be a single positive whole number, or `Inf` for the largest
#'   value the parser can represent. `max_nodes` is capped at
#'   `.Machine$integer.max`, because node ids are R integers. Each limit has
#'   its own error condition.
#' @param ... Passed on to `xml_parse()`.
#' @return A `zuxml_document`.
#' @seealso [zuxml-conditions] for the errors these raise.
#' @export
#' @examples
#' doc <- xml_parse("<catalog><book id='1'><title>XML</title></book></catalog>")
#' xml_text(xml_find(doc, "title"))
xml_parse <- function(x, encoding = NULL, comments = TRUE, pis = TRUE,
                      allow_doctype = FALSE, max_depth = 256L,
                      max_nodes = 1e7, max_attrs = 4096L,
                      max_text = 64 * 1024^2, max_memory = 1024 * 1024^2) {
  if (!is.null(encoding) &&
      (!is.character(encoding) || length(encoding) != 1L || is.na(encoding)))
    zux_invalid_argument("encoding", "`encoding` must be a single string or NULL")
  if (is.character(x)) {
    # Collapsing silently is what used to happen, with "": it joined the
    # lines of readLines() into one, changing text nodes and reporting every
    # error at line 1. Which separator is right is the caller's to say.
    if (length(x) != 1L)
      zux_invalid_argument("x", sprintf(paste0(
        "`x` must be a single string, not a character vector of length %d; ",
        "join lines with paste(x, collapse = \"\\n\")"), length(x)))
    if (is.na(x)) zux_invalid_argument("x", "`x` must not be NA")
    # A character string has already been decoded: whatever the bytes it came
    # from were, R holds it as text and enc2utf8() yields UTF-8. Another
    # `encoding` would re-decode those UTF-8 bytes as something they are not.
    if (!is.null(encoding) && !toupper(encoding) %in% c("UTF-8", "UTF8"))
      zux_invalid_argument("encoding", sprintf(
        "`encoding = \"%s\"` applies to raw input only; a character `x` is already decoded",
        encoding))
    x <- charToRaw(enc2utf8(x))
    encoding <- "UTF-8"
  }
  if (!is.raw(x))
    zux_invalid_argument("x", "`x` must be a single string or a raw vector")
  comments <- zux_flag(comments, "comments")
  pis <- zux_flag(pis, "pis")
  allow_doctype <- zux_flag(allow_doctype, "allow_doctype")
  limits <- list(
    max_depth  = zux_check_limit(max_depth,  "max_depth",  zux_u32_max),
    max_nodes  = zux_check_limit(max_nodes,  "max_nodes",  .Machine$integer.max),
    max_attrs  = zux_check_limit(max_attrs,  "max_attrs",  zux_u32_max),
    max_text   = zux_check_limit(max_text,   "max_text",   zux_size_max),
    max_memory = zux_check_limit(max_memory, "max_memory", zux_size_max))

  if (!is.null(encoding) && toupper(encoding) %in% names(zux_native_encodings)) {
    encoding <- unname(zux_native_encodings[toupper(encoding)])
  } else if (!is.null(encoding)) {
    conv <- tryCatch(
      iconv(list(x), from = encoding, to = "UTF-8", toRaw = TRUE)[[1L]],
      error = function(e) NULL)
    if (is.null(conv)) {
      zuxml_abort("zuxml_encoding_error",
        sprintf("zuxml: could not convert input from '%s' to UTF-8", encoding),
        call = NULL)
    }
    x <- conv
    encoding <- "UTF-8"
  }

  res <- .Call(C_zux_parse, x, c(list(
    encoding = encoding, comments = comments, pis = pis,
    allow_doctype = allow_doctype), limits))

  if (!identical(res$name, "ZUX_OK") || is.null(res$doc)) zux_abort(res, limits)
  structure(list(ptr = res$doc), class = "zuxml_document")
}

#' @rdname xml_parse
#' @export
xml_read <- function(path, encoding = NULL, ...) {
  if (!is.character(path) || length(path) != 1L || is.na(path))
    zux_invalid_argument("path", "`path` must be a single file path")
  # file.exists() is TRUE for a directory, which would otherwise reach
  # readBin() and surface as a base R warning about a non-regular file.
  if (dir.exists(path))
    zux_invalid_argument("path", sprintf("not a file: %s", path))
  if (!file.exists(path))
    zux_invalid_argument("path", sprintf("no such file: %s", path))
  n <- file.info(path)$size
  xml_parse(readBin(path, "raw", n = n), encoding = encoding, ...)
}

# The largest value each limit's C type holds. Inf asks for it; a finite value
# above it is refused rather than clamped. size_t limits stop at 2^53, the
# largest whole number a double represents exactly, on a 64-bit build.
zux_u32_max <- 2^32 - 1
zux_size_max <- if (.Machine$sizeof.pointer >= 8L) 2^53 else 2^32 - 1

# A resource limit is a security property: one silently replaced by the
# default, or truncated from a fraction, is a limit the caller did not set.
# So anything but a single positive whole number, or Inf, is refused. Inf is
# passed through, and C turns it into its own type's maximum. As zukomp's
# zu_check_limit().
zux_check_limit <- function(x, arg, upper, call = sys.call(-1L)) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x <= 0 ||
      (is.finite(x) && x != trunc(x)))
    zuxml_abort("zuxml_invalid_argument", sprintf(
      "zuxml: `%s` must be a single positive whole number, or Inf for the largest allowed",
      arg), arg = arg, call = call)
  if (is.finite(x) && x > upper)
    zuxml_abort("zuxml_invalid_argument", sprintf(
      "zuxml: `%s` must be at most %s, or Inf for the largest allowed",
      arg, format(upper, scientific = FALSE)), arg = arg, call = call)
  as.double(x)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
