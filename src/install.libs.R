## Installs the shared object, and beside it the LinkingTo surface that a
## consumer written against Expat itself needs: libzuxml.a and Expat's two
## public headers. See src/Makevars for why that surface exists.
##
## Defining this file makes R stop installing the shared object by itself, so
## the first block below is not optional boilerplate -- without it the package
## installs with no compiled code at all. (Writing R Extensions 1.2.1.1.)

libs <- file.path(R_PACKAGE_DIR, paste0("libs", R_ARCH))
dir.create(libs, recursive = TRUE, showWarnings = FALSE)
file.copy(Sys.glob(paste0("*", SHLIB_EXT)), libs, overwrite = TRUE)
if (file.exists("symbols.rds")) {
  file.copy("symbols.rds", libs, overwrite = TRUE)
}

## The archive is arch-specific but installs to a single arch-neutral path,
## which is what the design asks for and what every current platform needs.
## It would have to move under R_ARCH before zuxml could support a multi-arch
## installation again.
lib <- file.path(R_PACKAGE_DIR, "lib")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
if (!file.copy("libzuxml.a", lib, overwrite = TRUE)) {
  stop("zuxml: failed to install libzuxml.a; src/Makevars should have built it")
}

## Expat's public headers, copied from the vendored tree rather than kept as a
## second copy under inst/include/, so they cannot drift from the sources the
## archive was compiled from. They land beside zuxml.h, which R's own "inst"
## step copies here afterwards -- that step merges into this directory rather
## than replacing it, which tests/testthat/test-linking.R checks from the
## installed package.
include <- file.path(R_PACKAGE_DIR, "include")
dir.create(include, recursive = TRUE, showWarnings = FALSE)
headers <- file.path("vendor", "expat", c("expat.h", "expat_external.h"))
if (!all(file.copy(headers, include, overwrite = TRUE))) {
  stop("zuxml: failed to install the Expat headers from src/vendor/expat/")
}
