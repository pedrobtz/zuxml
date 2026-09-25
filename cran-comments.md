## Submission

This is a new submission.

zuxml bundles the Expat XML parser, version 2.8.4
(<https://libexpat.github.io/>), unmodified, in `src/vendor/expat/`. Its
copyright holders are listed in `Authors@R` and `inst/COPYRIGHTS`.

## Test environments

* local macOS 26.6.2, R 4.6.1
* GitHub Actions: ubuntu-latest (R release, oldrel-1), macOS-latest (R
  release), windows-latest (R release, R-devel)
* R-hub containers, R-devel: `clang23`, `ubuntu-clang`, `ubuntu-gcc16`

## R CMD check results

0 errors | 0 warnings | 2 notes

* New submission.

* `Found '___stderrp', possibly from 'stderr' (C)` in
  `vendor/expat/xmlparse.o`.

  The only reference is an `fprintf(stderr, ...)` in Expat's `ENTROPY_DEBUG()`,
  which runs only when the user sets the environment variable
  `EXPAT_ENTROPY_DEBUG`. zuxml never sets it. We keep the bundled Expat
  byte-identical to upstream so that security updates can be applied cleanly,
  and would rather not patch it for a line that cannot run by default. We are
  happy to patch it if CRAN prefers.

On R 4.5 (r-oldrel) only, a third NOTE lists `R_GetConnection` and
`R_ReadConnection` as non-API calls. They are used by `xml_read()` to read
connections. R 4.6 lists them in the "Experimental API index" of Writing R
Extensions, so the NOTE does not appear on r-release or r-devel.
