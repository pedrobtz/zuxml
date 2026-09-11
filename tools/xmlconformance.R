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
#     TYPE="not-wf"   must be rejected
#     TYPE="invalid"  must be ACCEPTED -- "invalid" means invalid against a
#                     DTD, which a non-validating parser must not diagnose;
#                     accepting them is the conformant answer
#     TYPE="valid"    must be ACCEPTED
#     TYPE="error"    optional; never gated in either mode
#
# Scope is defined by the error class and not by grepping the bytes for
# "<!DOCTYPE", which is wrong in both directions: o-p15pass1, o-p16pass1 and
# o-p18pass1 carry the string inside a comment, a PI and a CDATA section, and
# ~180 files hit a parse error inside the DTD before the declaration is
# recognised at all.
#
# That judgement is applied TWICE, once per parse mode, because allow_doctype
# is a documented user-facing option and the default-mode gate is blind to it
# by construction: a gated file there is one zuxml did not stop at the
# DOCTYPE, so the flag cannot move any of them. Without the second gate the
# opt-in mode would have no conformance coverage at all.
#
#   allow_doctype = FALSE   591 gated, 47 deviations. No TYPE="valid" case
#                           survives -- all 812 carry a DOCTYPE.
#   allow_doctype = TRUE    730 gated, 92 deviations. Allowing a DOCTYPE with
#                           no internal subset brings 139 more cases in,
#                           including the first "valid" ones. Every extra
#                           deviation has one cause: the external subset is
#                           never retrieved, which shows up in both
#                           directions -- a not-wf document accepted because
#                           the violation is in the unread DTD, and a valid
#                           document rejected because the entity it
#                           references was declared there.
#
# Every deviation in both modes is attributable to a property the catalog
# itself states -- see `explain()`. Deviations with no such label fail the run.
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
    # "parameter"/"both" is the catalog stating that the declarations this
    # case turns on live outside the document -- see explain().
    ents    = xml_attr(tests, "ENTITIES"),
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

cat(sprintf("\n%s: %d catalogs, %d test cases\n", release, length(cases), nrow(d)))

# ---- attribution ---------------------------------------------------------
#
# Every deviation must be attributable to a property the catalog states about
# the case, not to a hand-maintained list of file names -- otherwise a NEW
# deviation can hide inside a known category. A deviation that no rule
# explains is a finding.
#
# Order matters. A case can satisfy more than one clause (the XML 1.1 P77
# name-character tests also pull in an external subset), and the first match
# should be the reason it actually deviates, so the narrower cause wins.
explain <- function(rec, ns, version, ents) {
  rec <- ifelse(is.na(rec), "", rec)
  ns <- ifelse(is.na(ns), "", ns)
  version <- ifelse(is.na(version), "", version)
  ents <- ifelse(is.na(ents), "", ents)
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
  ifelse(ents %in% c("parameter", "both"),
         # ENTITIES="parameter"/"both" is the catalog saying the declarations
         # this case turns on live outside the document. zuxml never fetches
         # an external subset (design §2 Never, §23.5), so it cannot see them,
         # and that shows up as BOTH symptoms: a not-wf document accepted
         # because the violation is in the unread DTD, and a valid document
         # rejected because the entity it references was declared there. One
         # cause, two directions.
         "external subset not retrieved (by design)",
         NA_character_))))
}

# One deviation is a genuine, reviewed difference rather than a category:
# a UTF-8 BOM followed by encoding='iso-8859-1'. The suite says not-wf; Expat
# does not diagnose the contradiction and zuxml reports encoding
# "iso-8859-1". Its sibling hst-lhs-008 (UTF-16 BOM vs a utf-8 declaration)
# *is* rejected, so this is specifically the UTF-8-BOM case. Listed rather
# than swept into a rule, because unlike the categories above it is a gap and
# not a design decision.
known <- c("hst-lhs-007" =
             "UTF-8 BOM contradicts encoding='iso-8859-1'; Expat does not diagnose")

