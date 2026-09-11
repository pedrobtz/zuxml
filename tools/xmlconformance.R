#!/usr/bin/env Rscript
#
# Conformance: run the W3C XML Conformance Test Suite against zuxml.
#
# The suite is the standard external check on what an XML parser accepts and
# rejects. It is *not* shaped like nst/JSONTestSuite, and a direct port of
# tools/jsontestsuite.R from zujson would report a catastrophe where there is
# none. The difference is worth stating, because it determines everything
# below.
#
# JSONTestSuite's y_/n_ split maps one-to-one onto json_validate(). The W3C
# suite's TYPE attribute does not map onto xml_parse(), because the suite is
# DTD-centric by construction -- it was written to exercise validating and
# non-validating parsers against the whole of XML 1.0, including DTDs, entity
# expansion, attribute defaulting and conditional sections. zuxml implements
# the DTD-free subset on purpose (see R/parse.R and the security tests), so
# large parts of the suite are testing machinery this package does not have
# and will not grow.
#
# Concretely, at the time of writing: all 812 TYPE="valid" files carry a
# DOCTYPE, so a naive harness scores 0/812 on the "must accept" cases. That is
# not a conformance failure, it is the documented policy working. Equally,
# 985 of the 1498 TYPE="not-wf" files are refused at the DOCTYPE gate before
# their actual well-formedness violation is ever reached -- the right answer
# for the wrong reason, and counting those as passes would be dishonest.
#
# So the gate here is narrower and means something:
#
#   ADJUDICATED = zuxml returned anything other than zuxml_doctype_error, i.e.
#   it actually formed an opinion about the document's well-formedness rather
#   than stopping at the policy gate. Within that set:
#
#     TYPE="not-wf"   must be rejected   (513 files)
#     TYPE="invalid"  must be ACCEPTED   (78 files) -- "invalid" means invalid
#                     against a DTD, which a non-validating parser must not
#                     diagnose; accepting them is the conformant answer
#     TYPE="error"    optional, reported but never gated
#     TYPE="valid"    none survive; all 812 are refused at the DOCTYPE
#
# Scope is defined by the error class and not by grepping the bytes for
# "<!DOCTYPE", which is wrong in both directions: o-p15pass1, o-p16pass1 and
# o-p18pass1 carry the string inside a comment, a PI and a CDATA section, and
# ~180 files hit a parse error inside the DTD before the declaration is
# recognised at all.
#
# Current standing for xmlts20130923: 591 gated files, 544 as expected and 47
# deviations, every one of which falls into a category the catalog itself
# labels -- see `explain()`. Deviations with no such label fail the run.
#
# The canonical-XML OUTPUT files are deliberately not compared. Only three
# adjudicated cases even have one, and xml_serialize() is not a C14N
# implementation, so a byte comparison would report formatting differences as
# conformance failures.
#
# Needs network on the first run. Run from the package root:
#
#   Rscript tools/xmlconformance.R
#
# Set XMLCONF_DIR to an unpacked suite to skip the download, which is also how
# a CI job avoids hitting w3.org on every build:
#
#   XMLCONF_DIR=~/src/xmlconf Rscript tools/xmlconformance.R
#
# Exits non-zero on any unexplained deviation, or if an explained category has
# grown past its baseline.
#
# Base R only, and deliberately so: the same constraint as tools/run-fuzz and
# zujson's tools/jsontestsuite.R, so the script runs anywhere the package
# builds without dragging in a test framework.

library(zuxml)

# Pinned to a dated archive, not to a "latest" URL. W3C ships the suite as
# immutable dated zips and it has been frozen since 2013, which makes this a
# stronger pin than a git commit: there is no upstream branch to drift. Bump
# it deliberately and review what moved.
release <- "xmlts20130923"
url <- sprintf("https://www.w3.org/XML/Test/%s.zip", release)

root <- Sys.getenv("XMLCONF_DIR", "")
if (!nzchar(root)) {
  zipfile <- tempfile(fileext = ".zip")
  cat("downloading", release, "\n")
  download.file(url, zipfile, mode = "wb", quiet = TRUE)
  exdir <- tempfile("xmlconf-")
  unzip(zipfile, exdir = exdir)
  root <- file.path(exdir, "xmlconf")
}
if (!file.exists(file.path(root, "xmlconf.xml"))) {
  stop("no xmlconf.xml under '", root, "'", call. = FALSE)
}

