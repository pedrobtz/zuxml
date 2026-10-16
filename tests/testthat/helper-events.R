# Thin wrappers over the internal introspection entry points, shared by the
# seam, limits, namespace, security, chunking and tree suites.
#
# Helpers live in helper-*.R, never at the top of a test file: testthat sources
# these before any test runs, whereas devtools::test(shuffle = TRUE) reorders a
# test file's top-level code along with its test_that() blocks (#75).
ev  <- function(...) zuxml:::zux_event_log(...)
evs <- function(...) zuxml:::zux_event_log(...)$events
st  <- function(...) zuxml:::zux_event_log(...)$status
ti  <- function(...) zuxml:::zux_tree_info(...)

structure_of <- function(doc) zuxml:::zux_tree_info(xml_serialize(doc))$dump

nest <- function(n) paste0(paste(rep("<a>", n), collapse = ""),
                           paste(rep("</a>", n), collapse = ""))

# Shapes test-chunking.R parses at every chunk boundary.
fixtures <- list(
  simple     = "<a/>",
  nested     = "<a><b><c>x</c></b></a>",
  mixed      = "<p>Hello <em>XML</em> world</p>",
  attrs      = '<a id="1" lang="en" data-x="a b c"/>',
  namespaces = '<f:feed xmlns:f="urn:a" xmlns="urn:d"><e id="1">t</e></f:feed>',
  entities   = "<a>x&amp;y&lt;z&#65;</a>",
  cdata      = "<a><![CDATA[x<y&z]]>tail</a>",
  comment    = "<a><!-- a comment --><?pi some data?>t</a>",
  utf8       = "<a>naïve café 中文 \U0001F600</a>",
  decl       = '<?xml version="1.0" encoding="UTF-8"?><a>x</a>',
  wide       = paste0("<r>", strrep('<i a="1">t</i>', 50), "</r>")
)
