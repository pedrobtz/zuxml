# The round-trip property, checked against a semantic oracle rather than
# against zux_tree_info()$dump, which records only how many attributes a node
# has. See helper-semantics.R.

# Why this file exists, in one experiment: a serializer mutated to emit
# attributes sorted by local name -- silently reordering every attribute list,
# which man/xml_serialize.Rd promises is preserved -- survives the whole rest
# of the suite. Sorting is idempotent, so the fixed-point check sees nothing,
# and zux_tree_info()$dump records only how many attributes a node has, so the
# structural check sees nothing either. That mutant is caught here and nowhere
# else. tools/run-mutation-check is not the place for it: that gate drives a C
# probe to prove the security guards are load-bearing, and this oracle is R.

test_that("the fingerprint sees everything the docs promise is preserved", {
  # An oracle nobody has tried to fool is worth very little: the dump-based
  # one silently could not tell any of these pairs apart. Each row below must
  # come out different, or the round-trip tests that follow prove nothing.
  u <- c("urn:p", "urn:x", "urn:one", "urn:two", "urn:d")
  fp <- function(x) paste(zux_semantics(x, u), collapse = " ")
  differs <- function(a, b) expect_false(identical(fp(a), fp(b)), info = a)

  differs('<a xmlns:p="urn:p" p:k="v"/>', '<a k="v"/>')    # attribute namespace
  differs('<a z="1" m="2"/>',             '<a m="2" z="1"/>')  # attribute order
  differs('<a k="v"/>',                   '<a k="w"/>')    # attribute value
  differs('<a k="v"/>',                   '<a/>')          # attribute dropped
  differs('<a xmlns="urn:d"/>',           '<a/>')          # element namespace
  differs('<a xmlns="urn:d"><b/></a>',    '<a><b/></a>')   # inherited namespace
  differs('<a>x<b/>y</a>',                '<a>y<b/>x</a>') # text order
  differs('<a><b/><c/></a>',              '<a><c/><b/></a>')   # child order
  differs('<a><!--c--><b/></a>',          '<a><b/></a>')   # comment dropped
  differs('<a><?p d?><b/></a>',           '<a><b/></a>')   # PI dropped
  differs('<a><?p d?></a>',               '<a><?q d?></a>')    # PI target
})

test_that("the fingerprint ignores what the docs say is not preserved", {
  u <- c("urn:x")
  fp <- function(x) paste(zux_semantics(x, u), collapse = " ")
  same <- function(a, b) expect_identical(fp(a), fp(b), info = a)

  same('<p:a xmlns:p="urn:x"/>', '<q:a xmlns:q="urn:x"/>')  # prefix spelling
  same('<a></a>',                '<a/>')                    # empty element
  same('<a><![CDATA[x<y]]></a>', '<a>x&lt;y</a>')            # CDATA boundary
  same("<a k='v'/>",             '<a k="v"/>')               # quote style
  same('<a  k="v"   j="w"/>',    '<a k="v" j="w"/>')         # inter-attr space
})

test_that("round-tripping preserves semantics, not just serialized text", {
  # The corpus-wide property with an oracle that can see attributes. Every
  # comment and PI setting, since dropping a node changes the node sequence.
  for (nm in names(corpus)) {
    for (kc in c(TRUE, FALSE)) for (kp in c(TRUE, FALSE)) {
      x <- corpus[[nm]]
      s <- xml_serialize(xml_parse(x, comments = kc, pis = kp))
      u <- union(zux_uris(x), zux_uris(s))
      expect_identical(
        zux_semantics(s, u, comments = kc, pis = kp),
        zux_semantics(x, u, comments = kc, pis = kp),
        info = sprintf("%s comments=%s pis=%s", nm, kc, kp))
    }
  }
})

test_that("namespace re-emission preserves namespace semantics", {
  cases <- c(
    default          = '<a xmlns="urn:d"><b><c/></b></a>',
    prefixed         = '<p:a xmlns:p="urn:x"><p:b/></p:a>',
    shadowed         = '<a xmlns="urn:one"><b xmlns="urn:two"><c/></b></a>',
    reset            = '<a xmlns="urn:d"><b xmlns=""><c/></b></a>',
    two_prefixes     = '<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i/><y:i/></r>',
    rebound_prefix   = '<p:a xmlns:p="urn:one"><p:b xmlns:p="urn:two"><p:c/></p:b></p:a>',
    attr_prefixed    = '<a xmlns:p="urn:p" p:k="v" plain="w"/>',
    # An unprefixed attribute is in no namespace even under a default xmlns,
    # so an attribute in the same URI as its element still needs a prefix.
    attr_same_uri    = '<a xmlns="urn:x" xmlns:p="urn:x" p:k="v"/>',
    attr_only_use    = '<a xmlns:p="urn:p" p:k="v"/>',
    declared_unused  = '<a xmlns:p="urn:p"><b/></a>',
    attr_vs_element  = '<p:a xmlns:p="urn:p" p:a="1" a="2"/>',
    deep_reuse       = '<a xmlns:p="urn:p"><p:b><c p:k="v"/></p:b></a>',
    default_on_child = '<a><b xmlns="urn:d"><c/></b></a>',
    many             = '<a xmlns="urn:d" xmlns:p="urn:p" xmlns:q="urn:q" p:k="1" q:k="2" k="3"/>',
    attr_order       = '<a z="1" m="2" a="3" b="4"/>',
    attr_order_ns    = '<a xmlns:p="urn:p" z="1" p:z="2" m="3" p:m="4"/>'
  )
  for (nm in names(cases)) {
    x <- cases[[nm]]
    s <- xml_serialize(xml_parse(x))
    u <- union(zux_uris(x), zux_uris(s))
    expect_identical(zux_semantics(s, u), zux_semantics(x, u), info = nm)
    # And a second pass changes nothing.
    expect_identical(xml_serialize(xml_parse(s)), s, info = nm)
  }
})

test_that("allow_doctype does not reach the tree or the serializer", {
  # Which is why fuzz_roundtrip.c does not vary it: the option gates
  # acceptance only, so it adds no serializer state to explore. fuzz_tree.c
  # varies it, where parse and tree behaviour is what is under test.
  x <- '<!DOCTYPE greeting><greeting a="1">hi</greeting>'
  d <- xml_parse(x, allow_doctype = TRUE)
  s <- xml_serialize(d)

  expect_false(grepl("DOCTYPE", s, fixed = TRUE))
  # The body is identical to the same document without the declaration, and
  # the output re-parses under the stricter default.
  expect_identical(s, xml_serialize(xml_parse('<greeting a="1">hi</greeting>')))
  expect_s3_class(xml_parse(s), "zuxml_document")
  expect_identical(
    zux_semantics(s, character(0)),
    zux_semantics(x, character(0), allow_doctype = TRUE))
})
