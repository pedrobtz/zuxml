# cran-comments

## Submission

This is a new submission: zuxml 0.1.0.

zuxml reads, navigates and writes XML. It bundles the Expat parser
(<https://libexpat.github.io/>, version 2.8.4) under `src/vendor/expat/`, so
no system XML library is required, and exposes a registered C interface that
lets other packages parse XML without linking against Expat themselves.

## Test environments

* local macOS 26.6.2 (aarch64-apple-darwin23), R 4.6.1 — `R CMD check --as-cran`
* GitHub Actions on every push and pull request:
  - R-devel in three R-hub containers — `r-hub/containers/clang23`
    (which builds C as `-std=gnu23`), `ubuntu-clang` and `ubuntu-gcc16`
  - ubuntu-latest, R release and oldrel-1
  - macOS-latest, R release
  - windows-latest, R release and R-devel

R-devel on Linux is covered by the R-hub containers rather than by a plain
R-devel runner: the runner's own toolchain matches no CRAN flavor, whereas the
containers are the compilers CRAN checks on. A diagnostic that exists only in
the newer compiler, or only under `-pedantic`, is what they are there to
surface before submission rather than after. R-hub is therefore already
exercised on every push, and no separate submission to it is reported here.

Windows R-devel is a runner row instead, since that flavor — a newer Rtools
toolchain than release, and the one CRAN's incoming pretest uses — has no
container equivalent. It is also why no win-builder result is reported
separately: the same ground is covered on every push rather than once by hand
before release.

In addition to `R CMD check`, the package's own gates run in CI on every push:
AddressSanitizer and UndefinedBehaviorSanitizer (with LeakSanitizer on Linux),
libFuzzer over three targets, a mutation check that every security guard is
load-bearing, a strict-warning build (`-Werror -Wall -Wextra -Wpedantic
-Wconversion -Wcast-qual`), a downstream fixture package that links
the installed `lib${R_ARCH}/libzuxml.a` through `LinkingTo` alone, exactly as a real
consumer does, and the W3C XML Conformance Test Suite.

## R CMD check results

0 errors | 0 warnings | 2 notes

### NOTE: New submission

Expected for a first submission.

### NOTE: Found `___stderrp`, possibly from `stderr` (C)

```
File 'zuxml/libs/zuxml.so':
  Found '___stderrp', possibly from 'stderr' (C)
    Object: 'vendor/expat/xmlparse.o'
```

This is in the bundled Expat sources, not in package-owned code, and the call
is unreachable in normal use.

The single reference is `ENTROPY_DEBUG()` in `src/vendor/expat/xmlparse.c`,
which Expat uses to trace the seeding of its hash-collision defence. Its body
is guarded:

```c
static struct sipkey
ENTROPY_DEBUG(const char *label, struct sipkey entropy_128) {
  if (getDebugLevel("EXPAT_ENTROPY_DEBUG", 0) >= 1u) {
    fprintf(stderr, ...);
  }
  return entropy_128;
}
```

`getDebugLevel()` reads the `EXPAT_ENTROPY_DEBUG` environment variable and
defaults to 0, so the `fprintf` executes only if a user deliberately sets that
variable before loading the package. Nothing in zuxml sets it, and no code
path in zuxml can reach the `fprintf` otherwise.

We have deliberately not patched it out. The vendored Expat is kept verbatim
and verified byte-for-byte against upstream by `tools/verify-vendor`, which is
what makes routine security updates safe to apply; carrying a local patch
would weaken that guarantee to remove a diagnostic that cannot fire. We are of
course happy to patch it if CRAN would prefer.

### NOTE on R 4.5 only: Found non-API calls to R: 'R_GetConnection', 'R_ReadConnection'

`xml_read()` streams a connection (a `url()`, a `gzfile()`, a socket) through
`R_ext/Connections.h`, the way iotools does. R 4.5's `R CMD check` lists
`R_GetConnection()` and `R_ReadConnection()` as non-API entry points; R 4.6
removed them from that list and 'Writing R Extensions' now lists them in its
"Experimental API index". So this NOTE appears on the r-oldrel flavours only,
and not on r-release or r-devel. The source checks `R_CONNECTIONS_VERSION`
and refuses to compile against any other version of the connections API.

A further NOTE appears on the maintainer's machine only — "Skipping checking
HTML validation: 'tidy' doesn't look like recent enough HTML Tidy" — which is
a property of that macOS install, not of the package. It does not appear on
any CI platform.

## Method references

There are no published references describing the methods in this package. It
implements XML 1.0 parsing and a document tree; the specification is the W3C
XML 1.0 Recommendation, and conformance against the W3C XML Conformance Test
Suite is checked by `tools/run-conformance`.

## Acceptance criteria

The package's design sets twelve acceptance criteria. Each is verified, and by
what:

| # | Criterion | Verified by |
|---|---|---|
| 1 | Builds from source on Windows, macOS and Linux with no system Expat, CMake or autotools | CI matrix, source installs only: 5 GitHub runners (Windows release and devel, macOS release, Ubuntu release and oldrel) plus 3 R-devel Linux containers (gcc 16, clang, clang 23) |
| 2 | Parsing is byte-for-byte independent of input chunk boundaries | `tests/testthat/test-chunking.R` at sizes 1, 2, 3, 7, 31, 4096 and random splits, including splits inside names, attribute values, UTF-8 sequences, entity references and CDATA markers; plus the `fuzz_feed` target choosing boundaries adversarially |
| 3 | Namespace-aware parsing is correct, including shadowing and unqualified attributes | `tests/testthat/test-namespaces.R`; W3C suite namespace cases |
| 4 | Mixed-content ordering is preserved exactly | `tests/testthat/test-tree.R`; the round-trip fuzz target |
| 5 | External entities never cause filesystem or network access | Structural: `XML_GE 0`, `XML_DTD` never defined. Behavioural: `tests/testthat/test-security.R` XXE fixtures assert that a `file://` or `http://` entity is refused at the `DOCTYPE`, that a canary file's contents never reach the event stream, and that a missing path fails exactly as an existing one does, so resolution is never attempted. Nothing observes system calls. Proven non-vacuous by `tools/run-mutation-check` |
| 6 | Every oversized or malformed input fails through an explicit classed error; none crashes, hangs or aborts on OOM | `test-limits.R`, `test-conditions.R`; 5.4M fuzz executions across three targets under ASan+UBSan; the W3C conformance gate asserts no condition escapes the `zuxml_error` contract |
| 7 | Parse errors carry line, column and byte offset in an R condition | `tests/testthat/test-conditions.R` |
| 8 | Round-trip (parse → serialize → parse) is structurally identical across the corpus | `test-serialize.R`, whose corpus includes the whitespace character references (`&#13;`, `&#13;&#10;`, `&#9;`) that survive end-of-line normalization; the `fuzz_roundtrip` target aborts on any non-fixed-point, survived 2.5M inputs, and it now runs every input under all four comment/PI settings, since dropping a node is what puts two text nodes next to each other in the output; `fuzz/corpus/seed21.xml` and `seed22.xml` seed both families |
| 9 | Fuzzing under ASan/UBSan finds no memory-safety failure in project-owned code | 5.4M executions, all clean; nightly 30-minutes-per-target run in `hardening.yaml` |
| 10 | `inst/include/zuxml.h` exposes no Expat type; a fixture package consumes zuxml through `LinkingTo` and the installed `lib${R_ARCH}/libzuxml.a`, with no `Imports:` entry and no run-time dependency on zuxml | `tools/run-downstream-check`, which installs the fixture against a freshly built zuxml, asserts that no Expat symbol is left undefined for the loader to satisfy, and asserts the fixture still parses with zuxml absent from the library path |
| 10b | A fixture consumes the registered table through `Imports:` + `LinkingTo:` + `importFrom()` and calls every member | `tools/run-downstream-check`: `tools/zuxmltable` calls all 26 members, with identical results at every chunk size, and links no Expat symbol. A frozen copy of the table's 0.1.0 layout fails its build if a member moves. The same gate compiles `zuxml.h` as C and C++ under `-Wall -Wextra -Werror` |
| 11 | Vendored Expat provenance is recorded and reproducible | `src/vendor/PROVENANCE`, `inst/COPYRIGHTS`, `LICENSE.note`; `tools/verify-vendor` compares byte-for-byte against the pinned upstream release |
| 12 | `R CMD check --as-cran` is clean on all three platforms | CI matrix; results above |

Two further checks beyond the criteria: the W3C XML Conformance Test Suite
(`tools/run-conformance`, 591 and 730 adjudicated cases in the two parse modes,
no unexplained deviation), and benchmarks against the design's performance
targets (`tools/run-benchmarks`).

## Downstream dependencies

None. This is a new package.