# The master catalog is the one file in the suite zuxml cannot read: it
# composes the sub-catalogs out of external entities declared in an internal
# subset, which is exactly what this package refuses. Pull the sub-catalog
# paths out with a regex and read those directly -- they are plain XML, so
# from here on the harness parses its own input with the package under test.
master <- readLines(file.path(root, "xmlconf.xml"), warn = FALSE)
subs <- unique(sub('.*SYSTEM "([^"]*\\.xml)".*', "\\1",
                   grep('SYSTEM "[^"]*\\.xml"', master, value = TRUE)))
if (!length(subs)) stop("no sub-catalogs found in xmlconf.xml", call. = FALSE)

read_bytes <- function(path) {
  n <- file.info(path)$size
  if (is.na(n)) stop("cannot stat '", path, "'", call. = FALSE)
  if (n == 0) return(raw(0))
  readBin(path, "raw", n = n)
}

# Every catalog is wrapped in a synthetic root before parsing, unconditionally,
# which handles two separate shapes that would otherwise be lost silently:
#
#   sun/sun-valid.xml, sun-invalid.xml and sun-not-wf.xml are bare external
#   parsed entities -- many top-level <TEST> elements and no root at all,
#   because the master catalog only ever pulls them in through an entity
#   reference. Parsed as documents they fail on "junk after document element",
#   taking 158 cases with them.
#
#   sun/sun-error.xml is a well-formed document whose ROOT is the <TEST>. It
#   parses, but xml_find() selects descendants (R/node.R), and the root is not
#   a descendant of itself, so the single case in it goes missing without any
#   error. Wrapping puts every <TEST> at depth >= 1 and makes the two shapes
#   one case.
#
# The wrapper is ASCII and the bytes are spliced raw, so nothing re-encodes;
# every catalog in this release is ASCII (the test *files* are not, but they
# are never wrapped).
read_catalog <- function(path) {
  b <- read_bytes(path)
  # An XML declaration, if present, must stay first. Its pseudo-attribute
  # values cannot contain ">", so the first ">" ends it.
  at <- 0L
  if (length(b) >= 5L && identical(b[1:5], charToRaw("<?xml"))) {
    at <- which(b == charToRaw(">"))[1L]
    if (is.na(at)) stop("unterminated XML declaration in '", path, "'",
                        call. = FALSE)
  }
  xml_parse(c(head(b, at), charToRaw("<TESTCASES>"),
              tail(b, length(b) - at), charToRaw("</TESTCASES>")))
}

cases <- list()
for (s in subs) {
  path <- file.path(root, s)
  # A catalog the master lists but that is not on disk means the suite is
  # incomplete, which makes every count below meaningless. Not a warning.
  if (!file.exists(path)) {
    stop("catalog listed in xmlconf.xml but missing: '", s, "'", call. = FALSE)
  }
  doc <- read_catalog(path)
  tests <- xml_find(doc, "TEST")
  # A catalog that contributes nothing is a harness bug, not an empty file --
  # that is how sun-error.xml disappeared. Fail loudly rather than skip.
  if (!length(tests)) stop("no <TEST> elements found in '", s, "'", call. = FALSE)
  cases[[s]] <- data.frame(
    catalog = s,
    id      = xml_attr(tests, "ID"),
    type    = xml_attr(tests, "TYPE"),
    ns      = xml_attr(tests, "NAMESPACE"),
    rec     = xml_attr(tests, "RECOMMENDATION"),
    version = xml_attr(tests, "VERSION"),
    output  = xml_attr(tests, "OUTPUT"),
    # URIs resolve against the sub-catalog's own directory. The master
    # catalog also carries xml:base on each <TESTCASES> it composes, but that
    # is both redundant and, in one case, stale: it gives ht-bh.xml the base
    # "eduni/namespaces/misc/" while the entity points at "eduni/misc/", where
    # the files actually are. dirname() of the sub-catalog agrees with every
    # xml:base that is correct and is right where that one is not -- the
    # existence check below is what proves it.
    path    = file.path(root, dirname(s), xml_attr(tests, "URI")),
    stringsAsFactors = FALSE)
}
d <- do.call(rbind, cases)

missing <- !file.exists(d$path)
if (any(missing)) {
  stop(sum(missing), " test files listed in the catalogs are missing, e.g. ",
       d$path[which(missing)[1]], call. = FALSE)
}

