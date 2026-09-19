# The round-trip corpus, shared by test-serialize.R and test-semantics.R.
# Each entry is a shape the serializer has to reproduce exactly; several were
# added because a bug reached them and no existing entry did.
corpus <- c(
  empty_elem  = "<a/>",
  nested      = "<a><b><c>x</c></b></a>",
  mixed       = "<p>Hello <em>XML</em> world</p>",
  attrs       = '<a id="1" lang="en" k="a b c"/>',
  esc_attr    = '<a x="a&amp;b&lt;c&quot;d"/>',
  esc_text    = "<a>a &amp; b &lt; c &gt; d</a>",
  cdata       = "<a><![CDATA[x<y&z]]>tail</a>",
  ns_prefix   = '<f:a xmlns:f="urn:a"><f:b/></f:a>',
  ns_default  = '<a xmlns="urn:d"><b><c/></b></a>',
  ns_shadow   = '<a xmlns="urn:one"><b xmlns="urn:two"><c/></b></a>',
  ns_reset    = '<a xmlns="urn:d"><b xmlns=""><c/></b></a>',
  ns_same_uri = '<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i/><y:i/></r>',
  ns_attr     = '<a xmlns:p="urn:p" p:k="v" plain="w"/>',
  comment_pi  = "<a><!-- note --><?target data?>t</a>",
  utf8        = "<a>naïve café 中文 \U0001F600</a>",
  whitespace  = "<a>  leading and trailing  <b/>  </a>",
  wide        = paste0("<r>", strrep('<i a="1">t</i>', 30), "</r>"),
  deep        = paste0(strrep("<a>", 60), "x", strrep("</a>", 60)),
  attr_ws     = '<a t="line1&#10;line2&#9;tab"/>',
  cdata_close = "<a>a ]]&gt; b</a>",
  # A carriage return that arrived as a character reference survives parsing,
  # so it has to leave as one: end-of-line normalization would rewrite a
  # literal CR to LF on re-parse.
  cr_text     = "<a>x&#13;y</a>",
  cr_crlf     = "<a>line1&#13;&#10;line2</a>",
  cr_attr     = '<a v="x&#13;y"/>',
  # A "]]" and a ">" separated by a node that some option settings drop, so
  # the two land in adjacent text nodes and the seam has to be escaped.
  seam_comment = "<a>]]<!--c-->></a>",
  seam_pi      = "<a>]]<?p d?>></a>"
)
