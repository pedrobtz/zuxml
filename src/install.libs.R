## Installs the shared object, and beside it the LinkingTo surface that a
## consumer written against Expat itself needs: libzuxml.a and Expat's two
## public headers. See src/Makevars for why that surface exists.
##
## Defining this file makes R stop installing the shared object by itself, so
## the first block below is not optional boilerplate -- without it the package
## installs with no compiled code at all. (Writing R Extensions 1.2.1.1.)

install_or_stop <- function(from, to, what) {
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  ## file.copy() returns a logical per source and never signals, so an
  ## unchecked call is how a package installs with a piece silently missing.
  ok <- file.copy(from, to, overwrite = TRUE)
  if (length(ok) == 0L || !all(ok)) {
    stop("zuxml: failed to install ", what, " into ", to)
  }
  invisible(TRUE)
}

libs <- file.path(R_PACKAGE_DIR, paste0("libs", R_ARCH))
## Checked like everything else here: Sys.glob() returning nothing is exactly
## the "no compiled code at all" failure the comment above describes, and an
## unchecked copy of zero files succeeds quietly.
install_or_stop(Sys.glob(paste0("*", SHLIB_EXT)), libs, "the shared object")
if (file.exists("symbols.rds")) {
  install_or_stop("symbols.rds", libs, "symbols.rds")
}

## The archive is arch-specific but installs to a single arch-neutral path,
## which is what the design asks for and what every current platform needs.
## It would have to move under R_ARCH before zuxml could support a multi-arch
## installation again.
lib <- file.path(R_PACKAGE_DIR, "lib")
install_or_stop("libzuxml.a", lib,
                "libzuxml.a (src/Makevars should have built it)")

## Expat's public headers, copied from the vendored tree rather than kept as a
## second copy under inst/include/, so they cannot drift from the sources the
## archive was compiled from. They land beside zuxml.h, which R's own "inst"
## step copies here afterwards -- that step merges into this directory rather
## than replacing it, which tests/testthat/test-linking.R checks from the
## installed package.
include <- file.path(R_PACKAGE_DIR, "include")
install_or_stop(file.path("vendor", "expat", c("expat.h", "expat_external.h")),
                include, "the Expat headers from src/vendor/expat/")

## Expat's licence. This is a licensing obligation, not tidiness: MIT requires
## the copyright and permission notice to accompany every copy, and an
## installed zuxml carries Expat three times over -- compiled into the shared
## object, compiled into libzuxml.a, and as expat.h. Nothing outside inst/ is
## installed, so without this copy the notice reached the source tarball and
## stopped there; inst/COPYRIGHTS pointed at a file the installed package did
## not have. Copied from the vendored tree, so it cannot drift from the sources
## the archive was compiled from. zukomp installs miniz's the same way.
licenses <- file.path(R_PACKAGE_DIR, "licenses")
dir.create(licenses, recursive = TRUE, showWarnings = FALSE)
if (!file.copy(file.path("vendor", "expat", "COPYING"),
               file.path(licenses, "expat-COPYING"), overwrite = TRUE)) {
  stop("zuxml: failed to install Expat's COPYING from src/vendor/expat/")
}
