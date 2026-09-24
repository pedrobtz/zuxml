# zuxml — Roadmap to 0.1.0 (first CRAN release)

Companion to [zuxml-design.md](zuxml-design.md). Section references (§) point there.

## Sequencing principles

1. **Security policy lands before the tree.** DOCTYPE rejection, limits, and the no-DTD build are enforced at the event seam (§3, §11). Building the tree first means retrofitting limits into code that already assumes they hold — that is how limit bugs get shipped.
2. **The serializer lands before the hardening stage.** It is the round-trip test oracle (§13); every stage after it gets a stronger test suite for free.
3. **Every stage ends with something runnable and tested.** No stage is "write three files, test later."
4. **Portability is proven at Stage 1, not discovered at Stage 8.** The Expat vendoring traps (§18) are the single largest schedule risk, and they surface on Windows.
5. **A stage is done when its exit criteria pass in CI on all three platforms**, not when the code is written.

Sizes are relative: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is the week.

**"v1" means the first release's scope**, here and in the design. That release ships as 0.1.0 (Stage 9); 1.0.0 comes later.

**Status never goes in a heading — issue links use the anchors.** A heading is `## Stage N — Title · Size` and nothing else; a stage's state is the **Status:** line directly under it. Status words in a heading change its GitHub anchor, which silently breaks every issue that links to the stage.

---

## Stage 0 — Repo hygiene · S

**Status:** complete.

The package arrived as the `usethis` template; cleared before building on it.

- `DESCRIPTION` filled in: real `Title`, `Description`, `Authors@R` (Pedro Baltazar, `aut`/`cre`/`cph`), `URL`, `BugReports`, `Depends: R (>= 4.1)`.
- `LICENSE` and `LICENSE.md` name a real copyright holder instead of "zuxml authors".
- `.Rbuildignore` extended with `^\.agents$` and `^tools$`.
- `design-zuxml.md` deleted, superseded by the consolidated design.
- Initial commit made, so the Stage 1 Expat import lands as a reviewable diff against a clean baseline.
- CI: the matrix was **already** correct (windows/macos/ubuntu x release, ubuntu x devel and oldrel-1). The real gap was the trigger — it fired only on `main`/`master` while work happens on `develop`, so nothing ran at all. Fixed.

Two further fixes, found only by actually running the check rather than by planning:

- `src/init.c` with `R_registerRoutines()` / `R_useDynamicSymbols(dll, FALSE)` / `R_forceSymbols(dll, TRUE)`, replacing the symbol-less `usethis` stub — otherwise `R CMD check` NOTEs on unregistered native routines. Registration is therefore correct from the first commit instead of being retrofitted at Stage 1. `NAMESPACE` regenerated to `useDynLib(zuxml, .registration = TRUE)`.
- `tests/testthat/test-init.R` — `tests/testthat.R` with an empty `testthat/` directory is a hard check **ERROR**, and the empty directory is silently dropped at build time.

**Exit:** `R CMD check --as-cran` passes with 2 NOTEs, neither a package defect: the development version string `0.0.0.9000` (clears at release) and a local HTML Tidy version warning (environmental; absent on CI). Verified on macOS; CI covers the other platforms.

---

## Stage 1 — Vendor Expat and prove it builds · L

**Status:** complete.

The highest-risk stage. Do not proceed until it is genuinely green on Windows.

**Do**
- Import Expat 2.7.x (floor 2.7.1, CVE-2024-8176 — verify the current release) into `src/vendor/expat/`. Parser sources only: `xmlparse.c`, `xmltok*.c`, `xmlrole.c`, headers, `COPYING`. No `xmlwf`, examples, tests, benchmarks, CMake, or autotools.
- Write the project-owned configuration header (§18) — it landed as `src/expat_config.h`, see below: `XML_Char = char`, `XML_NS` on, **`XML_DTD` off**, `XML_CONTEXT_BYTES = 1024`.
- Solve the three traps (§18) *here*:
  - `BYTEORDER` derived from `__BYTE_ORDER__` / `_WIN32` / `__BIG_ENDIAN__`, with `#error` on the unknown case. Never copy a generated `expat_config.h`.
  - Entropy probe: `getrandom` / `arc4random_buf` / `RtlGenRandom`, with a compile-time `#error` on an unknown platform. Never `XML_POOR_ENTROPY` (design §11).
  - `src/Makevars` with no GNU-make-only syntax and no `-Wno-*` overrides.
- `src/init.c` with `R_useDynamicSymbols(dll, FALSE)` and one smoke entry point that creates and frees a parser.
- `tools/update-expat` and `tools/verify-vendor`; write `src/vendor/PROVENANCE` (one level above the vendored tree, so the tree itself stays byte-identical to upstream).
- **Licensing and attribution.** CRAN policy requires copyright held by anyone other than the package authors to be declared. Expat's `COPYING` names three holders; the notice is, verbatim:

      Copyright (c) 1998-2000 Thai Open Source Software Center Ltd and Clark Cooper
      Copyright (c) 2001-2025 Expat maintainers

  Add all three as `cph` in `Authors@R`, each with a `comment` naming the bundled component; write `inst/COPYRIGHTS` recording zuxml's and Expat's notices separately; keep Expat's unmodified `COPYING` in the vendor tree; write `LICENSE.note`. This is deliberately **not** done before Stage 1 — declaring copyright holders for code the package does not yet contain would be false.
- `zuxml_info()` reporting the Expat version and the compiled-in policy.

**Exit**
- Installs from source on Windows, macOS, and Linux with no system Expat, no CMake, no autotools.
- `tools/verify-vendor` reproduces the committed tree from the pinned release.
- `zuxml_info()` reports `DTD: disabled`, `External entities: unavailable`.
- `Authors@R` lists the three Expat copyright holders; `inst/COPYRIGHTS`, `LICENSE.note`, and `src/vendor/expat/COPYING` are present.
- `R CMD check --as-cran` clean.

**Trap:** if Windows fights the entropy probe, fix the probe — never fall back to `XML_POOR_ENTROPY`. An unknown platform is a compile error (`src/expat_config.h`), and `XML_SetHashSalt` is not a mitigation: Stage 2 deliberately does not call it (design §11).

**What actually happened**

