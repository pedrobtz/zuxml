# cran-comments

## Submission

This is a new submission: zuxml 0.1.0.

zuxml reads, navigates and writes XML. It bundles the Expat parser
(<https://libexpat.github.io/>, version 2.8.4) under `src/vendor/expat/`, so
no system XML library is required, and exposes a registered C interface that
lets other packages parse XML without linking against Expat themselves.

## Test environments

* local macOS 15.7.9 (x86_64-apple-darwin20), R 4.5.2 — `R CMD check --as-cran`
* GitHub Actions on every push:
  - ubuntu-latest, R devel / release / oldrel-1
  - macOS-latest, R release
  - windows-latest, R release
* win-builder, R release — *(pending; results to be added before submission)*
* win-builder, R devel — *(pending)*
* R-hub — *(pending)*

In addition to `R CMD check`, the package's own gates run in CI on every push:
AddressSanitizer and UndefinedBehaviorSanitizer (with LeakSanitizer on Linux),
libFuzzer over three targets, a mutation check that every security guard is
load-bearing, a strict-warning build (`-Werror -Wall -Wextra -Wpedantic
-Wconversion -Wcast-qual`), a downstream fixture package that exercises the
registered C API exactly as a real consumer would, and the W3C XML Conformance
Test Suite.

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

A third NOTE appears on the maintainer's machine only — "Skipping checking
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
| 1 | Builds from source on Windows, macOS and Linux with no system Expat, CMake or autotools | CI matrix: 5 jobs across the three platforms, source installs only |
| 2 | Parsing is byte-for-byte independent of input chunk boundaries | `tests/testthat/test-chunking.R` at sizes 1, 2, 3, 7, 31, 4096 and random splits, including splits inside names, attribute values, UTF-8 sequences, entity references and CDATA markers; plus the `fuzz_feed` target choosing boundaries adversarially |
| 3 | Namespace-aware parsing is correct, including shadowing and unqualified attributes | `tests/testthat/test-namespaces.R`; W3C suite namespace cases |
| 4 | Mixed-content ordering is preserved exactly | `tests/testthat/test-tree.R`; the round-trip fuzz target |
| 5 | External entities never cause filesystem or network access | Structural: `XML_GE 0`, `XML_DTD` never defined. Behavioural: `tests/testthat/test-security.R` XXE fixtures assert no file is opened. Proven non-vacuous by `tools/run-mutation-check` |
| 6 | Every oversized or malformed input fails through an explicit classed error; none crashes, hangs or aborts on OOM | `test-limits.R`, `test-conditions.R`; 5.4M fuzz executions across three targets under ASan+UBSan; the W3C conformance gate asserts no condition escapes the `zuxml_error` contract |
| 7 | Parse errors carry line, column and byte offset in an R condition | `tests/testthat/test-conditions.R` |
| 8 | Round-trip (parse → serialize → parse) is structurally identical across the corpus | `test-serialize.R`; the `fuzz_roundtrip` target aborts on any non-fixed-point, survived 2.5M inputs |
| 9 | Fuzzing under ASan/UBSan finds no memory-safety failure in project-owned code | 5.4M executions, all clean; nightly 30-minutes-per-target run in `hardening.yaml` |
| 10 | `inst/include/zuxml.h` exposes no Expat type; a fixture package consumes the C API via Imports + LinkingTo | `tools/run-downstream-check`, which also asserts the consumer's object references zero `XML_*` symbols |
| 11 | Vendored Expat provenance is recorded and reproducible | `src/vendor/PROVENANCE`, `inst/COPYRIGHTS`, `LICENSE.note`; `tools/verify-vendor` compares byte-for-byte against the pinned upstream release |
| 12 | `R CMD check --as-cran` is clean on all three platforms | CI matrix; results above |

Two further checks beyond the criteria: the W3C XML Conformance Test Suite
(`tools/run-conformance`, 591 and 730 adjudicated cases in the two parse modes,
no unexplained deviation), and benchmarks against the design's performance
targets (`tools/run-benchmarks`).

## Downstream dependencies

None. This is a new package.
