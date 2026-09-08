#' @export
length.zuxml_nodeset <- function(x) length(unclass(x))

#' @export
`[.zuxml_nodeset` <- function(x, i) new_nodeset(unclass(x)[i], zux_doc_of(x))

#' @export
`[[.zuxml_nodeset` <- function(x, i) new_nodeset(unclass(x)[[i]], zux_doc_of(x))

#' @export
c.zuxml_nodeset <- function(...) {
  parts <- list(...)
  docs <- lapply(parts, zux_doc_of)
  ptrs <- vapply(docs, function(d) format(d$ptr), character(1))
  if (length(unique(ptrs)) > 1L)
    stop("zuxml: cannot combine nodes from different documents")
  new_nodeset(unlist(lapply(parts, unclass)), docs[[1L]])
}

#' @export
rev.zuxml_nodeset <- function(x) new_nodeset(rev(unclass(x)), zux_doc_of(x))

#' @export
as.integer.zuxml_nodeset <- function(x, ...) unclass(x)

#' @export
print.zuxml_nodeset <- function(x, n = 10L, ...) {
  len <- length(x)
  if (len == 1L) {
    kind <- xml_type(x)
    cat(sprintf("<zuxml_node %s>\n", kind))
    if (kind %in% c("element", "pi")) {
      uri <- xml_ns(x)
      cat(if (is.na(uri)) xml_name(x) else sprintf("{%s}%s", uri, xml_local(x)),
          "\n")
      cat(sprintf("attributes: %d   children: %d\n",
                  length(xml_attrs(x)[[1L]]), length(xml_children(x))))
    } else {
      txt <- xml_text(x)
      cat(sprintf("%s\n", substr(txt, 1L, 60L)))
    }
    return(invisible(x))
  }
  cat(sprintf("<zuxml_nodeset[%d]>\n", len))
  if (len > 0L) {
    show <- seq_len(min(len, n))
    nm <- xml_name(x[show])
    ty <- xml_type(x[show])
    cat(paste0("[", show, "] ",
               ifelse(is.na(nm), paste0("<", ty, ">"), paste0("<", nm, ">")),
               collapse = " "), "\n")
    if (len > n) cat(sprintf("... and %d more\n", len - n))
  }
  invisible(x)
}

#' @export
print.zuxml_document <- function(x, ...) {
  m <- .Call(C_zux_doc_meta, x$ptr)
  r <- xml_root(x)
  cat("<zuxml_document>\n")
  if (length(r)) {
    uri <- xml_ns(r)
    cat(sprintf("root:     %s\n",
                if (is.na(uri)) xml_name(r)
                else sprintf("{%s}%s", uri, xml_local(r))))
  }
  cat(sprintf("nodes:    %.0f   attributes: %.0f\n", m$n_nodes, m$n_attrs))
  cat(sprintf("memory:   %s\n", format(structure(m$bytes, class = "object_size"),
                                       units = "auto")))
  cat(sprintf("encoding: %s\n", if (is.na(m$encoding)) "not declared" else m$encoding))
  invisible(x)
}

#' @export
format.zuxml_nodeset <- function(x, ...) {
  nm <- xml_name(x)
  ifelse(is.na(nm), paste0("<", xml_type(x), ">"), paste0("<", nm, ">"))
}
