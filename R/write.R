#' Serialize XML
#'
#' Writes a node and its subtree back to XML text.
#'
#' Element order, attribute order, text order, mixed-content interleaving and
#' namespace semantics are preserved. The original *formatting* is not: parsing
#' does not retain quote style, whitespace between attributes, CDATA
#' boundaries, entity spelling, or whether an empty element was written as
#' `<a/>` or `<a></a>`. `zuxml` is not a lossless source editor.
#'
#' @param x A `zuxml_document`, node, or nodeset.
#' @param path File to write to.
#' @param declaration Prepend an XML declaration.
#' @param ... Ignored.
#' @return `xml_serialize()` returns a character vector, one element per node.
#'   `xml_write()` returns `path` invisibly.
#' @export
#' @examples
#' doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
#' xml_serialize(doc)
xml_serialize <- function(x, declaration = FALSE) {
  s <- .Call(C_zux_serialize, zux_ptr(x), zux_ids(x))
  if (isTRUE(declaration)) {
    enc <- tryCatch(xml_encoding(x), error = function(e) NA_character_)
    s <- paste0(sprintf('<?xml version="1.0" encoding="%s"?>',
                        if (is.na(enc)) "UTF-8" else enc), s)
  }
  s
}

#' @rdname xml_serialize
#' @export
xml_write <- function(x, path, declaration = TRUE) {
  txt <- xml_serialize(x, declaration = declaration)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste(txt, collapse = "")), con)
  invisible(path)
}

#' @rdname xml_serialize
#' @export
as.character.zuxml_nodeset <- function(x, ...) xml_serialize(x)

#' @rdname xml_serialize
#' @export
as.character.zuxml_document <- function(x, ...) xml_serialize(x)
