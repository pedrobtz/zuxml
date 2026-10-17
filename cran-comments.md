## Resubmission

This is a resubmission. In response to the review of 0.1.0, `Authors@R` now
names the authors of the bundled Expat sources as listed in Expat's own
AUTHORS file
(<https://raw.githubusercontent.com/libexpat/libexpat/R_2_8_4/expat/AUTHORS>),
and the authors of the bundled SipHash header, all as `ctb`. As the CRAN
policy allows, the copyright holders are given through the `Copyright`
field, which refers to `inst/COPYRIGHTS`: it lists Expat's copyright
notices and every one of the 60 individuals and the organisations named in
the copyright lines of the bundled source files.

Earlier, the 2026-09-25 upload was archived by the incoming pretest because of

    Found 'stderr', possibly from 'stderr' (C)
      Object: 'vendor/expat/xmlparse.o'

The only reachable reference was a debug-only `fprintf(stderr, ...)` in
Expat's `ENTROPY_DEBUG()`. It is now removed by a local patch to the bundled
Expat, recorded in `src/vendor/PROVENANCE`. No compiled object in the package
references `stderr`, `stdout` or `printf` any more.

## Submission

This is a new submission.

zuxml bundles the Expat XML parser, version 2.8.4
(<https://libexpat.github.io/>), in `src/vendor/expat/`, with that one patch
and no other change. Its authors are listed in `Authors@R` and its copyright
holders in `inst/COPYRIGHTS`.

## Test environments

* local macOS 26.6.2, R 4.6.1
* GitHub Actions: ubuntu-latest (R release, oldrel-1), macOS-latest (R
  release), windows-latest (R release, R-devel)
* R-hub containers, R-devel: `clang23`, `ubuntu-clang`, `ubuntu-gcc16`

## R CMD check results

0 errors | 0 warnings | 1 note

* New submission.

On R 4.5 (r-oldrel) only, a second NOTE lists `R_GetConnection` and
`R_ReadConnection` as non-API calls. They are used by `xml_read()` to read
connections. R 4.6 lists them in the "Experimental API index" of Writing R
Extensions, so the NOTE does not appear on r-release or r-devel.
