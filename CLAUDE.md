# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/native-code.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

An R package that reads, navigates and writes XML using a **vendored copy of
Expat** (`src/vendor/expat/`), so no system XML library is required. The R side
is a vectorized navigation interface over an immutable tree
(`xml_parse()`/`xml_read()`, `xml_children()`, `xml_find()`, `xml_text()`,
`xml_serialize()`). Parsing is strict and secure by default.

Two things make this package unusual, and most mistakes come from missing one of
them: the parser's **feature policy is deliberately stricter than a distro
Expat**, and zuxml is a **provider for other packages' C code**, with two
distinct consumption modes that are easy to confuse.

Read this first, then [.agents/zuxml-design.md](.agents/zuxml-design.md) for
the reasoning behind any decision below; the design outranks this file.
[.agents/roadmap.md](.agents/roadmap.md) is the stage-by-stage history,
including what went wrong and what was learned. Check it before
re-litigating a choice.

## Current state

Verified 2026-11-11: 0.1.0 is on CRAN, published 2026-10-27 and tagged
`0.1.0`; `main` is at `0.1.0.9000`. The **Status:** line under each stage in
the roadmap is authoritative for the road to 0.1.0; this is the summary.

* The first 0.1.0 submission (2026-09-25) was archived by CRAN's automatic
  pretest for the `stderr` NOTE from vendored Expat, which Stage 8 had chosen
  to justify rather than patch. Patched in #72.
* Stage 6's table criteria went unverified from f3392b2, which retargeted the
  only fixture at the archive, until #36 added `tools/zuxmltable` beside it.
* Stage 7's remaining items (cumulative fuzzing hours, MSan, clang-tidy,
  three fuzz targets) are #54, now planned for v0.1.1. The grown fuzz corpus
  is cached between CI runs, so fuzzing time accumulates.
* No win-builder run is needed: the `windows-latest`/R-devel row in
  `R-CMD-check.yaml` covers that flavor on every push.
