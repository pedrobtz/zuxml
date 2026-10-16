# Documents and readers shared by the R-API suites (test-api.R,
# test-find-first.R, test-extract.R, test-read.R, test-interrupt.R).

ATOM <- "http://www.w3.org/2005/Atom"

atom_doc <- function() xml_parse(sprintf('<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="%s" xmlns:x="urn:extra">
  <title>Example Feed</title>
  <entry x:rank="1"><title>First</title><link href="/1"/></entry>
  <entry x:rank="2"><title>Second</title><link href="/2"/></entry>
</feed>', ATOM))

books_doc <- function() xml_parse(
  "<r>
     <book id='a'><title>A</title><price>1</price></book>
     <book id='b'><price>2</price></book>
     <book id='c'><section><title>C</title></section><title>late</title></book>
   </r>")

tbl <- function(xml, ...) xml_table(xml_parse(xml), ...)[[1]]
lst <- function(xml, ...) xml_list(xml_parse(xml), ...)[[1]]

# About mib MiB of repeated records, for test-interrupt.R.
items_doc <- function(mib) {
  item <- "<item id='1'><name>widget</name><price>9.99</price></item>"
  n <- ceiling(mib * 1024^2 / nchar(item))
  paste0("<items>", strrep(item, n), "</items>")
}

# rawConnection() is born open, so xml_read() leaves it open; close it here
# rather than let the GC warn about an unused connection.
read_raw <- function(bytes, ...) {
  con <- rawConnection(bytes)
  on.exit(close(con), add = TRUE)
  xml_read(con, ...)
}