- Pinned **2.8.4**, not the 2.7.1 the design assumed — four minor releases had shipped, the newest a security release fixing 4 CVEs. Checking upstream rather than trusting the plan was the whole value of that step.
- `XML_GE` must be *defined as `0`*, not left undefined: Expat tests `XML_GE == 1`, and enforces with its own `#error` that `XML_DTD` stays undefined when it is 0. Stronger than the design specified — general-entity machinery is gone entirely.
- The 2.8.x entropy backends live in separate `random_*.c` files that are **not** self-guarded, so they cannot all be compiled. A fixed, portable `OBJECTS` list therefore needs `src/zux_expat_random.c`, a shim that `#include`s exactly one of them.
- Deliberately **not** probing `__GLIBC__` to prefer `getrandom()` over the raw syscall: that needs `<features.h>` from a header included before the `random_*.c` files set `_DEFAULT_SOURCE` / `_POSIX_C_SOURCE`, which would freeze glibc's feature exposure at the wrong level. Linux uses `HAVE_SYSCALL_GETRANDOM`, which works on every libc.
- Build configuration is kept **outside** the vendor tree (`src/expat_config.h`, not `src/vendor/expat/expat_config.h` as the design sketched), so `src/vendor/expat/` stays byte-identical to upstream and `tools/verify-vendor` can prove it.
- `R CMD build` cleans only `src/` top level, so vendored `*.o` from a local install leaked into the tarball. Fixed with `.Rbuildignore` patterns.
- Compiled with **zero warnings** on the first attempt on macOS; Linux (release, devel, oldrel-1) also passed first time.
- **Windows failed**, exactly as the stage predicted — and on a fourth trap the design had not named. Expat's `internal.h` picks MSVC-style `"%I64x"` printf formats whenever `_WIN32` is set and `__USE_MINGW_ANSI_STDIO` is not; Rtools' GCC 14 rejects them under `-Wformat`, which R CMD check raises to a WARNING and CI treats as failure. Fixed with `-D__USE_MINGW_ANSI_STDIO=1` in `Makevars`, a macro Expat supports explicitly, so the vendor tree stays byte-identical. Everything else on Windows — install, load, tests — had already passed.
- Both the Windows warning and the macOS `___stderrp` NOTE originate in the *same* function, Expat's `ENTROPY_DEBUG`. That makes a small `tools/patches/` patch removing it more attractive at Stage 8 than it first appeared: one patch would close two findings.

**Carried to Stage 8:** `R CMD check --as-cran` NOTEs `___stderrp` in `xmlparse.o`. `XML_GE 0` already removed five of Expat's six `stderr` sites; the survivor is `ENTROPY_DEBUG`, debug-only behind `getenv("EXPAT_ENTROPY_DEBUG")`. Decide then between a documented `tools/patches/` patch and an explanation in `cran-comments.md` — not now, since a patch would add maintenance cost to every Expat update before there is even a parser.

---

## Stage 2 — Event seam and security policy · L

**Status:** complete. One criterion is met more weakly than written: the XXE fixture is asserted by a canary file never reaching the event stream (`tests/testthat/test-security.R`), not at the syscall level. `cran-comments.md` still claims the stronger form ("assert no file is opened") and needs the same correction.

The core of the package. Everything downstream is a consumer of what this stage defines.

**Do**
- `src/zux_parser.c` — implement `zux_parser_new/feed/finish/free` and `zux_parser_error` (§14) over Expat.
- Namespace handling: `XML_ParserCreateNS` with `\f`, `XML_SetReturnNSTriplet(TRUE)`, and the **split-from-the-right** logic (§8). Write the URI-contains-separator test at the same time as the splitter, not after.
- Security policy at the seam: `XML_SetStartDoctypeDeclHandler` → `ZUX_ERR_DOCTYPE`; all five limits with the §11 defaults, `max_text` enforced **on each coalescing append**. Do *not* call `XML_SetHashSalt` — Expat's automatic salt already uses the Stage 1 entropy backend and overriding it can only weaken it.
- Cancellation: handlers return `zux_status`; non-`ZUX_OK` triggers `XML_StopParser` and unwinds through C. No R API is reachable from a handler.
- `zux_options_init()` filling in the documented defaults.
- Text coalescing into a bounded buffer at the seam.

**Exit**
- The XXE fixture (§20) errors with **no file opened** — assert at the syscall level where the platform allows.
- Billion-laughs fixture errors at the DOCTYPE, before any expansion.
- Each of the five limits trips its own distinct status on a targeted fixture; none crashes or OOMs.
- Chunk-independence harness passes at 1/2/3/7/31/4096 bytes and random boundaries, asserting identical event sequences — with forced splits inside UTF-8 sequences, entity refs, CDATA markers, and attribute values.
- Cancellation from every handler returns `ZUX_ERR_CANCELLED` and frees the parser (ASan-clean).
- `zux_parser_error()` returns correct line/column/byte offset for a malformed fixture.

**What actually happened**

- 469 tests pass; `R CMD check --as-cran` holds at the same 3 NOTEs as Stage 1. `tools/run-sanitizers` drives 1279 parses through ASan+UBSan with zero findings.
- **A real defect was found and fixed in `allow_doctype = TRUE`.** With `XML_GE 0` Expat does not record entity declarations, and a reference to an undeclared entity in a document that *has* a DTD is passed through as **literal text** — `&e;` arrived as four characters of content instead of an error. No XXE, but silently wrong content, and a later serialize would re-escape it to `&amp;e;`. `XML_SetSkippedEntityHandler` does not fire on that path.
- The fix keys on `has_internal_subset`, which Expat hands to the DOCTYPE handler and the first implementation ignored: an internal subset is now rejected **even when `allow_doctype` is set**, since it is the only place a document can declare entities. Bare and `PUBLIC`/`SYSTEM` DOCTYPEs — what real feeds actually carry — are still accepted, so the option stays useful. Entity bombs need an internal subset, so they fall to the same rule.
- `XML_ERROR_BAD_CHAR_REF` was initially mapped to `ZUX_ERR_ENCODING`. It is a well-formedness violation, not an encoding fault; remapped to `ZUX_ERR_INVALID_XML`.
- The namespace-separator argument holds up empirically: `0x0C` is rejected by Expat both literally and as `&#12;`, so the triplet split is unambiguous. Both cases are now permanent tests.
- macOS ASan has no LeakSanitizer, so **leak coverage still comes only from Linux** — carried to Stage 7 rather than claimed here.

---

## Stage 3 — Tree builder · M

**Status:** complete.

