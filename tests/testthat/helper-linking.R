# For test-linking.R, which audits the installed layout.
#
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

# The archive installs under lib${R_ARCH}, which is plain lib/ where R sets no
# architecture (#42).
archive_path <- function() {
  arch <- .Platform$r_arch
  if (nzchar(arch)) installed_path("lib", arch, "libzuxml.a")
  else installed_path("lib", "libzuxml.a")
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
