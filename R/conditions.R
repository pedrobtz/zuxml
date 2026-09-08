# Map a project status string onto the condition hierarchy in design section 12.
zux_condition_class <- function(status) {
  switch(status,
    "invalid XML"                                = c("zuxml_parse_error"),
    "undefined entity reference"                 = c("zuxml_parse_error"),
    "invalid or unsupported encoding"            = c("zuxml_encoding_error"),
    "document type declaration is not allowed"   = c("zuxml_doctype_error"),
    "document type declaration with an internal subset is not allowed" =
      c("zuxml_doctype_error"),
    "maximum nesting depth exceeded"   = c("zuxml_depth_limit", "zuxml_limit_error"),
    "maximum node count exceeded"      = c("zuxml_node_limit",  "zuxml_limit_error"),
    "maximum attribute count exceeded" = c("zuxml_attr_limit",  "zuxml_limit_error"),
    "maximum text size exceeded"       = c("zuxml_text_limit",  "zuxml_limit_error"),
    "memory limit exceeded"            = c("zuxml_memory_limit","zuxml_limit_error"),
    "out of memory"                    = c("zuxml_memory_error"),
    "cancelled by handler"             = c("zuxml_cancelled"),
    c("zuxml_parse_error")
  )
}

zux_abort <- function(res) {
  cls <- c(zux_condition_class(res$status), "zuxml_error", "error", "condition")
  msg <- if (identical(res$status, "invalid XML") ||
             identical(res$status, "undefined entity reference")) {
    sprintf("XML parse error at line %.0f, column %.0f: %s",
            res$line, res$column, res$message)
  } else if (res$line > 0) {
    sprintf("%s (at line %.0f, column %.0f)", res$message, res$line, res$column)
  } else {
    res$message
  }
  stop(structure(
    class = cls,
    list(message = msg, call = NULL,
         line = res$line, column = res$column,
         byte_offset = res$byte_offset, status = res$status)))
}
