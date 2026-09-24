# Tables and lists out of XML documents (#57). XML only: these read the tree a
# document actually has, and infer nothing the way an HTML parser would -- a
# table without <tbody> has exactly the rows it contains. Elements are matched
# by local name, in any namespace unless `ns` says otherwise, so XHTML works
# with or without its namespace declaration.

#' Extract tables and lists
#'
#' `xml_table()` turns `table` elements into data frames, and `xml_list()`
#' turns `ul` and `ol` elements into R lists. Both read well-formed XML, such
#' as XHTML or a table embedded in another XML format. They do not apply HTML
#' parsing rules: a `table` without `tbody` has exactly the rows it contains.
#'
#' **Tables.** The rows are the `tr` elements that are children of the
#' `table`, or of its `thead`, `tbody` or `tfoot`, in document order. A table
#' nested inside a cell is not descended into; extract it separately. The
#' cells are the `td` and `th` elements of a row, and a cell's value is its
#' text, as [xml_text()] gives it. Every column is character: convert types
#' yourself, for example with `type.convert(df, as.is = TRUE)`.
#'
#' `colspan` and `rowspan` are expanded by repeating the cell's value. A span
#' that is not a positive whole number counts as 1, and spans are capped at
#' HTML's own limits, 1000 columns and 65534 rows. A row span never adds rows
#' past the end of the table. Short rows are padded with `NA`.
#'
#' Expansion can make a small document produce a very large table, so the
#' expanded size of each table is bounded by `max_cells`, and exceeding it is
#' a `zuxml_limit_error`.
#'
#' **Lists.** Each `li` child of a `ul` or `ol` becomes one item. An item is
#' its text as a string or, when the `li` has `ul` or `ol` children, a list
#' with two elements: `text`, the item's own text without the nested lists',
#' and `items`, the items of its nested lists, extracted the same way. Only
#' direct `ul` and `ol` children of an `li` count as nested lists. Comments
#' and processing instructions inside an item are ignored.
#'
#' @param x A node or nodeset of `table` elements for `xml_table()`, or of
#'   `ul` and `ol` elements for `xml_list()`. A document stands for its root.
#' @param header Use the first row as column names. `NA`, the default, does so
#'   when every cell of the first row is a `th`.
#' @param trim Trim leading and trailing whitespace from each value.
#' @param ns Namespace URI of the table or list elements, `NA` for none,
#'   `NULL` for any.
#' @param max_cells The most cells one table may expand to. A positive whole
#'   number, or `Inf`.
#' @return A list with one element per node in `x`: a data frame for
#'   `xml_table()`, a list of items for `xml_list()`.
#' @seealso [xml_find()] to locate the tables or lists in a document, and
#'   [zuxml-conditions] for the errors these raise.
#' @export
#' @examples
#' doc <- xml_parse("<table>
#'   <tr><th>fruit</th><th>price</th></tr>
#'   <tr><td>apple</td><td>1.20</td></tr>
#'   <tr><td>pear</td><td>0.90</td></tr>
#' </table>")
#' xml_table(xml_root(doc))[[1]]
#'
#' doc <- xml_parse("<ul>
#'   <li>fruit<ul><li>apple</li><li>pear</li></ul></li>
#'   <li>bread</li>
#' </ul>")
#' str(xml_list(xml_root(doc))[[1]])
xml_table <- function(x, header = NA, trim = TRUE, ns = NULL,
                      max_cells = 1e7) {
  if (!is.logical(header) || length(header) != 1L)
    zux_invalid_argument("header", "`header` must be TRUE, FALSE or NA")
  trim <- zux_flag(trim, "trim")
  max_cells <- zux_check_limit(max_cells, "max_cells", 2^53)
  nodes <- zux_extract_nodes(x, "table", ns)
  lapply(seq_along(nodes), function(i)
    zux_table(nodes[i], header, trim, ns, max_cells))
}

#' @rdname xml_table
#' @export
xml_list <- function(x, trim = TRUE, ns = NULL) {
  trim <- zux_flag(trim, "trim")
  nodes <- zux_extract_nodes(x, c("ul", "ol"), ns)
  lapply(seq_along(nodes), function(i) zux_list_items(nodes[i], trim, ns))
}

# The nodes of `x`, each checked to be an element with one of `names`.
zux_extract_nodes <- function(x, names, ns, call = sys.call(-1L)) {
  nodes <- if (inherits(x, "zuxml_document")) xml_root(x) else x
  zux_doc_of(nodes)
  ok <- xml_type(nodes) == "element" & xml_local(nodes) %in% names
  if (!is.null(ns)) {
    uri <- xml_ns(nodes)
    ok <- ok & (if (is.na(ns)) is.na(uri) else !is.na(uri) & uri == ns)
  }
  if (!all(ok))
    zuxml_abort("zuxml_invalid_argument", sprintf(
      "zuxml: `x` must be %s elements%s", paste0("<", names, ">", collapse = " or "),
      if (is.null(ns)) "" else " in the namespace given by `ns`"),
      arg = "x", call = call)
  nodes
}

# Element children of `x` whose local name is in `names`, in document order.
zux_named_children <- function(x, names, ns) {
  kids <- xml_elements(x, ns = ns)
  kids[xml_local(kids) %in% names]
}

# A span attribute as a count: a positive whole number, capped; else 1.
zux_span <- function(v, cap) {
  n <- suppressWarnings(as.numeric(v))
  n[is.na(n) | n < 1 | n != trunc(n)] <- 1
  as.integer(pmin(n, cap))
}

