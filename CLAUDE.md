# zuxml

Read this first, then [.agents/zuxml-design.md](.agents/zuxml-design.md) for the
reasoning behind any decision below. [.agents/roadmap.md](.agents/roadmap.md) is
the stage-by-stage history, including what went wrong and what was learned —
check it before re-litigating a choice.

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

## Current state (2026-09-22)

Version 0.1.0, not yet on CRAN. The **Status:** line under each stage in the
roadmap is authoritative; this is the summary.

* Stages 0–6 are complete. Stage 6's table criteria went unverified from
  f3392b2, which retargeted the only fixture at the archive, until #36 added
  `tools/zuxmltable` beside it.
* Stage 7 (#32) is open. The interrupt criterion is unverified but
  automatable (#37). The 24h-per-target fuzzing criterion is not met yet;
  the grown corpus is cached between CI runs, so fuzzing time accumulates.
* Stage 8 (#33) is complete. Its one open box is an optional win-builder
  R-devel run.
* Stage 9 (#34) is blocked on #40 and #44.
* **Consumers:** `zuxlsx` is the only one, and it uses the archive. The
  registered table has no consumer yet — `zuhttp` plans no XML support — so
  `tools/zuxmltable` stands in for one and calls all 26 members.
* An archive consumer does not inherit the seam's DOCTYPE rejection or its
  limits (#41).
* Progress is tracked in #24 (v0.1.0): one `stage`-labelled sub-issue per
  roadmap stage (#25–#34), each linking to its stage's heading anchor. That is
  why status stays out of the headings.

## Feature policy — non-negotiable

`src/expat_config.h` is project-owned and is the only place local configuration
lives. Everything under `src/vendor/expat/` is byte-identical to the pinned
upstream release; `tools/verify-vendor` enforces that and CI runs it.

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

|                   | table (`zuxml_api`)             | archive (`libzuxml.a`)        |
|-------------------|---------------------------------|-------------------------------|
| Consumer declares | `Imports:` **and** `LinkingTo:` | `LinkingTo:` only             |
| `NAMESPACE`       | an `importFrom()` is required   | nothing                       |
| Header            | `inst/include/zuxml.h`          | `expat.h`, installed          |
| Resolved          | `R_GetCCallable()`, at run time | linked into the consumer      |
| Needs zuxml live  | yes, installed **and** loaded   | no, not even installed        |

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

## Layout

```
R/                 parse.R, node.R, nodeset.R, events.R, write.R, conditions.R, info.R
src/               init.c, r_api.c, r_document.c   R-facing glue
                   zux_parser.c, zux_tree.c, zux_write.c   core, no R in it
                   zux_register.c   R_RegisterCCallable, the zuxml_api table
                   expat_config.h, install.libs.R, Makevars, vendor/expat/
inst/include/      zuxml.h — the only header in the sources
tools/             gates and maintenance scripts, plus zuxmltest/ and zuxmltable/
.agents/           design document and roadmap
```

The core (`zux_parser.c`, `zux_tree.c`, `zux_write.c`) contains no R. Keep it
that way: it is what the sanitizer and fuzz drivers compile standalone.

## Commands

```sh
Rscript -e 'devtools::document()'   # roxygen -> NAMESPACE + man/
Rscript -e 'devtools::load_all()'   # compile + load for interactive work
Rscript -e 'devtools::test()'
Rscript -e 'devtools::check()'      # full R CMD check
R CMD INSTALL .                     # an installed layout, for test-linking.R
```

`tests/testthat/test-linking.R` audits the *installed* package
(`lib/libzuxml.a`, `include/expat.h`), so it skips under `load_all()`. It has
teeth only under `R CMD check` or against a real install, and there a missing
artifact fails rather than skips: whether the layout is installed is read from
`Meta/package.rds`, never from the artifact under test.

## Gates

Run these from the package root. All but `tools/run-benchmarks` and
`tools/update-expat` are wired into CI (`.github/workflows/`: `R-CMD-check`,
`hardening`, `native-checks`, `coverage`, `pkgdown`). The benchmarks are
deliberately not, since shared-runner timings are too noisy to gate on, and
`update-expat` is a maintenance script.

| script                     | what it proves                                        |
|----------------------------|-------------------------------------------------------|
| `tools/run-lint`           | project-owned code compiles warning-free (`-Werror`)  |
| `tools/verify-vendor`      | `src/vendor/expat` matches the pinned release exactly |
| `tools/run-sanitizers`     | the event seam under ASan + UBSan, no R in the way    |
| `tools/run-fuzz`           | libFuzzer over the parser seam, after a canary that must crash |
| `tools/run-mutation-check` | each security guard is load-bearing                   |
| `tools/run-conformance`    | the W3C XML Conformance Test Suite                    |
| `tools/run-downstream-check` | both consumption modes work for a real consumer package |
| `tools/run-benchmarks`     | the design §21 performance targets                    |
| `tools/update-expat <ver>` | re-vendor Expat (then re-run `verify-vendor`)         |

Two traps when running them by hand:

* `tools/zuxmltest/cleanup` uses paths relative to the current directory.
  Run it as `(cd tools/zuxmltest && ./cleanup)` — from the package root it
  deletes zuxml's own `src/Makevars`.
* A developer machine that also works on `zuxlsx` has zuxml in its **user**
  library, and `R_LIBS` does not hide it. `tools/run-downstream-check` points
  `R_LIBS_USER`/`R_LIBS_SITE` at nothing for that reason; anything else
  resolving `system.file(package = "zuxml")` in a test needs the same care.

## Definition of done

* A stage is done when its exit criteria pass in CI on all three platforms,
  not when the code is written. A criterion met differently from how it is
  worded goes in the stage's **Status:** line. So does one that a later
  change invalidates: re-check a closed stage when you touch its subject.
* A gate counts once it has been seen to fail — a deliberate warning, a
  removed guard, a target that must crash. `tools/run-lint` and
  `tools/run-fuzz` both passed vacuously until someone checked (#35).
* A change to a contract (`zuxml.h`, the table, the archive layout, the
  feature policy) amends the design in the same commit.
* `devtools::document()` leaves no diff, and `R CMD check --as-cran` shows only
  the NOTEs that `cran-comments.md` explains. A user-facing change also needs
  a test, roxygen documentation and a `NEWS.md` entry.

## Conventions

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
* Expat and its notices are redistributed here: `inst/COPYRIGHTS`,
  `src/vendor/PROVENANCE`, `LICENSE.note`. Static linking in a consumer
  redistributes them too.
