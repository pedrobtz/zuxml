ev  <- function(...) zuxml:::zux_event_log(...)
evs <- function(...) zuxml:::zux_event_log(...)$events

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

test_that("parsing is independent of chunk boundaries", {
  for (nm in names(fixtures)) {
    whole <- evs(fixtures[[nm]])
    expect_identical(evs(fixtures[[nm]]), whole, info = nm)
    for (k in c(1L, 2L, 3L, 7L, 31L, 4096L)) {
      expect_identical(evs(fixtures[[nm]], chunk = k), whole,
                       info = paste(nm, "chunk", k))
    }
  }
})

test_that("parsing is independent of random chunk boundaries", {
  set.seed(20260908)
  for (nm in names(fixtures)) {
    whole <- evs(fixtures[[nm]])
    for (trial in 1:5) {
      k <- sample.int(nchar(fixtures[[nm]], type = "bytes") + 1L, 1L)
      expect_identical(evs(fixtures[[nm]], chunk = k), whole,
                       info = paste(nm, "random chunk", k))
    }
  }
})

test_that("splitting inside a multibyte UTF-8 sequence is safe", {
  # One byte at a time guarantees every multibyte character is split.
  doc <- "<a>é中\U0001F600</a>"
  expect_identical(evs(doc, chunk = 1L), evs(doc))
  expect_identical(ev(doc, chunk = 1L)$status, "ok")
})

test_that("splitting inside specific lexical constructs is safe", {
  targets <- c(
    tag_open   = "<abcdef/>",
    attr_name  = '<a longattributename="v"/>',
    attr_value = '<a x="a long attribute value here"/>',
    entity     = "<a>&amp;&#12345;</a>",
    cdata      = "<a><![CDATA[payload]]></a>",
    close_tag  = "<abcdef>x</abcdef>",
    comment    = "<a><!-- a fairly long comment --></a>",
    pi         = "<a><?target a fairly long instruction?></a>"
  )
  for (nm in names(targets)) {
    whole <- evs(targets[[nm]])
    n <- nchar(targets[[nm]], type = "bytes")
    for (k in seq_len(n)) {
      expect_identical(evs(targets[[nm]], chunk = k), whole,
                       info = paste(nm, "split at", k))
    }
  }
})

test_that("an error is reported identically regardless of chunking", {
  bad <- "<a><b></a>"
  base <- ev(bad)
  for (k in c(1L, 2L, 5L)) {
    r <- ev(bad, chunk = k)
    expect_identical(r$status, base$status, info = paste("chunk", k))
    expect_identical(r$byte_offset, base$byte_offset, info = paste("chunk", k))
  }
})
