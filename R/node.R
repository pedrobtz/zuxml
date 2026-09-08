# A node and a nodeset are the same object at different lengths: an integer
# vector of node ids carrying the document as an attribute. R's GC traces
# attributes, so the document stays reachable for free -- no protection list,
# no reference counting. Design section 6.

new_nodeset <- function(ids, doc) {
  structure(as.integer(ids), class = "zuxml_nodeset", doc = doc)
}

zux_doc_of <- function(x) {
  d <- attr(x, "doc", exact = TRUE)
  if (is.null(d)) stop("zuxml: not a node or nodeset")
  d
}

zux_ptr <- function(x) {
  if (inherits(x, "zuxml_document")) return(x$ptr)
  zux_doc_of(x)$ptr
}

zux_ids <- function(x) {
  if (inherits(x, "zuxml_document")) return(.Call(C_zux_root, x$ptr))
  as.integer(unclass(x))
}

zux_as_doc <- function(x) {
  if (inherits(x, "zuxml_document")) x else zux_doc_of(x)
}

#' Navigate an XML document
#'
#' Every accessor is vectorized: given a nodeset of length `n` it returns a
#' result of length `n`, and the traversal functions return a single flat
#' nodeset.
#'
#' Filtering is uniform. `name` matches the *local* name. `ns = NULL` matches
#' any namespace, `ns = NA` matches only nodes in no namespace, and a string
#' matches that namespace URI. Matching never considers the prefix: two
#' prefixes bound to one URI are the same name.
#'
#' @param x A `zuxml_document`, node, or nodeset.
#' @param name Local name to match, or `NULL` for any.
#' @param ns Namespace URI, `NA` for none, `NULL` for any.
#' @return `xml_root()`, `xml_parent()`, `xml_children()`, `xml_elements()`
#'   and `xml_find()` return a nodeset.
#' @name xml_navigate
#' @examples
#' doc <- xml_parse("<r><a><b>1</b></a><b>2</b></r>")
#' xml_name(xml_children(xml_root(doc)))
#' xml_text(xml_find(doc, "b"))
NULL

#' @rdname xml_navigate
#' @export
xml_root <- function(x) {
  d <- zux_as_doc(x)
  new_nodeset(.Call(C_zux_root, d$ptr), d)
}

#' @rdname xml_navigate
#' @export
xml_parent <- function(x) {
  d <- zux_as_doc(x)
  ids <- .Call(C_zux_parent, d$ptr, zux_ids(x))
  new_nodeset(ids[!is.na(ids)], d)
}

#' @rdname xml_navigate
#' @export
xml_children <- function(x) {
  d <- zux_as_doc(x)
  new_nodeset(.Call(C_zux_select, d$ptr, zux_ids(x), 0L, NULL, NULL), d)
}

#' @rdname xml_navigate
#' @export
xml_elements <- function(x, name = NULL, ns = NULL) {
  d <- zux_as_doc(x)
  new_nodeset(.Call(C_zux_select, d$ptr, zux_ids(x), 1L,
                    zux_chr(name), zux_chr(ns)), d)
}

#' @rdname xml_navigate
#' @export
xml_find <- function(x, name = NULL, ns = NULL) {
  d <- zux_as_doc(x)
  new_nodeset(.Call(C_zux_select, d$ptr, zux_ids(x), 2L,
                    zux_chr(name), zux_chr(ns)), d)
}

zux_chr <- function(v) {
  if (is.null(v)) return(NULL)
  if (length(v) != 1L) stop("zuxml: `name` and `ns` must be length 1 or NULL")
  as.character(v)
}

#' Read properties of XML nodes
#'
#' All of these are vectorized over a nodeset.
#'
#' @param x A node or nodeset.
#' @param name Attribute local name.
#' @param ns Namespace URI, `NA` for none, `NULL` for any.
#' @param default Value for nodes lacking the attribute.
#' @param recursive Concatenate text of all descendants (default) or only
#'   direct text children.
#' @param trim Trim leading and trailing whitespace from the result.
#' @return A character vector, except `xml_attrs()` which returns a list of
#'   named character vectors.
#' @name xml_properties
#' @examples
#' doc <- xml_parse("<p>Hello <em>XML</em> world</p>")
#' xml_text(xml_root(doc))
#' xml_text(xml_root(doc), recursive = FALSE)
NULL

#' @rdname xml_properties
#' @export
xml_name <- function(x) .Call(C_zux_node_info, zux_ptr(x), zux_ids(x), "qname")

#' @rdname xml_properties
#' @export
xml_local <- function(x) .Call(C_zux_node_info, zux_ptr(x), zux_ids(x), "local")

#' @rdname xml_properties
#' @export
xml_ns <- function(x) .Call(C_zux_node_info, zux_ptr(x), zux_ids(x), "uri")

#' @rdname xml_properties
#' @export
xml_prefix <- function(x) .Call(C_zux_node_info, zux_ptr(x), zux_ids(x), "prefix")

#' @rdname xml_properties
#' @export
xml_type <- function(x) .Call(C_zux_node_info, zux_ptr(x), zux_ids(x), "kind")

#' @rdname xml_properties
#' @export
xml_attrs <- function(x) .Call(C_zux_attrs, zux_ptr(x), zux_ids(x))

#' @rdname xml_properties
#' @export
xml_attr <- function(x, name, ns = NULL, default = NA_character_) {
  v <- .Call(C_zux_attr, zux_ptr(x), zux_ids(x), zux_chr(name), zux_chr(ns))
  v[is.na(v)] <- default
  v
}

#' @rdname xml_properties
#' @export
xml_text <- function(x, recursive = TRUE, trim = FALSE) {
  v <- .Call(C_zux_text, zux_ptr(x), zux_ids(x), recursive)
  if (isTRUE(trim)) trimws(v) else v
}

#' Document metadata
#' @param x A `zuxml_document`.
#' @return A length-1 vector.
#' @name xml_metadata
#' @examples
#' xml_encoding(xml_parse('<?xml version="1.0" encoding="UTF-8"?><a/>'))
NULL

#' @rdname xml_metadata
#' @export
xml_version <- function(x) .Call(C_zux_doc_meta, zux_ptr(x))$version

#' @rdname xml_metadata
#' @export
xml_encoding <- function(x) .Call(C_zux_doc_meta, zux_ptr(x))$encoding

#' @rdname xml_metadata
#' @export
xml_standalone <- function(x) .Call(C_zux_doc_meta, zux_ptr(x))$standalone
