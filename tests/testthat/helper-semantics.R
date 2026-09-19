# A semantic fingerprint of a document, for use as the round-trip oracle.
#
# zux_tree_info()$dump records an attribute COUNT and nothing else, so on its
# own it cannot tell an attribute in a namespace from one in no namespace, nor
# a reordered attribute list, nor a changed value. The corpus-wide round-trip
# property needs an oracle that sees everything the documentation promises is
# preserved, and ignores everything it says is not.
#
# Preserved, so included: document order, node kinds, (namespace, local name)
# of elements, attribute order, and each attribute's (namespace, local name)
# and value, plus text, comment and PI content.
#
# Not preserved, so deliberately excluded: prefixes (two prefixes bound to one
# URI are the same name), quote style, inter-attribute whitespace, CDATA
# boundaries, entity spelling and empty-element spelling.

# Candidate namespace URIs, read out of the source text. An attribute's
# namespace cannot be enumerated through the R API -- xml_attrs() reports a
# qualified name, and the prefix does not determine identity -- so the
# fingerprint resolves each attribute by probing xml_attr(ns = ) against these.
zux_uris <- function(txt) {
  hits <- regmatches(txt, gregexpr('xmlns(:[^=[:space:]]+)?="([^"]*)"', txt))[[1L]]
  uris <- sub('"$', "", sub('^.*="', "", hits))
  unique(uris[nzchar(uris)])
}

zux_fingerprint <- function(doc, uris) {
  # xml_find() returns only elements, so walk xml_children(), which returns
  # every node kind, or text and comments drop out of the comparison.
  walk <- function(n) {
    acc <- n
    kids <- xml_children(n)
    for (i in seq_along(kids)) acc <- c(acc, walk(kids[i]))
    acc
  }

  attr_part <- function(n) {
    locals <- sub("^[^:]*:", "", names(xml_attrs(n)[[1L]]))
    vapply(locals, function(ln) {
      ns <- "<none>"
      val <- xml_attr(n, ln, ns = NA)
      for (u in uris) {
        v <- xml_attr(n, ln, ns = u)
        if (!is.na(v)) { ns <- u; val <- v }
      }
      sprintf("@{%s}%s=%s", ns, ln, val)
    }, character(1), USE.NAMES = FALSE)
  }

  nodes <- walk(xml_root(doc))
  vapply(seq_along(nodes), function(i) {
    n <- nodes[i]
    switch(xml_type(n),
      element = sprintf("E{%s}%s[%s]",
                        if (is.na(xml_ns(n))) "" else xml_ns(n),
                        xml_local(n),
                        paste(attr_part(n), collapse = ",")),
      text    = paste0("T:", xml_text(n)),
      comment = paste0("C:", xml_text(n)),
      pi      = sprintf("P{%s}%s", xml_local(n), xml_text(n)),
      sprintf("?%s", xml_type(n)))
  }, character(1))
}

# The fingerprint of a document parsed from `txt`, under the given options.
zux_semantics <- function(txt, uris, ...) {
  zux_fingerprint(xml_parse(txt, ...), uris)
}