# ---- one gate, run once per parse mode -----------------------------------
#
# Both modes are gated because allow_doctype is a documented, user-facing
# option, and the default-mode gate cannot see it: a gated file there is by
# construction one zuxml did not stop at the DOCTYPE, so the flag cannot move
# any of them. Running the same judgement twice is what gives that option
# coverage at all.
run_gate <- function(label, result, types, size_baseline, baseline) {
  adjudicated <- result != "zuxml_doctype_error"
  keep <- adjudicated & d$type %in% types
  g <- d[keep, ]
  g$result <- result[keep]
  # "invalid" and "valid" must both be ACCEPTED: invalid means invalid against
  # a DTD, which a non-validating parser must not diagnose.
  g$want <- g$type %in% c("invalid", "valid")
  g$deviant <- (g$result == "ok") != g$want
  g$why <- ifelse(g$deviant, explain(g$rec, g$ns, g$version, g$ents), NA)
  hit <- g$deviant & is.na(g$why) & g$id %in% names(known)
  g$why[hit] <- "known deviation"

  cat(sprintf("\n== gate: allow_doctype = %s ==============================\n",
              label))

  # The deviation baselines only mean anything against a pool of the expected
  # size. Without this, a truncated or wrong-release suite reports "0
  # unexplained" and passes -- the gate would be measuring nothing. Symmetric,
  # unlike the per-cause baselines: a pool that grew means the suite changed,
  # so the per-cause numbers were calibrated against a different population.
  if (nrow(g) != size_baseline) {
    stop("gated pool is ", nrow(g), ", expected ", size_baseline,
         " -- wrong suite release, or a catalog changed. Review before ",
         "updating the baselines.", call. = FALSE)
  }

  for (ty in types) {
    i <- which(g$type == ty)
    cat(sprintf("  %-20s %4d files, %4d as expected, %3d deviations\n",
                if (ty == "not-wf") "not-wf must reject" else
                  paste(ty, "must accept"),
                length(i), sum(!g$deviant[i]), sum(g$deviant[i])))
  }

  # Per cause, and asymmetric: a category growing means a case that used to
  # get the right answer stopped getting it, which is a regression even though
  # the cause is known. A category shrinking is an improvement, reported only.
  cat("  -- deviations, by cause --\n")
  bad <- 0L
  for (cause in names(baseline)) {
    n <- sum(g$deviant & !is.na(g$why) & g$why == cause)
    note <- ""
    if (n > baseline[[cause]]) {
      note <- sprintf("   <- REGRESSION, baseline is %d", baseline[[cause]])
      bad <- bad + 1L
    } else if (n < baseline[[cause]]) {
      note <- sprintf("   <- improved, baseline is %d", baseline[[cause]])
    }
    cat(sprintf("    %-50s %3d%s\n", cause, n, note))
  }
  for (j in which(g$deviant & g$why == "known deviation")) {
    cat(sprintf("        %s: %s\n", g$id[j], known[[g$id[j]]]))
  }

  un <- g[g$deviant & is.na(g$why), ]
  cat(sprintf("    %-50s %3d%s\n", "unexplained", nrow(un),
              if (nrow(un)) "   <- these fail the run" else ""))
  for (j in seq_len(nrow(un))) {
    cat(sprintf("        %-34s %-8s %-20s %s\n", un$id[j], un$type[j],
                if (is.na(un$rec[j])) "XML1.0" else un$rec[j], un$result[j]))
  }
  cat(sprintf("  %d gated, %d deviations, %d unexplained\n",
              nrow(g), sum(g$deviant), nrow(un)))
  bad + nrow(un)
}

bad <- 0L

# Default mode. No TYPE="valid" case survives here -- all 812 carry a DOCTYPE
# -- so the pool is not-wf and invalid only.
bad <- bad + run_gate("FALSE (package default)", d$result,
  c("not-wf", "invalid"), 591L, c(
    "XML 1.1 (zuxml is XML 1.0)"                         = 34L,
    "5th-edition name characters (zuxml is 4th edition)" = 10L,
    "NAMESPACE=\"no\" (zuxml is namespace-aware)"         =  2L,
    "external subset not retrieved (by design)"          =  0L,
    "known deviation"                                    =  1L))

# Opt-in mode. Allowing a DOCTYPE without an internal subset brings 139 more
# cases into scope, including the first TYPE="valid" ones the suite can offer
# this parser. The extra deviations are all one cause: the external subset is
# never retrieved.
bad <- bad + run_gate("TRUE (opt-in)", d$result_dt,
  c("not-wf", "invalid", "valid"), 730L, c(
    "XML 1.1 (zuxml is XML 1.0)"                         = 45L,
    "5th-edition name characters (zuxml is 4th edition)" = 10L,
    "NAMESPACE=\"no\" (zuxml is namespace-aware)"         =  2L,
    "external subset not retrieved (by design)"          = 34L,
    "known deviation"                                    =  1L))

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
# Not pass/fail. This is the part of the suite neither gate can reach, and its
# size is the honest price of the security model. Printed so that a change in
# the policy shows up here as a diff rather than as silence.

cat("\n-- reached by neither gate (informational) -------------------------\n")
never <- d[d$result_dt == "zuxml_doctype_error", ]
cat(sprintf("  %d of %d cases refused even with allow_doctype = TRUE, by TYPE: %s\n",
            nrow(never), nrow(d),
            paste(sprintf("%s=%d", names(table(never$type)),
                          as.integer(table(never$type))), collapse = "  ")))
cat("  every one carries an internal subset -- the only place a document can\n")
cat("  declare entities, and the rule that has no flag (design §11)\n")

cat(sprintf("\n%s\n", if (bad > 0L) "FAIL" else "==> conformance clean"))
if (bad > 0L) quit(status = 1L)