# Every file is read as bytes. Reading them as text would be wrong: the suite
# is full of UTF-16, of deliberately broken encodings, and of byte sequences
# that are not valid in any encoding -- which is the point of those cases.
outcome <- function(path) {
  bytes <- read_bytes(path)
  tryCatch({ xml_parse(bytes); "ok" },
    zuxml_error = function(e) class(e)[1],
    error = function(e) paste0("bare:", conditionMessage(e)))
}
d$result <- vapply(d$path, outcome, "", USE.NAMES = FALSE)

# allow_doctype changes nothing in the gated set by construction -- every
# gated file is one zuxml did not stop at the DOCTYPE -- so the gate is stable
# regardless of that argument. It is varied only for the informational
# section, where it separates "refused for having a DTD at all" from "refused
# for having an internal subset".
outcome_dt <- function(path) {
  bytes <- read_bytes(path)
  tryCatch({ xml_parse(bytes, allow_doctype = TRUE); "ok" },
    zuxml_error = function(e) class(e)[1],
    error = function(e) paste0("bare:", conditionMessage(e)))
}
d$result_dt <- vapply(d$path, outcome_dt, "", USE.NAMES = FALSE)

d$adjudicated <- d$result != "zuxml_doctype_error"
d$accepted <- d$result == "ok"

cat(sprintf("\n%s: %d catalogs, %d test cases, %d adjudicated\n",
            release, length(cases), nrow(d), sum(d$adjudicated)))

# ---- the gate ------------------------------------------------------------

gated <- d[d$adjudicated & d$type %in% c("not-wf", "invalid"), ]
gated$want <- gated$type == "invalid"   # invalid must be ACCEPTED, not-wf must not
gated$deviant <- gated$accepted != gated$want

# Every deviation must be attributable to a property the catalog states about
# the case, not to a hand-maintained list of file names. A deviation that no
# rule explains is a finding.
explain <- function(rec, ns, version) {
  rec <- ifelse(is.na(rec), "", rec)
  ns <- ifelse(is.na(ns), "", ns)
  version <- ifelse(is.na(version), "", version)
  ifelse(rec %in% c("XML1.1", "NS1.1") | version == "1.1",
         # Expat is an XML 1.0 processor. These cases turn on characters XML
         # 1.1 forbids but 1.0 permits (ibm02n32 is a bare 0x7F), or on the
         # wider 1.1 name repertoire. Rejecting them would be the wrong answer
         # for the recommendation zuxml actually implements.
         "XML 1.1 (zuxml is XML 1.0)",
  ifelse(rec %in% c("XML1.0-errata3e", "XML1.0-errata4e"),
         # The 5th edition widened NameChar substantially. Expat implements
         # the 4th edition classes.
         "5th-edition name characters (zuxml is 4th edition)",
  ifelse(ns == "no",
         # The catalog marks these as not namespace-well-formed; zuxml is
         # namespace-aware, so refusing them is correct for this parser.
         "NAMESPACE=\"no\" (zuxml is namespace-aware)",
         NA_character_)))
}
gated$why <- ifelse(gated$deviant,
                    explain(gated$rec, gated$ns, gated$version), NA_character_)

# One deviation is a genuine, reviewed difference rather than a category:
# a UTF-8 BOM followed by encoding='iso-8859-1'. The suite says not-wf; Expat
# does not diagnose the contradiction and zuxml reports encoding
# "iso-8859-1". Its sibling hst-lhs-008 (UTF-16 BOM vs a utf-8 declaration)
# *is* rejected, so this is specifically the UTF-8-BOM case. Listed rather
# than swept into a rule, because unlike the categories above it is a gap and
# not a design decision.
known <- c("hst-lhs-007" =
             "UTF-8 BOM contradicts encoding='iso-8859-1'; Expat does not diagnose")
hit <- gated$deviant & is.na(gated$why) & gated$id %in% names(known)
gated$why[hit] <- "known deviation"

# The deviation baselines only mean anything against a pool of the expected
# size. Without this, a truncated or wrong-release suite reports "0
# unexplained" and passes -- the gate would be measuring nothing.
gated_baseline <- 591L
if (nrow(gated) != gated_baseline) {
  stop("gated pool is ", nrow(gated), ", expected ", gated_baseline,
       " -- wrong suite release, or a catalog changed. Review before ",
       "updating the baselines.", call. = FALSE)
}

