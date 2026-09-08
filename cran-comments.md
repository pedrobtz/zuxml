# cran-comments

<!--
BEFORE SUBMITTING:
  * The pkgdown site at https://pedrobtz.github.io/zuxml/ must be live, or
    `--as-cran` reports the DESCRIPTION URL as a 404. It deploys from main.
  * Add the win-builder (release + devel) and R-hub results to "Test
    environments" below, and record any additional NOTEs they produce.
  * Delete this comment.
-->

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

In addition to `R CMD check`, the package's own gates run in CI on every push:
AddressSanitizer and UndefinedBehaviorSanitizer (with LeakSanitizer on Linux),
libFuzzer over three targets, a mutation check that every security guard is
load-bearing, a strict-warning build (`-Werror -Wall -Wextra -Wpedantic
-Wconversion -Wcast-qual`), and a downstream fixture package that exercises
the registered C API exactly as a real consumer would.

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

## Downstream dependencies

None. This is a new package.