**Do**
- `src/zux_tree.c` — the three growable arrays, name interning with an open-addressed hash, and `zux_tree_parse` (§5). Iterative construction and iterative free; no recursion anywhere.
- Node accessors (`zux_root`, `zux_parent`, `zux_first_child`, `zux_next_sibling`, `zux_node_name`, `zux_node_text`, `zux_attr_count`, `zux_attr_at`).
- Enforce the document-string contract: strings from document accessors are NUL-terminated and live as long as the document, unlike handler strings (§14).
- `max_memory` checked at every array growth.

**Exit**
- A 100k-node fixture builds and frees ASan- and UBSan-clean.
- A 100k-deep fixture fails with `ZUX_ERR_DEPTH_LIMIT` and no stack overflow — verified with a small stack rlimit.
- Mixed content preserves order exactly.
- Name interning verified: a fixture with 50k elements over 12 distinct names allocates ~12 qname entries.
- Memory within the §21 budget (~40 bytes/node + text + 12 bytes/attribute).

**What actually happened**

- Went in clean, no design changes needed — the index-addressed layout from §5 worked as specified on the first attempt.
- The tree is built as an ordinary consumer of `zux_handlers`, with no privileged access to Expat, so the seam really is the boundary the design claims and an HTML producer could reuse everything above it.
- Interning verified: 100,002 nodes over 11 element names plus one attribute name and a root collapse to **13 distinct qnames**. 50k elements parse in ~0.04 s.
- Measured **~63 bytes/node** on a mixed element+text+attribute document, consistent with the ~40 bytes/node plus text and attributes budget.
- `tools/run-sanitizers` now also builds, walks and frees trees (1344 parses, ASan+UBSan clean) and separately builds a **100k-deep document under a 1 MB stack** without sanitizers, proving construction, traversal and teardown are all genuinely iterative. A recursive implementation crashes that test.
- Test suite is 507 assertions; `R CMD check` holds at the same 3 NOTEs.

---

## Stage 4 — R document and node API · M