zux_table <- function(tbl, header, trim, ns, max_cells) {
  kids <- zux_named_children(tbl, c("tr", "thead", "tbody", "tfoot"), ns)
  row_ids <- lapply(seq_along(kids), function(i) {
    k <- kids[i]
    as.integer(if (xml_local(k) == "tr") k else zux_named_children(k, "tr", ns))
  })
  rows <- new_nodeset(unlist(row_ids), zux_doc_of(tbl))

  # Row spans carry a value down a column: carry_n[j] more rows take
  # carry_v[j]. Each cell starts at the first column no carried value holds,
  # and fills its whole column span with one vector assignment. Work per row
  # is proportional to its expanded width, which max_cells bounds, never to
  # the span values themselves.
  carry_n <- integer()
  carry_v <- character()
  grid <- vector("list", length(rows))
  cells_total <- 0

  # Every cell of the table in one pass, then split by row: each accessor is
  # one vectorized call over the whole table rather than one per row.
  all_cells <- zux_named_children(rows, c("td", "th"), ns)
  row_of <- match(as.integer(xml_parent(all_cells)), as.integer(rows))
  all_text <- xml_text(all_cells, trim = trim)
  all_th <- xml_local(all_cells) == "th"
  all_colspan <- zux_span(xml_attr(all_cells, "colspan", ns = NA), 1000)
  all_rowspan <- zux_span(xml_attr(all_cells, "rowspan", ns = NA), 65534)
  by_row <- split(seq_along(all_cells), factor(row_of, levels = seq_along(rows)))
  first_row_th <- length(rows) > 0L && length(by_row[[1L]]) > 0L &&
    all(all_th[by_row[[1L]]])

  for (r in seq_along(rows)) {
    i <- by_row[[r]]
    text <- all_text[i]
    colspan <- all_colspan[i]
    rowspan <- all_rowspan[i]

    # An upper bound: every spanned column, plus every column still carried.
    width <- max(length(carry_n), sum(colspan) + sum(carry_n > 0L))
    cells_total <- cells_total + width
    if (cells_total > max_cells)
      zuxml_abort("zuxml_limit_error", sprintf(
        "zuxml: table expands to more than %s cells; raise `max_cells` if that is expected",
        format(max_cells, scientific = FALSE)),
        limit = "max_cells", limit_value = max_cells, call = NULL)

    length(carry_n) <- width
    carry_n[is.na(carry_n)] <- 0L
    length(carry_v) <- width
    out <- rep(NA_character_, width)
    placed <- logical(width)
    new_n <- rep(NA_integer_, width)
    new_v <- rep(NA_character_, width)
    free <- which(carry_n == 0L)
    col <- 1L
    for (k in seq_along(i)) {
      start <- free[findInterval(col - 1L, free) + 1L]
      idx <- start + seq_len(colspan[k]) - 1L
      # A column span running into a column a row span still holds is an
      # overlap, an error in the HTML table model. The new cell wins.
      out[idx] <- text[k]
      placed[idx] <- TRUE
      if (rowspan[k] > 1L) {
        new_n[idx] <- rowspan[k] - 1L
        new_v[idx] <- text[k]
      }
      col <- start + colspan[k]
    }
    carried <- which(carry_n > 0L & !placed)
    out[carried] <- carry_v[carried]
    # Every carried column loses this row, whether it was shown or overlapped.
    carry_n <- pmax(carry_n - 1L, 0L)
    fresh <- !is.na(new_n)
    carry_n[fresh] <- new_n[fresh]
    carry_v[fresh] <- new_v[fresh]
    # `width` is an upper bound; keep only the columns this row reached.
    grid[[r]] <- out[seq_len(max(0L, which(placed), carried))]
  }

  ncol <- max(0L, lengths(grid))
  grid <- lapply(grid, function(v) { length(v) <- ncol; v })
  use_header <- length(grid) > 0L &&
    (if (is.na(header)) first_row_th else header)
  nms <- if (use_header) grid[[1L]] else rep(NA_character_, ncol)
  if (use_header) grid <- grid[-1L]
  blank <- is.na(nms) | !nzchar(nms)
  nms[blank] <- paste0("X", seq_len(ncol))[blank]
  nms <- make.unique(nms)

  m <- matrix(unlist(grid) %||% character(), nrow = length(grid), ncol = ncol,
              byrow = TRUE)
  cols <- lapply(seq_len(ncol), function(j) m[, j])
  structure(cols, names = nms, class = "data.frame",
            row.names = .set_row_names(length(grid)))
}

# The items of one <ul> or <ol>. Recursion depth is the list nesting depth,
# which the parse's max_depth bounds.
zux_list_items <- function(lst, trim, ns) {
  lis <- zux_named_children(lst, "li", ns)
  lapply(seq_along(lis), function(i) {
    ch <- xml_children(lis[i])
    type <- xml_type(ch)
    local <- xml_local(ch)
    nested <- type == "element" & local %in% c("ul", "ol")
    if (!is.null(ns) && any(nested)) {
      uri <- xml_ns(ch)
      nested <- nested & (if (is.na(ns)) is.na(uri) else !is.na(uri) & uri == ns)
    }
    keep <- !nested & type %in% c("element", "text")
    text <- paste(xml_text(ch[which(keep)]), collapse = "")
    if (trim) text <- trimws(text)
    if (!any(nested)) return(text)
    sub <- ch[which(nested)]
    list(text = text,
         items = do.call(c, lapply(seq_along(sub), function(j)
           zux_list_items(sub[j], trim, ns))))
  })
}
