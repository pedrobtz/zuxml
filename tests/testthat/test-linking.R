# The LinkingTo surface for consumers written against Expat itself, rather
# than against the registered function table: <pkg>/lib/libzuxml.a and Expat's
# public headers. See src/Makevars and src/install.libs.R.
#
# These read the *installed* package, which is what a consumer sees. Under
# devtools::load_all() there is no installed layout, so they skip; R CMD check
# runs them against a real installation, which is where they have teeth.

# Whether this is an installed layout is decided once, from a file that R's
# install step writes and nothing else does, and never from the artifact under
# test: asking system.file() for libzuxml.a itself returns "" both under
# load_all() and when the install lost the archive, so a missing archive used
# to report a skip, and R CMD check passes a skip (#38). Meta/package.rds is
# outside inst/, so load_all() cannot find it in the source tree either.
skip_if_not_installed_layout <- function() {
  skip_if(!nzchar(system.file("Meta", "package.rds", package = "zuxml")),
          "not an installed layout")
}

# Absolute path to something install.libs.R is responsible for, without
# asking whether it exists: the caller asserts that, so a missing file fails.
installed_path <- function(...) {
  skip_if_not_installed_layout()
  file.path(system.file(package = "zuxml"), ...)
}

# nm over an archive interleaves a "member.o:" line before each member's
# symbols, and those lines are not symbols -- reading them as such is how a
# test asserting "no zux_ symbol here" fails on the member named
# zux_expat_random.o. Keep only lines that carry a symbol type.
archive_symbols <- function(archive) {
  # Not a skip: the layout exists by now, so an absent archive is a failure
  # of the install, which is what this file audits.
  expect_true(file.exists(archive), label = archive)
  if (!file.exists(archive)) return(character())
  nm <- Sys.which("nm")
  skip_if(!nzchar(nm), "nm is not available on this platform")
  out <- suppressWarnings(
    system2(nm, c("-g", shQuote(archive)), stdout = TRUE, stderr = FALSE)
  )
  skip_if(!is.character(out) || length(out) == 0L, "nm produced no output")
  grep("^[0-9a-fA-F ]*\\s[A-Za-z]\\s", out, value = TRUE)
}

test_that("Expat's licence is installed with the Expat it ships", {
  # The installed package carries Expat compiled into zuxml.so and
  # libzuxml.a, and as expat.h, so the MIT notice has to come with it.
  # inst/COPYRIGHTS points here.
  f <- installed_path("licenses", "expat-COPYING")
  expect_true(file.exists(f))
  if (!file.exists(f)) return()
  txt <- paste(readLines(f), collapse = "\n")
  expect_match(txt, "Copyright (c) 2001-", fixed = TRUE)
  expect_match(txt, "Permission is hereby granted", fixed = TRUE)
  expect_match(paste(readLines(system.file("COPYRIGHTS", package = "zuxml")),
                     collapse = "\n"),
               "licenses/expat-COPYING", fixed = TRUE)
})

test_that("the static archive is installed", {
  archive <- installed_path("lib", "libzuxml.a")
  expect_true(file.exists(archive))
  expect_gt(file.size(archive), 0)
})

test_that("Expat's public headers are installed beside zuxml.h", {
  # The merge is the fragile part: install.libs.R writes expat.h into
  # <pkg>/include during the libs step, and R's own "inst" step copies
  # zuxml.h into the same directory afterwards. If that ever replaced the
  # directory instead of merging into it, the archive would still install and
  # only the headers would vanish.
  expect_true(file.exists(installed_path("include", "expat.h")))
  expect_true(file.exists(installed_path("include", "expat_external.h")))
  expect_true(file.exists(installed_path("include", "zuxml.h")))
})

test_that("the installed header and the compiled archive are the same Expat", {
  # A consumer compiles against the header and links against the archive, so
  # a bump that updates one and not the other is its problem, not ours, and
  # would show up as a silent ABI mismatch rather than a build error.
  header <- readLines(installed_path("include", "expat.h"), warn = FALSE)
  part <- function(name) {
    line <- grep(paste0("^#\\s*define XML_", name, "_VERSION\\b"), header, value = TRUE)
    expect_length(line, 1L)
    sub("^.*\\s(\\d+)\\s*$", "\\1", line)
  }
  from_header <- paste(part("MAJOR"), part("MINOR"), part("MICRO"), sep = ".")
  # zuxml_info() reports it as "expat_2.8.4"; the header carries the three
  # numbers. Compare the numbers, not the spelling.
  expect_match(zuxml_info()$expat_version, from_header, fixed = TRUE)
})

test_that("the header's optional APIs match what the archive actually defines", {
  # expat.h declares the billion-laughs limiters only under XML_DTD or
  # XML_GE == 1, and src/expat_config.h sets XML_GE 0 -- so they are compiled
  # out. A consumer that defines XML_GE=1 on its own command line would get
  # the declarations and then fail to link. The default (defining neither) is
  # the one that matches, and that is what this pins.
  code <- installed_path("include", "expat.h") |>
    readLines(warn = FALSE) |>
    paste(collapse = "\n")
  expect_match(
    code,
    "#\\s*if\\s+defined\\(XML_DTD\\)\\s*\\|\\|\\s*\\(defined\\(XML_GE\\)",
    fixed = FALSE
  )

  symbols <- archive_symbols(installed_path("lib", "libzuxml.a"))
  expect_length(
    grep("XML_SetBillionLaughsAttackProtection", symbols, value = TRUE), 0L
  )
})

test_that("the archive carries Expat and nothing of R", {
  symbols <- archive_symbols(installed_path("lib", "libzuxml.a"))
  defined <- grep("\\sU\\s", symbols, value = TRUE, invert = TRUE)

  # The Expat entry points a consumer cannot do without. The suspend/resume
  # pair is here deliberately: a pull-style reader built on this archive --
  # xlsxio's row and cell iterators, for one -- is written around it, and it
  # has no equivalent in zuxml.h's callback API.
  required <- c("XML_ParserCreate", "XML_ParserFree", "XML_SetUserData",
                "XML_SetElementHandler", "XML_SetCharacterDataHandler",
                "XML_GetBuffer", "XML_ParseBuffer", "XML_Parse",
                "XML_StopParser", "XML_ResumeParser", "XML_GetParsingStatus",
                "XML_GetErrorCode", "XML_ErrorString")
  for (name in required) {
    expect_length(grep(paste0("\\b_?", name, "\\b"), defined, value = TRUE), 1L)
  }

  # Nothing R-facing may be in here. The archive is linked into someone
  # else's shared object, where a zuxml R symbol would be dead weight at
  # best and a duplicate definition at worst.
  expect_length(grep("\\b_?(zux_|zuxml_|R_init_)", defined, value = TRUE), 0L)
})