cat("\n-- gated: documents zuxml adjudicated ------------------------------\n")
for (ty in c("not-wf", "invalid")) {
  i <- which(gated$type == ty)
  cat(sprintf("%-22s %4d files, %4d as expected, %3d deviations\n",
              if (ty == "not-wf") "not-wf must reject" else "invalid must accept",
              length(i), sum(!gated$deviant[i]), sum(gated$deviant[i])))
}

# Baselines are per cause. A category shrinking is an improvement and only
# reported; a category growing means a case that used to get the right answer
# stopped getting it, which is a regression even though the cause is known.
baseline <- c(
  "XML 1.1 (zuxml is XML 1.0)"                        = 34L,
  "5th-edition name characters (zuxml is 4th edition)" = 10L,
  "NAMESPACE=\"no\" (zuxml is namespace-aware)"        =  2L,
  "known deviation"                                    =  1L)

cat("\n-- deviations, by cause -------------------------------------------\n")
bad <- 0L
for (cause in names(baseline)) {
  n <- sum(gated$deviant & !is.na(gated$why) & gated$why == cause)
  note <- ""
  if (n > baseline[[cause]]) {
    note <- sprintf("   <- REGRESSION, baseline is %d", baseline[[cause]])
    bad <- bad + 1L
  } else if (n < baseline[[cause]]) {
    note <- sprintf("   <- improved, baseline is %d", baseline[[cause]])
  }
  cat(sprintf("  %-52s %3d%s\n", cause, n, note))
}
for (j in which(gated$deviant & gated$why == "known deviation")) {
  cat(sprintf("      %s: %s\n", gated$id[j], known[[gated$id[j]]]))
}

unexplained <- gated[gated$deviant & is.na(gated$why), ]
cat(sprintf("  %-52s %3d%s\n", "unexplained", nrow(unexplained),
            if (nrow(unexplained)) "   <- these fail the run" else ""))
for (j in seq_len(nrow(unexplained))) {
  cat(sprintf("      %-34s %-8s %-20s %s\n", unexplained$id[j],
              unexplained$type[j],
              if (is.na(unexplained$rec[j])) "XML1.0" else unexplained$rec[j],
              unexplained$result[j]))
}
bad <- bad + nrow(unexplained)

# A condition that is not a zuxml_error has escaped the contract, whatever the
# accept/reject answer was. Same check as the zujson script.
bare <- d[startsWith(d$result, "bare:") | startsWith(d$result_dt, "bare:"), ]
if (nrow(bare)) {
  bad <- bad + nrow(bare)
  cat("\nESCAPED THE zuxml_error CONTRACT (must not happen):\n")
  for (j in seq_len(nrow(bare))) {
    cat("    ", bare$id[j], " -> ", bare$result[j], "\n", sep = "")
  }
}

# ---- informational: what the DOCTYPE policy costs -------------------------
#
# Not pass/fail. This is the part of the suite zuxml declines to answer, and
# its size is the honest price of the security model. Printed so that a change
# in the policy shows up here as a diff rather than as silence.

cat("\n-- not gated: refused at the DOCTYPE (informational) ---------------\n")
gate_stopped <- d[!d$adjudicated, ]
cat(sprintf("  %d of %d cases, by TYPE: %s\n", nrow(gate_stopped), nrow(d),
            paste(sprintf("%s=%d", names(table(gate_stopped$type)),
                          as.integer(table(gate_stopped$type))),
                  collapse = "  ")))
cat(sprintf("  with allow_doctype = TRUE, %d of these parse; %d still refuse\n",
            sum(gate_stopped$result_dt == "ok"),
            sum(gate_stopped$result_dt == "zuxml_doctype_error")))
cat("  (the remainder is the internal-subset rule: a DTD may be declared,\n")
cat("   but never one that can declare entities)\n")

opt <- d[d$adjudicated & d$type == "error", ]
if (nrow(opt)) {
  cat(sprintf("\n-- TYPE=\"error\": optional, never gated ------------------------\n"))
  cat(sprintf("  %d adjudicated, %d accepted, %d rejected\n",
              nrow(opt), sum(opt$accepted), sum(!opt$accepted)))
}

cat(sprintf("\n%d gated files, %d deviations, %d unexplained\n",
            nrow(gated), sum(gated$deviant), nrow(unexplained)))
if (bad > 0L) {
  cat("FAIL\n")
  quit(status = 1L)
}
cat("==> conformance clean\n")
