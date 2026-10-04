## Resubmission

This is a resubmission. The previous upload (2026-09-25) was archived by the
incoming pretest because of

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
and no other change. Its copyright holders are listed in `Authors@R` and
`inst/COPYRIGHTS`.

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
