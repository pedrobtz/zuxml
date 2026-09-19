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
#' @details Each element of the result is escaped for its own node. Two
#'   adjacent text nodes -- which is what `comments = FALSE` or `pis = FALSE`
#'   leaves behind where a dropped node used to sit -- are therefore escaped
#'   independently, so concatenating the pieces yourself can produce content
#'   a parser will reject. Serialize the common parent instead, which escapes
#'   across the whole subtree.
#' @export
#' @examples
#' doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
#' xml_serialize(doc)
xml_serialize <- function(x, declaration = FALSE) {
  declaration <- zux_flag(declaration, "declaration")
  s <- .Call(C_zux_serialize, zux_ptr(x), zux_ids(x))
  if (declaration) {
    # One declaration belongs to one document. paste0() is vectorized, so a
    # nodeset would otherwise get a declaration prepended to every element
    # and xml_write() would emit a file that is not well-formed XML.
    if (length(s) != 1L)
      stop("zuxml: `declaration = TRUE` needs a single node, not a nodeset ",
           "of length ", length(s))
    # Always UTF-8, whatever the source document declared: that is what the
    # serializer emits. Echoing the original encoding produced a declaration
    # that contradicted its own bytes, so a written file did not round-trip.
    s <- paste0('<?xml version="1.0" encoding="UTF-8"?>', s)
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
