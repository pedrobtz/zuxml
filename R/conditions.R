# The condition hierarchy of design section 12. C returns a status and never
# raises a classed error itself; R turns the status into a condition here.
#
# The class is the contract: callers branch on it and on the fields below,
# never on the message, which may be reworded.

#' Conditions raised by zuxml
#'
#' Every error zuxml raises carries a condition class, so that it can be
#' caught by kind rather than by matching the message, which is not stable.
#' Every class below is a subclass of `zuxml_error`.
#'
#' \describe{
#'   \item{`zuxml_invalid_argument`}{An argument was not usable: an `x` that
#'     is not a single string or a raw vector, an `encoding` other than UTF-8
#'     for character input, a limit that is not a positive whole number, or a
#'     flag that is not `TRUE` or `FALSE`.}
#'   \item{`zuxml_parse_error`}{The input is not well-formed XML, ends too
#'     early, or references an undefined entity.}
#'   \item{`zuxml_encoding_error`}{The input is not valid in its encoding, or
#'     names an encoding that neither Expat nor [iconv()] can read.}
#'   \item{`zuxml_doctype_error`}{The document has a `DOCTYPE` declaration
#'     and `allow_doctype` is `FALSE`, or it has an internal subset, which is
#'     refused either way.}
#'   \item{`zuxml_limit_error`}{A resource limit was reached. The subclasses
#'     `zuxml_depth_limit`, `zuxml_node_limit`, `zuxml_attr_limit`,
#'     `zuxml_text_limit` and `zuxml_memory_limit` name which one.
#'     [xml_serialize()] raises the parent class alone when a node's text is
#'     longer than an R string can hold.}
#'   \item{`zuxml_memory_error`}{An allocation failed.}
#'   \item{`zuxml_cancelled`}{A handler stopped the parse. It can only happen
#'     through the C API, where a downstream package supplies the handler;
#'     no exported R function raises it.}
#' }
#'
#' A condition raised by a parse carries `line`, `column` and `byte_offset`,
#' the position where the parser stopped; `status`, the C status's enumerator
#' name, such as `"ZUX_ERR_DEPTH_LIMIT"`; and `expat_code`, Expat's own error
#' code, which is `NA` when the failure was not Expat's. It is there for
#' diagnostics: do not branch on it. A limit error also carries `limit`, the
#' argument's name, such as `"max_depth"`, and `limit_value`, the value it was
#' given. A `zuxml_invalid_argument` condition carries `arg`, the name of the
#' argument at fault.
#'
#' @name zuxml-conditions
#' @examples
#' tryCatch(
#'   xml_parse("<a><b></a>"),
#'   zuxml_parse_error = function(e) c(line = e$line, column = e$column)
#' )
#' tryCatch(
#'   xml_parse("<a><b/></a>", max_depth = 1),
#'   zuxml_limit_error = function(e) e$limit
#' )
NULL

zuxml_abort <- function(class, message, ..., call = sys.call(-1L)) {
  stop(structure(
    class = c(class, "zuxml_error", "error", "condition"),
    list(message = message, call = call, ...)))
}

zux_invalid_argument <- function(arg, message, call = sys.call(-1L)) {
  zuxml_abort("zuxml_invalid_argument", paste0("zuxml: ", message),
              arg = arg, call = call)
}

# The status-to-class map, keyed by the C enumerator's name. C returns the
# name alongside the English status string, so this map does not depend on
# either the enum's numbering or its wording. ZUX_OK and ZUX_DONE are absent:
# neither is a failure. Anything unmapped, ZUX_ERR_INTERNAL included, is a
# bare zuxml_error: still catchable, but not mistaken for a parse error.
zux_status_class <- list(
  ZUX_ERR_INVALID_ARGUMENT = "zuxml_invalid_argument",
  ZUX_ERR_INVALID_XML      = "zuxml_parse_error",
  ZUX_ERR_UNDEFINED_ENTITY = "zuxml_parse_error",
  ZUX_ERR_ENCODING         = "zuxml_encoding_error",
  ZUX_ERR_DOCTYPE          = "zuxml_doctype_error",
  ZUX_ERR_DEPTH_LIMIT      = c("zuxml_depth_limit",  "zuxml_limit_error"),
  ZUX_ERR_NODE_LIMIT       = c("zuxml_node_limit",   "zuxml_limit_error"),
  ZUX_ERR_ATTR_LIMIT       = c("zuxml_attr_limit",   "zuxml_limit_error"),
  ZUX_ERR_TEXT_LIMIT       = c("zuxml_text_limit",   "zuxml_limit_error"),
  ZUX_ERR_MEMORY_LIMIT     = c("zuxml_memory_limit", "zuxml_limit_error"),
  ZUX_ERR_MEMORY           = "zuxml_memory_error",
  ZUX_ERR_CANCELLED        = "zuxml_cancelled"
)

# Which xml_parse() argument each limit status reports on.
zux_status_limit <- c(
  ZUX_ERR_DEPTH_LIMIT  = "max_depth",
  ZUX_ERR_NODE_LIMIT   = "max_nodes",
  ZUX_ERR_ATTR_LIMIT   = "max_attrs",
  ZUX_ERR_TEXT_LIMIT   = "max_text",
  ZUX_ERR_MEMORY_LIMIT = "max_memory"
)

zux_condition_class <- function(name) {
  zux_status_class[[name]] %||% character()
}

# Raise the condition for a failed C_zux_parse() result. `limits` holds the
# limit arguments as the caller gave them, for the limit error's metadata.
zux_abort <- function(res, limits = list()) {
  cls <- zux_condition_class(res$name)
  msg <- if (identical(res$name, "ZUX_ERR_INVALID_XML") ||
             identical(res$name, "ZUX_ERR_UNDEFINED_ENTITY")) {
    sprintf("XML parse error at line %.0f, column %.0f: %s",
            res$line, res$column, res$message)
  } else if (res$line > 0) {
    sprintf("%s (at line %.0f, column %.0f)", res$message, res$line, res$column)
  } else {
    res$message
  }
  fields <- list(line = res$line, column = res$column,
                 byte_offset = res$byte_offset, status = res$name,
                 expat_code = res$expat_code)
  limit <- unname(zux_status_limit[res$name])
  if (!is.na(limit)) {
    fields$limit <- limit
    fields$limit_value <- limits[[limit]]
  }
  do.call(zuxml_abort, c(list(cls, msg), fields, list(call = NULL)))
}
