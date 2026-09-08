# Encodings Expat handles natively. Anything else is transcoded to UTF-8 with
# iconv() before parsing, and the declaration is then overridden so the (now
# stale) encoding attribute cannot mislead the parser. Design section 10.
zux_native_encodings <- c("UTF-8", "UTF8", "UTF-16", "UTF-16LE", "UTF-16BE",
                          "ISO-8859-1", "LATIN1", "US-ASCII", "ASCII")

#' Parse an XML document
#'
#' `xml_parse()` parses XML held in memory; `xml_read()` parses a file.
#'
#' Parsing is strict and secure by default: document type declarations are
#' rejected, general entities are not compiled in at all, and the limits below
#' bound what a hostile document can cost. See `vignette("security")` once
#' written, or `zuxml_info()` for the compiled-in policy.
#'
#' @param x A character string or a raw vector containing XML.
#' @param path Path to a file.
#' @param encoding Encoding of the input. `NULL` (default) lets the parser
#'   detect it from a byte-order mark or the XML declaration. An explicit
#'   value overrides the declaration, which is what an HTTP `charset` should
#'   do. Encodings that Expat cannot handle natively are transcoded with
#'   [iconv()].
#' @param comments,pis Retain comment and processing-instruction nodes.
#' @param allow_doctype Accept a `DOCTYPE` declaration. An internal subset is
#'   rejected even when this is `TRUE`, because it is the only place a
#'   document can declare entities.
#' @param max_depth,max_nodes,max_attrs,max_text,max_memory Resource limits.
#'   Each has its own error condition.
#' @param ... Passed on to `xml_parse()`.
#' @return A `zuxml_document`.
#' @export
#' @examples
#' doc <- xml_parse("<catalog><book id='1'><title>XML</title></book></catalog>")
#' xml_text(xml_find(doc, "title"))
xml_parse <- function(x, encoding = NULL, comments = TRUE, pis = TRUE,
                      allow_doctype = FALSE, max_depth = 256L,
                      max_nodes = 1e7, max_attrs = 4096L,
                      max_text = 64 * 1024^2, max_memory = 1024 * 1024^2) {
  if (is.character(x)) {
    if (anyNA(x)) stop("zuxml: `x` must not contain NA")
    x <- charToRaw(paste(x, collapse = ""))
    encoding <- encoding %||% "UTF-8"
  }
  if (!is.raw(x)) stop("zuxml: `x` must be a character string or a raw vector")

  if (!is.null(encoding) && !toupper(encoding) %in% toupper(zux_native_encodings)) {
    conv <- tryCatch(
      iconv(list(x), from = encoding, to = "UTF-8", toRaw = TRUE)[[1L]],
      error = function(e) NULL)
    if (is.null(conv)) {
      stop(structure(class = c("zuxml_encoding_error", "zuxml_error",
                               "error", "condition"),
        list(message = sprintf("zuxml: could not convert input from '%s' to UTF-8",
                               encoding), call = NULL)))
    }
    x <- conv
    encoding <- "UTF-8"
  }

  res <- .Call(C_zux_parse, x, list(
    encoding = encoding, comments = comments, pis = pis,
    allow_doctype = allow_doctype, max_depth = max_depth,
    max_nodes = max_nodes, max_attrs = max_attrs,
    max_text = max_text, max_memory = max_memory))

  if (!identical(res$status, "ok") || is.null(res$doc)) zux_abort(res)
  structure(list(ptr = res$doc), class = "zuxml_document")
}

#' @rdname xml_parse
#' @export
xml_read <- function(path, encoding = NULL, ...) {
  if (!file.exists(path)) stop(sprintf("zuxml: no such file: %s", path))
  n <- file.info(path)$size
  xml_parse(readBin(path, "raw", n = n), encoding = encoding, ...)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