**Status:** complete. The interrupt criterion was carried to Stage 7 and is now tested there (#37).

**Do**
- `R/parse.R`, `R/node.R`, `R/nodeset.R`, `R/conditions.R`; `src/r_api.c`.
- Document as external pointer with finalizer; node/nodeset as an integer vector with a `doc` attribute (§6). **Vectorized from the first line** — there is no scalar-only interim version, because retrofitting vectorization changes every signature.
- The §7 surface: `xml_parse`, `xml_read`, `xml_root`, `xml_parent`, `xml_children`, `xml_elements`, `xml_find`, `xml_name`, `xml_local`, `xml_ns`, `xml_prefix`, `xml_type`, `xml_attrs`, `xml_attr`, `xml_text`, metadata accessors, `zuxml_info`.
- S3: `print`, `format`, `length`, `[`, `[[`, `c`.
- Condition hierarchy (§12) with line/column/byte-offset metadata; `R_UnwindProtect` around every parse; interrupt checks between 64 KiB feeds, never inside a handler.
- `iconv` pre-transcode path for non-Expat encodings (§10).

**Exit**
- The Atom example from §7 runs and reads correctly.
- Every accessor works on a nodeset and returns matching length.
- A node handle whose document was `rm()`ed and garbage-collected errors cleanly — it never reads freed memory. Test under `gctorture(TRUE)`.
- `Ctrl-C` during a 100 MiB parse interrupts cleanly with no leak (ASan-clean).
- A `windows-1252` fixture parses correctly through the `iconv` path.
- Every condition class in §12 is reachable from R and carries its metadata.

**What actually happened**

- 594 assertions pass; sanitizers stay clean; `R CMD check --as-cran` holds at the same 3 NOTEs. The Atom example from design §7 runs verbatim.
- The node-handle design paid off exactly as argued: an integer vector with the document as an attribute means R's GC keeps the document reachable with no protection list, verified by a test that drops every reference to the document and calls `gc()` twice before using the nodes.
- **Two real bugs, both found by tests rather than review.** `xml_find()` returned descendants in *reverse* document order — the initial stack seeding pushed children forward while every later push reversed them. And a failure part-way through a chunked feed lost its line/column/byte offset, because the builder was torn down before the parser's position was read; fixed by adding `zux_tree_error()`.
- Chunked feeding forced a useful refactor: `zux_tree_begin/feed/end/abort` now exists as a real incremental API, which is what Stage 6 and `zuhttp` streaming need anyway.
- `iconv()` *raises* on an unknown encoding rather than returning `NULL`, so the classed `zuxml_encoding_error` needed a `tryCatch` around it.
- **A third bug, visible only on the smallest CI runner.** The Stage 3 test harness indents its tree dump with `"%*s"` at `depth * 2`, making a dump O(depth²) in memory — about 10 GB for the 100k-deep fixture. macOS and Windows hid it: `malloc` simply failed, the harness broke out of its loop, and the test still passed because it only asserted node counts. Ubuntu's 7 GB runner was OOM-killed instead, surfacing as three `cancelled` jobs and exit code 143, with no test failure anywhere to point at it. Fixed by capping the indent and giving the harness a `dump = FALSE` option; whole-suite peak RSS is now 165 MB. Worth remembering that *cancelled* CI jobs meant OOM, not flakiness.

**Unverifiable here: the interrupt criterion.** Chunked feeding with `R_CheckUserInterrupt()` between 64 KiB chunks is implemented, and `R_UnwindProtect` cleanup releases the in-flight builder. The call site is demonstrably reached — documents well over 64 KiB parse correctly through the loop. But **whether R honours the interrupt could not be tested in this environment**: a control experiment with no zuxml involved showed that plain batch `Rscript` ignores `SIGINT` entirely (a pure R `repeat {}` loop survived it and needed `SIGKILL`), and `setTimeLimit()` did not fire either. So this criterion is met by construction and code review, **not** by test. Validate it in an interactive session, or from a CI job able to deliver signals to a foreground R, before claiming it at Stage 7.

---

## Stage 5 — Serializer and round-trip · M

**Status:** complete.

**Do**
- `src/zux_write.c` (escaping landed there too; there is no separate `zux_escape.c`); `R/write.R` with `xml_serialize`, `xml_write`, `as.character`.
- Context-correct escaping (§13) — not blanket escaping. `--` in a comment and `?>` in PI data are errors, not escapes.
- Namespace declarations re-emitted from node namespace fields at first binding.
- Iterative serialization with an explicit worklist.

**Exit**
- `parse → serialize → parse` is structurally identical for every corpus fixture, as a property test.
- Namespace round-trip is semantically correct including shadowing and same-URI-different-prefix.
- Escaping test vectors pass, including `]]>` in text and quotes in attribute values.
- Serializing a 100k-node document does not recurse (small-stack test).

**What actually happened**

- Went in clean: the round-trip property passed over the whole 20-fixture corpus on the first run, and no design change was needed. Suite is now 695 assertions and, with the harness fix, runs in 11 s.
- Two escaping details that the design's "minimal set" table implies but does not spell out, both of which would silently break round-tripping:
  - **Tabs, newlines and carriage returns in attribute values must become character references.** Attribute-value normalization turns a literal tab or newline into a space on re-parse, so `t="x&#10;y"` would come back as `x y`. Tested.
  - **An unqualified element inside a default namespace needs an explicit `xmlns=""` reset**, or re-parsing silently puts it into the enclosing namespace.
- Namespace declarations are re-emitted where first needed rather than where they originally appeared, so `<r xmlns:x="urn:s" xmlns:y="urn:s"><x:i/><y:i/></r>` comes back as `<r><x:i xmlns:x="urn:s"/><y:i xmlns:y="urn:s"/></r>`. Semantically identical, lexically different — exactly the guarantee §13 states, and the reason round-trip is asserted structurally rather than textually.
- Serialization is iterative like everything else; the sanitizer driver now serializes a 100k-deep document under a 1 MB stack (699,997 bytes out) as well as building and freeing it.

---

## Stage 6 — Streaming C API and downstream contract · M

**Status:** complete. Exit criteria 1 and 4 went unverified from f3392b2, which retargeted the only fixture at the archive, until #36 added `tools/zuxmltable` beside it. Criterion 1 is reworded below: an installed zuxml puts `expat.h` on every `LinkingTo: zuxml` include path, so a table consumer can be held to including no Expat header and linking no Expat symbol, not to having none on its path.

**Do**
- Finalize `inst/include/zuxml.h` (§14) and the `zuxml_api` table with `struct_size` as the sole discriminator (§15); register via `R_RegisterCCallable`.
- Build `tools/zuxmltest/` — a throwaway package that consumes zuxml **exactly as `zuhttp` will**: `Imports: zuxml`, `LinkingTo: zuxml`, `R_GetCCallable`, feeding chunks into `zux_parser_feed` from C. This is the only way to find out that the header is unusable before `zuhttp` depends on it.
- Document the string-lifetime contract prominently in the header — borrowed and non-NUL-terminated in handlers, owned and NUL-terminated from document accessors.

**Exit**
- The fixture package installs against zuxml and parses a document from C, including no Expat header and linking no Expat symbol. (Until the archive mode put `expat.h` beside `zuxml.h`, this read "with no Expat header on its include path".)
- `grep -riE 'XML_Parser|XML_Char|XML_ERROR' inst/include/` returns nothing.
- Feeding arbitrary chunk sizes through the C API matches the whole-buffer tree.
- `struct_size` degradation works: a consumer compiled against a shorter table still runs.

**What actually happened**

- The fixture package earned its place immediately. It failed at run time with `function 'zuxml_api_v1' not provided by package 'zuxml'` despite `Imports: zuxml` in `DESCRIPTION` and the symbols being present and registered in the shared object. **`Imports:` guarantees only that the package is installed; `R_GetCCallable()` resolves nothing until the namespace is actually loaded**, which needs an `importFrom()`/`import()` directive in the consumer's `NAMESPACE`. The design's claim that `Imports` ensures the package is "installed/loaded" was wrong on the second half and is now corrected. Finding this here rather than in `zuhttp` is exactly why this stage exists.
- `inst/include/zuxml.h` is now the single source of truth: `src/zux.h` includes it rather than redeclaring the types, so the public and internal views cannot drift.
- The consumer exercises streaming events, the tree and the serializer through the table, is chunk-independent, and links **zero** Expat symbols (`nm -u` count is 0).
- **Later, the fixture was retargeted.** `tools/zuxmltest` now models `zuxlsx` rather than the planned `zuhttp`: `LinkingTo` alone, Expat's own headers, `libzuxml.a` linked statically by its own `configure`, no `Imports` and no run-time dependency on zuxml. The reason is that `zuxlsx` is the consumer that exists, and its shape was covered only by a hand-compiled `main()` inside `tools/run-downstream-check` — which never went through `R CMD INSTALL` and so tested none of what actually breaks: `configure` under `R_HOME`, `system.file("lib", ...)`, path quoting, `Makevars.in` substitution, or the archive linking into a real package `.so`. The table path (`zuxml_api_v2`, `zux_register.c`) is unchanged and still registered, but now has **no fixture**. It was meant to be covered again by the `zuhttp` work in §16, but `zuhttp` plans no XML support, so the table has no consumer either; whether to restore a fixture or stop registering it for 0.1.0 is #36.
- Retargeting turned up a platform trap worth recording: with `PKG_LIBS` emptied, the fixture still built, loaded and parsed correctly on macOS, because R links package shared objects with `-undefined dynamic_lookup` and the loader satisfied `XML_*` from the system Expat already in the process. Every behavioural assertion passed. Only `nm -u` caught it, which is why that check now runs before the R-level ones.
- `tools/run-downstream-check` makes the whole thing re-runnable, including the header-purity grep and the Expat-symbol check.
- **The table got its fixture back, as a second one (#36).** `tools/zuxmltable` consumes the table the way the original fixture did: `Imports:`, `LinkingTo:` and an `importFrom()` directive. It calls all 26 members through `zuxml_api_get()`, and it carries a frozen copy of the 0.1.0 table, so moving a member fails its build: that is criterion 4. The gate checks the rest:
  - event streams and trees identical at 1/2/3/7/31/4096-byte chunks;
  - serialization through the table matching zuxml's own;
  - `tree_error` still reporting line and column after a failed feed;
  - an older, shorter table detected by `ZUXML_API_HAS()`;
  - zero Expat and zero `zux_` symbols in the fixture's shared object.
- Writing it found that the resolver `zuxml.h` emits cast `DL_FUNC` straight to the table getter's type. That compiles under GCC and under clang's defaults, but clang rejects it under `-Wcast-function-type`, so a consumer building with `-Werror` would fail. It now reads the pointer through a union, as zukomp's does. The gate also compiles the header alone as C99 and C++11 with `-pedantic`, and the resolver as C and C++ under `-Wall -Wextra -Wcast-function-type -Werror`, with clang as well as R's own compiler. With the old cast restored, the clang leg fails. With two members swapped, the fixture does not compile.

---

## Stage 7 — Hardening · L

**Status:** closed before 0.1.0 (2026-09-23), with the rest carried to #54. The interrupt criterion is tested since #37. The fuzz gate could not fail on a crash until #35 fixed it. The 24h-per-target criterion is not met yet. It is now read as cumulative, since #35 also caches the grown corpus between CI runs; before that, every run restarted from the seeds. The no-network criterion is asserted by a grep over `tests/` (`hardening.yaml`), not at run time. MSan, clang-tidy, and dedicated fuzz targets for three of the seven planned areas (namespace splitting, attribute copying, text coalescing) were not done: drop or schedule each. The other four areas are covered by the three targets that exist (design §20).

**Do**
- libFuzzer targets for: whole-document parse, incremental feed, namespace splitting, tree builder, attribute copying, text coalescing, serializer.
- Seed from the corpus plus upstream Expat corpora where licensing permits.
- ASan + UBSan in CI; MSan where practical; a scheduled (not per-push) long fuzz run.
- Full security test suite as permanent regressions (§20), including namespace-separator injection.
- `-Wall -Wextra -Wpedantic` as CI failures for project-owned code only; clang-tidy pass.
- Small-stack tests for every iterative claim: free, descendant search, text concat, serialization.
- ~~**Validate the Stage 4 interrupt criterion**, which could not be tested there: batch `Rscript` ignores `SIGINT`. Needs an interactive R session or a CI job that can signal a foreground R.~~ **Done (#37)**, with no signal at all. `tests/testthat/test-interrupt.R` sets `setTimeLimit()` inside the same expression as a 32 MiB parse, so the limit fires from the `R_CheckUserInterrupt()` call between feeds and unwinds through `parse_cleanup()` exactly as Ctrl-C does. An internal count of the arenas the R glue holds must be back at its starting value before any garbage collection, and the same input must then parse. The test runs under `--as-cran` too, so the ASan and valgrind jobs see the unwind path. Seen to fail with `parse_cleanup()` made to return early.

**Exit**
- 24h+ of fuzzing per target, cumulative across CI runs on the cached corpus, with no crash, leak, or UB in project-owned code.
- Every §20 security fixture passes; none can pass vacuously (verify each fails when its guard is deliberately removed).
- Zero warnings from project-owned sources.
- No test performs network I/O — assert this, do not assume it.

**What actually happened**

- **Fuzzing: 5.4M executions across three targets, all clean.** `fuzz_tree` (1.3M), `fuzz_feed` (1.6M, with the first byte choosing the chunk size so boundaries are explored adversarially rather than by enumeration) and `fuzz_roundtrip` (2.5M). The round-trip target `abort()`s if zuxml produces output it cannot itself re-parse, or if a second serialize is not a fixed point — that property survived 2.5M hostile inputs.
- Apple's Command Line Tools clang ships **no libFuzzer runtime**; `tools/run-fuzz` probes for a capable compiler (Homebrew LLVM locally, `clang` on CI) and says so rather than failing obscurely.
- **The strict-warning gate was initially broken and passing vacuously.** `-fsyntax-only` exits 0 on warnings, so `|| fail=1` caught nothing; it needed `-Werror`. Verified by deliberately introducing a warning and confirming the gate now fails. The parser core (`zux_parser.c`, `zux_tree.c`, `zux_write.c`) is clean even under `-Wconversion -Wshadow -Wcast-qual -Wwrite-strings`.
- Wiring the prototypes header surfaced a **name collision**: `init.c` had a static helper called `zux_str`, which is also the public *string type*. Invisible until the public header was included there. Renamed.
- **`tools/run-mutation-check` proves the security tests are not vacuous.** It deletes each guard from a throwaway copy and requires the hostile input to stop being rejected. All six — DOCTYPE, internal subset, `max_depth`, `max_nodes`, `max_attrs`, `max_text` — flip from their specific error to `ok` when removed. A guard whose removal changes nothing was never doing anything.
- Small-stack coverage now spans every operation the design claims is iterative: build, walk, **descendant search**, **text concatenation**, serialize and free, all at 100k depth under a 1 MB stack.
- New `hardening.yaml` workflow runs lint, sanitizers with **LeakSanitizer** (the Linux-only gap called out at Stage 2), mutation, downstream and fuzz on every push, plus a nightly 30-minutes-per-target fuzz run. **The fuzz step has never been able to fail on a crash:** `tools/run-fuzz` pipes each target into `tail -12` under POSIX `sh`, so the status it tests is `tail`'s (#35). The 5.4M clean executions above were read from the output, not enforced by the gate.
- **Fixed after the 2026-09-22 review (#35).** `tools/run-fuzz` captures the fuzzer's own status and treats any new file in `fuzz/artifacts/` as a finding. Before any real target, it requires `fuzz/fuzz_canary.c` to crash through the same code path, and exits 2 if it does not. The fuzz job caches the grown corpus under a fresh key per run, restored from the newest one. Checked locally: a clean run exits 0, the canary run as an ordinary target exits 1, and a canary edited not to crash exits 2.

**Still unverified: the interrupt criterion.** Three approaches were tried — batch `Rscript` + `SIGINT`, `setTimeLimit()`, and `R --interactive` + `SIGINT` — each with a control using no zuxml at all. **Every control also failed to interrupt**, including a pure R `repeat {}` loop that had to be `SIGKILL`ed. Signals cannot reach R in this environment, so the criterion is untestable here no matter what the code does. It remains implemented and reviewed (`R_CheckUserInterrupt` between 64 KiB feeds; `R_UnwindProtect` cleanup sharing the tested `zux_tree_abort` path) but **unexercised**. It does not need a person at a terminal. `R_CheckUserInterrupt()` also enforces `setTimeLimit()`, so an elapsed limit raises from the same call site and unwinds through the same cleanup, with no signal involved. The control above most likely set the limit as its own top-level expression, which the default `transient = TRUE` resets before the next one. And GitHub runners deliver signals normally; it was this environment that did not. Automating it is #37.

**Added after 0.1.0: the W3C XML Conformance Test Suite** (`tools/run-conformance`, `tools/xmlconformance.R`), pinned to the dated `xmlts20130923` archive — frozen since 2013, so it is a stronger pin than a git commit.

The suite cannot be scored the way zujson scores nst/JSONTestSuite, and saying why is most of the value. It is DTD-centric by construction: **all 812 `TYPE="valid"` cases carry a DOCTYPE**, so a naive harness reports 0/812 on the "must accept" half and looks catastrophic, when it is only the §11 policy working. Worse, 985 of the 1498 `not-wf` cases are refused at the DOCTYPE gate *before* their actual well-formedness violation is reached — the right answer for the wrong reason, and counting those as passes would be vacuous in exactly the way the strict-warning gate was.

So the gate is the **adjudicated** set: cases where zuxml returned something other than `zuxml_doctype_error`, i.e. actually formed an opinion about well-formedness. That is 591 files — 513 `not-wf` that must be rejected, 78 `invalid` that must be *accepted*, because "invalid" means invalid against a DTD and a non-validating parser must not diagnose it. Scope is decided by the error class, not by grepping for `<!DOCTYPE`: three OASIS cases carry that string inside a comment, a PI and a CDATA section, and ~180 files hit a parse error inside the DTD before the declaration is recognised at all.

That judgement runs **twice, once per parse mode**, because `allow_doctype` is a documented user-facing option and the default-mode gate is blind to it by construction — a gated file there is one zuxml did not stop at the DOCTYPE, so the flag cannot move any of them. Without the second gate the opt-in mode has no conformance coverage at all.

| | gated | as expected | deviations |
|---|---|---|---|
| `allow_doctype = FALSE` | 591 | 544 | 47 |
| `allow_doctype = TRUE` | 730 | 638 | 92 |

**0 unexplained in both.** Every deviation is attributable to a property the catalog itself states — XML 1.1 (Expat is an XML 1.0 processor; `ibm02n32` is a bare `0x7F`, forbidden in 1.1 and legal in 1.0), fifth-edition `NameChar` (Expat implements the 4th edition), `NAMESPACE="no"`, and in the opt-in gate `ENTITIES="parameter"/"both"`. Attribution is by rule, not by a list of file names, so a *new* deviation cannot hide inside a known category; order matters, since the XML 1.1 P77 cases also pull in an external subset and the narrower cause must win. Baselines are per cause and asymmetric: a category growing fails the run, a category shrinking is an improvement and only reported. The pool-size baselines are symmetric instead — a pool that *grew* means the suite changed, so the per-cause numbers were calibrated against a different population.

The 139 cases the opt-in gate adds bring 45 extra deviations, under two causes. **34** are the external subset never being retrieved, and that one runs in both directions: a `not-wf` document accepted because its violation lives in the unread DTD (29), and a `valid` document rejected because the entity it references was declared there (5). The remaining **11** are XML 1.1 name characters (5 `not-wf`, 6 `valid`), already covered by the existing rule. Nothing new is unexplained — design §2's Never column showing up as a measurement rather than a claim.

One genuine gap found, listed explicitly rather than swept into a rule: **`hst-lhs-007`** — a UTF-8 BOM followed by `encoding='iso-8859-1'`. The suite says not-wf; Expat does not diagnose the contradiction and `xml_encoding()` reports `iso-8859-1`. The sibling `hst-lhs-008` (UTF-16 BOM vs a `utf-8` declaration) *is* rejected, so it is specifically the UTF-8-BOM case.

Two traps, both of which lose cases **silently**:

- The master `xmlconf.xml` is the one file in the suite zuxml cannot read — it composes the sub-catalogs from external entities in an internal subset, which is precisely what this package refuses. The sub-catalogs are plain XML, so the harness reads them directly and parses its own input with the package under test.
- Three `sun/*` catalogs are bare external parsed entities (many top-level `<TEST>`, no root) and a fourth, `sun-error.xml`, is a document whose *root* is the `<TEST>` — and `xml_find()` selects descendants, so the root is not a descendant of itself. The first shape fails loudly; the second returns zero and was lost without any error until the per-catalog count was checked against the file. Both are fixed by wrapping every catalog in a synthetic root unconditionally, plus a hard failure if any catalog contributes nothing.

The canonical-XML `OUTPUT` files are deliberately not compared: only three adjudicated cases have one, and `xml_serialize()` is not a C14N implementation, so a byte comparison would report formatting as non-conformance.

Gate verified non-vacuous the same way the mutation check is: removing the `hst-lhs-007` entry fails the run with one unexplained deviation naming it, lowering a baseline fails it as a regression, and raising one passes while reporting the improvement.

---

## Stage 8 — Documentation, benchmarks, CRAN prep · M

**Status:** complete. The valgrind criterion is met by the valgrind job in `native-checks.yaml` on every push, and win-builder and R-hub are covered by CI rows, as `cran-comments.md` explains. #33 now says the same; its one open box is an optional win-builder R-devel run, since that is the machine CRAN's incoming pre-test uses.

**Do**
- roxygen2 docs for the full export surface; every function has a runnable example.
- ~~Getting-started article~~ **done**: `vignettes/articles/zuxml.Rmd`, pkgdown-only (excluded from the tarball via `.Rbuildignore`, so it never reaches CRAN or slows `R CMD check`). Writing it found a use-after-free that the fuzzers could not — they never read `zux_error.message`.
- ~~Remaining vignettes: *Parsing untrusted XML*, *Streaming large documents*~~ **done**, both shipped in the tarball (`VignetteBuilder: knitr`), unlike the getting-started article which stays pkgdown-only. `vignettes/security.Rmd` is deliberately named so that `vignette("security")` resolves — `R/parse.R` had referenced it as "once written" since Stage 4, so this closed a dangling cross-reference as well as a gap. `vignettes/streaming.Rmd` documents the **C** seam and says plainly that there is no R-level streaming API in 0.1.0, because there is not one; an R pull API is phase 2 and pretending otherwise in a vignette would be the wrong kind of documentation.
- ~~README rewrite~~ **done**: states plainly that this is XML, **not HTML** (§17), with the `<br>` failure shown rather than described.
- ~~Benchmarks against the §21 fixtures and targets, versus `xml2`~~ **done**: `tools/run-benchmarks` + `tools/benchmarks.R`, all seven §21 fixtures generated rather than shipped. Deliberately **not** in CI — shared-runner timings are too noisy to gate on, and ratio targets belong to a release check rather than every push. `xml2` and `bench` are not in `Suggests`, because `tools/` is `.Rbuildignore`d and CRAN should not install them to check the package.
- ~~`cran-comments.md`, `NEWS.md`, `LICENSE.note` with Expat provenance~~ **done**. `cran-comments.md` is `.Rbuildignore`d. It no longer waits on win-builder/R-hub results: it argues that the R-hub containers and the Windows R-devel runner cover that ground on every push.
- ~~Resolve the `___stderrp` NOTE from Expat's `ENTROPY_DEBUG` (see Stage 1)~~ **done**, via the justification route: `cran-comments.md` quotes the `getDebugLevel("EXPAT_ENTROPY_DEBUG", 0) >= 1u` guard and argues that a local patch would cost more than it buys, because `tools/verify-vendor` compares the vendored tree byte-for-byte against upstream and a patch would weaken that. Offer to patch if CRAN asks.
- ~~`R CMD check --as-cran` on win-builder (release + devel) and R-hub~~ **covered by CI instead**: the three R-hub containers and a `windows-latest`/R-devel row in `R-CMD-check.yaml` run on every push, and `cran-comments.md` says why no separate submission is reported.

**Exit**
- Zero NOTEs beyond "New submission" and the `___stderrp` one from vendored Expat. (The anticipated "installed size" NOTE does not in fact appear.) **Met** — a third NOTE appears locally, "'tidy' doesn't look like recent enough HTML Tidy", which is a property of the maintainer's macOS install and absent on every CI platform. Recorded in `cran-comments.md` rather than chased.
- Every example runs under `--run-donttest`. **Met.**
- Benchmarks meet the §21 targets, or the gap is documented with a reason. **Met on three of four, with one documented gap.**
- The `_R_CHECK_*` compiled-code checks pass, including `--use-valgrind` on one Linux run. **Met** — valgrind is not viable on the maintainer's macOS, but the valgrind job in `native-checks.yaml` runs on Linux on every push, with `--leak-check=full`.

**Benchmark results** (local macOS, R 4.5.2; absolute numbers are machine-dependent, the ratios are the targets):

| §21 target | Result |
|---|---|
| Tree parse within ~2× of `xml2` on a 1 MiB feed | **0.7–1.0×** — at parity, and *faster* than `xml2` on many-tiny-nodes (0.66×) and namespace-heavy (0.70×) |
| Streaming throughput independent of chunk size above 4 KiB | **2–13% spread** across 4 KiB–256 KiB |
| Zero R allocations during parsing; handles created lazily | Parsing 9 MiB moves R's gc counters by ~21 cells; materializing 40k node handles afterwards moves them by ~220 — the ordering is the claim |
| Memory ≤ 2.5× input | **Gap: ~2.6–3.4× measured.** See below |

The memory gap is the one real finding, and it is smaller than it first looked. A single 100 KiB parse reports ~3.6×, but nearly all of that is fixed cost — allocator arenas, page granularity, first touch — that a second document does not pay again. Measured marginally over 40 live copies the figure falls to ~2.4–2.7× on the 1 MiB feed and 2.4–3.4× on the 100 KiB one, varying run to run. RSS is a noisy instrument that never returns memory eagerly, so these run high if anything. The honest statement is that the package is **at or slightly above** the 2.5× target rather than comfortably inside it, and that the instrument is not sharp enough to say which. The benchmark therefore reports the number and does not gate on it. Sharpening this needs the arena to report its own size, which is a phase-2 change, not a 0.1.0 blocker.

---

## Stage 9 — first CRAN release · S

**Status:** open. Nothing mechanical blocks it since #44: tag `v0.1.0` and submit (#34).

- **0.1.0 is the first CRAN release, not 1.0.0.** The C ABI already needed one
  bump (`zuxml_api_v1` → `v2`, §15) before a single real consumer existed;
  promising API stability before `zuhttp` has actually used it would be
  premature, and CRAN version numbers only go up.
- ~~Verify all twelve acceptance criteria (design §23) explicitly, one by one, in `cran-comments.md`~~ **done** — a table naming, for each criterion, the test file, tool or CI job that verifies it. Writing it out was worth the effort: every criterion had something behind it, but three were verified only by a gate that nothing in `cran-comments.md` had previously mentioned.
- **Tag, submit, respond to CRAN — outstanding, and deliberately a human step, but not reachable yet.** This bullet used to say everything mechanical was done. The 2026-09-22 review found mechanical work left: #35, #36, #38, #40 and #44 (see *Review 2026-09-22* below). What was done stands: the pkgdown site is live, so the DESCRIPTION URL resolves; the README offers `install.packages("zuxml")` as well as the development install; and `R CMD check --as-cran --run-donttest` is clean. The win-builder, R-hub and Linux valgrind runs are no longer outstanding (Stage 8). The submission itself remains.
- **Fixed after the 2026-09-22 review (#40, #43).** `xml_parse()` refuses a character `x` of any length but one, rather than pasting it with `""`, and an `encoding` other than UTF-8 for character input. Limits are positive whole numbers or `Inf`, never replaced by the default. Every argument error is `zuxml_invalid_argument`; C statuses map to classes by enumerator name; conditions carry `expat_code`, and limit errors the limit's name and value; `?"zuxml-conditions"` documents them. Found on the way: `encoding = "latin1"`, `"UTF8"` and `"ASCII"` reached Expat untranslated and failed as unknown. For #43, the document's external pointer now exists before the parse, and the serializer's buffer is held by one while R allocates, with its length bounded by `INT_MAX`.
- **Fixed after the 2026-09-22 review (#44, and #41's documentation half).** The streaming vignette requires `importFrom()`, resolves the table at first use rather than in `R_init`, and names the fixture that checks for Expat symbols. The README and `vignette("linking")` quote `PKG_LIBS`, call `-DXML_STATIC` recommended rather than required (`dllimport` applies only under `_MSC_VER`), no longer promise that every zuxml update reaches a table consumer without a rebuild, and gain *What you do not inherit*: an archive consumer gets no DOCTYPE rejection and no limits, so an entity declared in an internal subset arrives as literal text. That claim, and the example handler, were checked against the installed archive. `cran-comments.md` names the archive's real path, counts the CI matrix as 5 runners and 3 containers, and says what the XXE tests assert. #41's code half, a policy helper in the archive, remains open.
- The next consumer work was to be `zuhttp`'s `resp_xml()`, but `zuhttp` plans
  no XML support today (design §16). v1.0.0 follows once the public R and C
  APIs have survived a real downstream consumer.

---

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| Expat vendoring fails on Windows | 1 | ~~Resolved.~~ Four traps hit, all fixed in configuration; green on all five CI jobs |
| Namespace triplet splitting is subtly wrong | 2 | Split-from-right rule specified; injection test written alongside the splitter |
| Undefined-entity errors on real feeds (`&nbsp;`) | post-v1 | Known and documented (§22 Q4). Decide the phase-2 answer from actual user reports, not speculation |
| C header proves unusable downstream | 6 | One fixture package per consumption mode: `tools/zuxmltest` for the archive, `tools/zuxmltable` for the table (#36). The table still has no real consumer |
| Users expect HTML to work | 8 | Say so in the README, the vignette, and the error message for `text/html` |
| CRAN objects to vendored source size | 8 | Parser subset only; provenance documented; precedent exists across CRAN |
| Scope creep toward libxml2 | all | §2's "Never" column is a commitment, not a suggestion |

---

## Explicitly not in v1

Tree construction and mutation · R pull/streaming API · `xml_as_list()` · pretty-printing · XPath or any query DSL · `zuhttp::resp_xml()` · HTML.

Each is either phase 2 in §2 or permanently out of scope. None blocks v1, and none is made harder by shipping v1 first — the index-addressed arena (§5) accommodates mutation, and the event seam (§3) accommodates a second producer.

---

## After v1

1. `zuhttp::resp_xml()` on buffered bodies (design §16) — not planned by `zuhttp` today, which could at most take zuxml as a `Suggests:`.
2. R pull/batched streaming API.
3. Tree construction and mutation.
4. `zuhtml` — HTML5 tokenizer on the same event seam, sharing zuxml's tree, node API, and serializer (design §17). This is the stage that makes `resp_html()` possible, and the whole reason the seam exists.
5. `zuhttp` streaming: response chunks fed straight into `zux_parser_feed` with no body materialization.

---

## Review 2026-09-22

A read-through of the whole repository against this roadmap, the design and the siblings, done before submission. The findings are issues #35–#44; the stage **Status:** lines above already reflect them.

**What should have been done differently**

- **Inventory the confirmed consumers at Stage 0.** Stage 6 modelled `zuhttp`, which plans no XML support. The consumer that existed was `zuxlsx`, whose vendored `xlsxio` is written against Expat itself. An inventory would have put the archive into Stage 6, rather than widening a finished package on 2026-09-17 and retargeting its fixture on 2026-09-21.
- **Add a fixture; never replace one.** f3392b2 turned the table's only fixture into the archive's, so `zuxml_api_v2` has no caller at all. Two consumer shapes need two fixtures, as zukomp has (`tools/zukomptest`, `tools/zukomplink`).
- **Try an in-process lever before deferring a criterion to a person.** `setTimeLimit()` reaches the same `R_CheckUserInterrupt()` call site as Ctrl-C, and a GitHub runner delivers signals normally. The interrupt criterion sat unverified across two stages for want of that (#37).
- **Gates need canaries.** Two gates here have passed vacuously: `tools/run-lint` before it had `-Werror` (Stage 7), and `tools/run-fuzz`, which tests `tail`'s exit status (#35). A gate is trusted once it has been seen to fail — a warning introduced on purpose, a target that must crash — not before.
- **Change the design in the same commit as the contract.** ad79f28 shipped `libzuxml.a` and the installed `expat.h` without touching the design. §15 caught up four days later in f3392b2, and §1–§3 not until this review.
- **Re-check a closed stage when a later change touches its subject.** f3392b2 invalidated two Stage 6 exit criteria and the stage stayed "complete".

**Recommended 0.1.0 scope**

- **Keep the R API as it is**: the 21 exports (24 since `xml_table()` and `xml_list()` (#57) and `xml_find_first()` (#59) were added for 0.1.0 on 2026-09-24), the `xml_*` names, node and nodeset as one integer-vector type. Fix the usability traps in #40 before CRAN, since afterwards each fix is a breaking change: a multi-element `x` collapsed with `""`, invalid limits silently replaced by defaults, unclassed argument errors, and conditions mapped by matching the English status string rather than the status enumerator, which C already returns as `code`.
- **Keep the archive.** It has the family's only real consumer, `zuxlsx`. Say plainly what an archive consumer does not inherit from the seam (#41, zuxlsx#47).
- **Decide the table (#36):** either a fixture that calls every `zuxml_api` member through `Imports:` + `LinkingTo:` + `importFrom()`, or stop registering it for 0.1.0. Shipping it untested is the one option not to take.
- Everything under *Explicitly not in v1* stays out.

**Which issues gate 0.1.0**

| Issue | Gates 0.1.0? | Why |
|---|---|---|
| #35 fuzz gate cannot fail | **yes** | `cran-comments.md` cites the fuzz runs as evidence, and the gate that should enforce them cannot fail on a crash. |
| #36 table: fixture or unregister | **yes** | An ABI shipped with no caller is a commitment nobody has checked. Deciding before CRAN is cheap; after, it is a deprecation. |
| #37 automate the interrupt criterion | no, but should | Met by construction and review. Automating it is cheap and closes Stage 7's last functional criterion. |
| #38 `test-linking.R` skips on a missing artifact | **yes** | The skip is reachable from exactly the failure the test exists to catch, and `R CMD check` passes a skip. |
| #39 CI/build alignment with the family | no | Pins, `.covrignore`, symbol visibility and extra downstream OSes are hygiene. Pinning before the submission run does make that run reproducible. |
| #40 argument validation, condition mapping | **yes** | This is the R-level contract. Changing it after CRAN breaks callers. |
| #41 archive consumers bypass the seam | no | The gap has to be closed in the consumer (zuxlsx#47, open). The false "is a parse error" cost in `vignette("linking")`, repeated in the README, is a documentation fix of #44's kind. |
| #42 `lib${R_ARCH}`, Expat licence, zuxmltest scripts | no | Family convergence. Moving the archive has to be coordinated with `zuxlsx`, whose `configure` already copes with both layouts. |
| #43 R allocations can longjmp past the arena | no | Reachable only on an R allocation failure, or on serialized output over 2 GiB. |
| #44 header, vignettes, README out of date | **yes** | The shipped header and vignettes state a contract that is false: that `Imports:` loads zuxml, and that CI asserts zero `XML_*` symbols in the fixture. |

**Outcome, 2026-09-23.** Every gating issue is closed: #35 (#47), #36 (#48), #38 (#46), #40 and #43 (#49), #44 (#50). Of the rest, #37 is closed (#53); #42 is done: its licence and `cleanup` parts in #52, and the move under `lib${R_ARCH}` with the `lib_dir()` resolver on 2026-09-24; #41 is done: its documentation in #50, and the archive helper considered and rejected on 2026-09-24, with the reason in design §15 (a handler cannot reach the parser without owning the consumer's `userData`); #39 is folded into #51, which redesigns CI into a fast PR tier and a slow `main`-and-nightly tier.