* The R API has 24 exports: `xml_table()`, `xml_list()` (#57) and
  `xml_find_first()` (#59) were added for 0.1.0 after the 2026-09-22 review.
  `xml_find_first()` introduced the *missing node*, whose contract (every
  accessor gives `NA`) is in the design and is breaking to change later.
* An archive consumer does not inherit the seam's DOCTYPE rejection or its
  limits (#41).

## Versions and dependents

The current version's parent issue is
[v0.1.1 (#82)](https://github.com/pedrobtz/zuxml/issues/82); the 0.1.0 one
was #24, with one `stage`-labelled sub-issue per roadmap stage (#25–#34),
each linking to its stage's heading anchor. That is why status stays out of
the headings.

**Consumers:** `zuxlsx` is the only one, and it uses the archive. The
registered table has no consumer yet (`zuhttp` plans no XML support), so
`tools/zuxmltable` stands in for one and calls all 26 members.

## Feature policy — non-negotiable

`src/expat_config.h` is project-owned and is the only place local configuration
lives. Everything under `src/vendor/expat/` is the pinned upstream release
plus exactly the patches in `tools/patches/`; `tools/verify-vendor` enforces
that and CI runs it. The one patch removes Expat's only surviving `stderr`
write, which CRAN's pretest rejected (#72); `tools/check-no-stdio` keeps it
out. Patch only for a reason like that: every patch is carried through every
Expat update.

* `XML_GE 0`, and `XML_DTD` is **never** defined. General entities, parameter
  entities, external subsets and the external-entity machinery are compiled
  *out*, so XXE and entity amplification are impossible rather than switched
  off. The accepted cost: any entity reference beyond the five built-ins and
  numeric character references is a hard parse error.
* `XML_NS 1`, `XML_CONTEXT_BYTES 1024`. `XML_UNICODE`, `XML_LARGE_SIZE` and
  `XML_ATTR_INFO` are not defined, so `XML_Char` is `char` and input is UTF-8.
* `BYTEORDER` and the entropy source are **derived from compiler macros** and
  `#error` on an unknown platform rather than guessing. Never copy a generated
  `expat_config.h` from another machine, and never define `XML_POOR_ENTROPY`.

`tools/run-mutation-check` exists to prove the security guards are not
vacuous: removing a guard must change what its hostile input produces. It
checks that through `tools/mutation/probe.c`, not by re-running the testthat
suite against the mutant.

## Consumers — two modes, do not conflate

<!-- markdownlint-disable MD013 -->
|                   | table (`zuxml_api`)             | archive (`libzuxml.a`)        |
|-------------------|---------------------------------|-------------------------------|
| Consumer declares | `Imports:` **and** `LinkingTo:` | `LinkingTo:` only             |
| `NAMESPACE`       | an `importFrom()` is required   | nothing                       |
| Header            | `inst/include/zuxml.h`          | `expat.h`, installed          |
| Resolved          | `R_GetCCallable()`, at run time | linked into the consumer      |
| Needs zuxml live  | yes, installed **and** loaded   | no, not even installed        |
<!-- markdownlint-enable MD013 -->

**The table** is the path for new C code. It has no real consumer yet;
`tools/zuxmltable` calls every member on every push, and a frozen copy of the
0.1.0 layout there fails its build if a member moves. `Imports:` alone
is not enough — `R_GetCCallable()` resolves nothing until zuxml's namespace is
*loaded*, which needs an actual import directive in the consumer's
`NAMESPACE`. The registered callable **name** (`zuxml_api_v2`) versions every
public type, and `struct_size` versions the table itself; appending a member
is safe, changing the layout of `zux_error`/`zux_options`/`zux_name` means
bumping the name. R does not rebuild `LinkingTo` dependents on upgrade, so
that name is what stands between `install.packages("zuxml")` and memory
corruption downstream. No Expat type may ever appear in `zuxml.h`.

**The archive** is for C code already written against Expat and not worth
rewriting — `xlsxio` in `zuxlsx` is the case that prompted it. It needs
`XML_GetBuffer`/`XML_StopParser`/`XML_ResumeParser`, which the table cannot
express. `src/Makevars` builds it from `EXPAT_OBJECTS` only: keep R glue out,
or a consumer gets dead weight and duplicate symbols. `src/install.libs.R`
installs it to `<pkg>/lib/` and copies `expat.h`/`expat_external.h` out of the
vendored tree to `<pkg>/include/` — deliberately *not* a second copy under
`inst/include/`, which could drift from the sources the archive was compiled
from. Defining `install.libs.R` means R stops installing the shared object
itself, so its first block is load-bearing, not boilerplate.

`vignette("linking")` is the consumer-facing write-up of the archive mode.
`tools/zuxmltest/` is a worked example of it and `tools/zuxmltable/` of the
table, and `tools/run-downstream-check` is the gate for both.

## Architecture

<!-- markdownlint-disable MD013 -->
```text
R/                 parse.R, node.R, nodeset.R, events.R, write.R, conditions.R, info.R
                   zu_source.R   input dispatch, copied verbatim to sibling packages
src/               init.c, r_api.c, r_document.c   R-facing glue
                   zu_source.h   header-only byte source, copied verbatim to sibling packages
                   zux_parser.c, zux_tree.c, zux_write.c   core, no R in it
                   zux_register.c   R_RegisterCCallable, the zuxml_api table
                   expat_config.h, install.libs.R, Makevars, vendor/expat/
inst/include/      zuxml.h — the only header in the sources
tools/             gates and maintenance scripts, plus zuxmltest/ and zuxmltable/
.agents/           design document and roadmap
```
<!-- markdownlint-enable MD013 -->

The core (`zux_parser.c`, `zux_tree.c`, `zux_write.c`) contains no R. Keep it
that way: it is what the sanitizer and fuzz drivers compile standalone.

## Commands

The everyday `devtools` loop is in `.claude/shared/r-package.md`.

```sh
R CMD INSTALL .                     # an installed layout, for test-linking.R
```

`tests/testthat/test-linking.R` audits the *installed* package
(`lib${R_ARCH}/libzuxml.a`, `include/expat.h`), so it skips under
`load_all()`. It has teeth only under `R CMD check` or against a real
install, and there a missing artifact fails rather than skips: whether the
layout is installed is read from `Meta/package.rds`, never from the artifact
under test.

### Gates

Run these from the package root. All but `tools/run-benchmarks` and
`tools/update-expat` are wired into CI (see Continuous integration). The
benchmarks are deliberately not, since shared-runner timings are too noisy to
gate on, and `update-expat` is a maintenance script.

<!-- markdownlint-disable MD013 -->
| script                       | what it proves                                                                                        |
|------------------------------|-------------------------------------------------------------------------------------------------------|
| `tools/run-lint`             | project-owned code compiles warning-free (`-Werror`)                                                  |
| `tools/verify-vendor`        | `src/vendor/expat` is the pinned release plus `tools/patches/`, exactly                               |
| `tools/check-no-stdio`       | no compiled object references `stderr`/`stdout`/`printf`                                              |
| `tools/check-authors`        | every person Expat's copyright lines name is in `inst/COPYRIGHTS`, and its AUTHORS in `Authors@R` too |
| `tools/run-sanitizers`       | the event seam under ASan + UBSan, no R in the way                                                    |
| `tools/run-fuzz`             | libFuzzer over the parser seam, after a canary that must crash                                        |
| `tools/run-mutation-check`   | each security guard is load-bearing                                                                   |
| `tools/run-conformance`      | the W3C XML Conformance Test Suite                                                                    |
| `tools/run-downstream-check` | both consumption modes work for a real consumer package                                               |
| `tools/run-benchmarks`       | the design §21 performance targets                                                                    |
| `tools/update-expat <ver>`   | re-vendor Expat (then re-run `verify-vendor`)                                                         |
<!-- markdownlint-enable MD013 -->

One trap when running them by hand:

* A developer machine that also works on `zuxlsx` has zuxml in its **user**
  library, and `R_LIBS` does not hide it. `tools/run-downstream-check` points
  `R_LIBS_USER`/`R_LIBS_SITE` at nothing for that reason; anything else
  resolving `system.file(package = "zuxml")` in a test needs the same care.

## Invariants that are easy to break

* **Portable make only** in `src/Makevars`: no GNU-make conditionals, no
  `$(shell ...)`, no `-W*` overrides. Any of them costs
  `SystemRequirements: GNU make` or a CRAN rejection.
* **Errors are classed conditions**, not bare `stop()` — see `R/conditions.R`.
  In C, avoid `Rf_error()` where a resource is held: it longjmps past every
  `free()`.
* Strings in handlers are **borrowed and not NUL-terminated**; strings from
  document accessors are **owned by the document and NUL-terminated**. This
  contract is stated at the top of `zuxml.h` and is the source of every memory
  bug if ignored.
* `vignettes/articles/` is pkgdown-only and `.Rbuildignore`d; `vignettes/*.Rmd`
  is built *and executed* by `R CMD check`, including under the sanitizers.

## Definition of done, beyond the shared one

* A stage is done when its exit criteria pass in CI on all three platforms,
  not when the code is written. A criterion met differently from how it is
  worded goes in the stage's **Status:** line. So does one that a later
  change invalidates: re-check a closed stage when you touch its subject.
* A gate counts once it has been seen to fail — a deliberate warning, a
  removed guard, a target that must crash. `tools/run-lint` and
  `tools/run-fuzz` both passed vacuously until someone checked (#35).
* A change to a contract (`zuxml.h`, the table, the archive layout, the
  feature policy) amends the design in the same commit.

## Continuous integration

* `R-CMD-check.yaml` calls `r-cmd-check.yml@v1` with one row added to the
  default runners, Windows on R-devel (CRAN's incoming flavour), plus the
  CRAN-like containers. It drops the plain Ubuntu R-devel row and
  `upload-snapshots` on purpose; the file says why.
* `hardening.yaml` holds the gates R CMD check cannot express, with no R in
  the way: strict warnings, no-stdio and author checks with their canaries,
  ASan + UBSan + LSan on the seam, mutation testing, the downstream check,
  and libFuzzer, with a long fuzz run nightly.
* `native-checks.yaml` calls r-actions' `vendor`, `sanitizers`, `valgrind`,
  `lto`, `gctorture`, `rchk` and `cran-special` workflows: the instrumented
  runs through R, and the only place the R-facing sources are instrumented.
* `coverage.yaml` calls `coverage.yml`, pinned to a commit (`v1.18.0`);
  `pkgdown.yaml` builds the site, and on `develop` only proves the articles
  knit.

**Deviation from `.claude/shared/ci.md`, as of 2026-11-11:** no workflow
calls `changes.yml`. `hardening.yaml`, `native-checks.yaml` and
`coverage.yaml` skip prose-only changes with `paths-ignore`, and
`R-CMD-check.yaml` deliberately has none, because `--as-cran` checks the URLs
in `README.md`, which ships in the tarball. #51 plans the CI rework.

## Vendored native code

Expat (libexpat) 2.8.4, MIT, release tag `R_2_8_4`, imported 2026-09-08 from
the release tarball, whose SHA-256 is in `src/vendor/PROVENANCE`. 2.8.4 is
the floor because it is a security release; `PROVENANCE` says why. Only the
parser library is imported, the files listed in `tools/expat-files.txt`.
Build configuration is not vendored: it is the project-owned
`src/expat_config.h` (see Feature policy). The one local patch is
`tools/patches/0001-no-stdio-entropy-debug.patch`.

* **Expat's AUTHORS are in `Authors@R`** (`ctb`), and **every individual
  named in a vendored copyright line is in `inst/COPYRIGHTS`**, which the
  `Copyright:` field points to. CRAN's review of 0.1.0 asked for them by
  name; listing all 60 in `Authors@R` was judged too much.
  `tools/check-authors` fails a re-vendor that brings in a new name until
  the right file is updated.
* Expat and its notices are redistributed here: `inst/COPYRIGHTS`,
  `src/vendor/PROVENANCE`, `LICENSE.note`, and Expat's `COPYING`, which
  `install.libs.R` installs as `licenses/expat-COPYING`. That copy is a
  licensing obligation: an installed zuxml carries Expat compiled and as
  `expat.h`, and nothing outside `inst/` is installed otherwise. Static
  linking in a consumer redistributes them too.
