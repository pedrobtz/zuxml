#' Report the zuxml build configuration
#'
#' Reports the vendored 'Expat' version and the parser policy compiled into
#' this build. Intended for diagnostics and for security audits: in a
#' correctly built `zuxml`, `dtd` and `general_entities` are both `FALSE` and
#' `entropy` names a real operating-system entropy source.
#'
#' @return An object of class `zuxml_info`: a list with elements
#'   `zuxml_version`, `expat_version`, `namespaces`, `dtd`,
#'   `general_entities`, `context_bytes`, `xml_char_bytes`, `byteorder`,
#'   `entropy` and `parser_ok`.
#' @export
#' @examples
#' zuxml_info()
zuxml_info <- function() {
  info <- .Call(C_zuxml_info)
  out <- c(
    list(zuxml_version = unname(getNamespaceVersion("zuxml"))),
    info
  )
  structure(out, class = "zuxml_info")
}

#' @export
print.zuxml_info <- function(x, ...) {
  yn <- function(v) if (isTRUE(v)) "yes" else "no"
  cat(
    sprintf("zuxml %s\n", x$zuxml_version),
    sprintf("Expat:             %s\n", x$expat_version),
    sprintf("Namespaces:        %s\n", yn(x$namespaces)),
    sprintf("DTD:               %s\n", if (isTRUE(x$dtd)) "ENABLED" else "disabled"),
    sprintf("General entities:  %s\n", if (isTRUE(x$general_entities)) "ENABLED" else "disabled"),
    sprintf("External entities: %s\n", "not compiled in"),
    sprintf("Encoding:          UTF-8 internal (XML_Char = %d byte)\n", x$xml_char_bytes),
    sprintf("Byte order:        %s-endian\n", x$byteorder),
    sprintf("Entropy:           %s\n", x$entropy),
    sprintf("Context bytes:     %d\n", x$context_bytes),
    sep = ""
  )
  invisible(x)
}
