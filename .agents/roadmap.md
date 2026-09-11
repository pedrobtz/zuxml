# zuxml — Roadmap to v1.0.0

Companion to [zuxml-design.md](zuxml-design.md). Section references (§) point there.

## Sequencing principles

1. **Security policy lands before the tree.** DOCTYPE rejection, limits, and the no-DTD build are enforced at the event seam (§3, §11). Building the tree first means retrofitting limits into code that already assumes they hold — that is how limit bugs get shipped.
2. **The serializer lands before the hardening stage.** It is the round-trip test oracle (§13); every stage after it gets a stronger test suite for free.
3. **Every stage ends with something runnable and tested.** No stage is "write three files, test later."
4. **Portability is proven at Stage 1, not discovered at Stage 8.** The Expat vendoring traps (§18) are the single largest schedule risk, and they surface on Windows.
5. **A stage is done when its exit criteria pass in CI on all three platforms**, not when the code is written.

Sizes are relative: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is the week.

---

## Stage 0 — Repo hygiene · S — **complete**

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

## Stage 1 — Vendor Expat and prove it builds · L — **complete**

The highest-risk stage. Do not proceed until it is genuinely green on Windows.

**Do**
- Import Expat 2.7.x (floor 2.7.1, CVE-2024-8176 — verify the current release) into `src/vendor/expat/`. Parser sources only: `xmlparse.c`, `xmltok*.c`, `xmlrole.c`, headers, `COPYING`. No `xmlwf`, examples, tests, benchmarks, CMake, or autotools.
- Write `src/zux_config.h` — the project-owned configuration header (§18): `XML_Char = char`, `XML_NS` on, **`XML_DTD` off**, `XML_CONTEXT_BYTES = 1024`.
- Solve the three traps (§18) *here*:
  - `BYTEORDER` derived from `__BYTE_ORDER__` / `_WIN32` / `__BIG_ENDIAN__`, with `#error` on the unknown case. Never copy a generated `expat_config.h`.
  - Entropy probe: `getrandom` / `arc4random_buf` / `RtlGenRandom`, falling back to `XML_POOR_ENTROPY` with the consequence documented.
  - `src/Makevars` with no GNU-make-only syntax and no `-Wno-*` overrides.
- `src/init.c` with `R_useDynamicSymbols(dll, FALSE)` and one smoke entry point that creates and frees a parser.
- `tools/update-expat` and `tools/verify-vendor`; write `src/vendor/expat/PROVENANCE`.
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

**Trap:** if Windows fights the entropy probe, fix the probe — do not reach for `XML_POOR_ENTROPY` unconditionally. `XML_SetHashSalt` (Stage 2) mitigates it, but only if the probe is honest about what it chose.

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

## Stage 2 — Event seam and security policy · L — **complete**

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


---

## Stage 3 — Tree builder · M — **complete**

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


---

## Stage 4 — R document and node API · M — **complete, with one criterion unverifiable**

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


---

## Stage 5 — Serializer and round-trip · M — **complete**

**Do**
- `src/zux_write.c` + `src/zux_escape.c`; `R/write.R` with `xml_serialize`, `xml_write`, `as.character`.
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


---

## Stage 6 — Streaming C API and downstream contract · M — **complete**

**Do**
- Finalize `inst/include/zuxml.h` (§14) and the `zuxml_api` table with `struct_size` as the sole discriminator (§15); register via `R_RegisterCCallable`.
- Build `tools/zuxmltest/` — a throwaway package that consumes zuxml **exactly as `zuhttp` will**: `Imports: zuxml`, `LinkingTo: zuxml`, `R_GetCCallable`, feeding chunks into `zux_parser_feed` from C. This is the only way to find out that the header is unusable before `zuhttp` depends on it.
- Document the string-lifetime contract prominently in the header — borrowed and non-NUL-terminated in handlers, owned and NUL-terminated from document accessors.

**Exit**
- The fixture package installs against zuxml and parses a document from C with no Expat header on its include path.
- `grep -riE 'XML_Parser|XML_Char|XML_ERROR' inst/include/` returns nothing.
- Feeding arbitrary chunk sizes through the C API matches the whole-buffer tree.
- `struct_size` degradation works: a consumer compiled against a shorter table still runs.

**What actually happened**

- The fixture package earned its place immediately. It failed at run time with `function 'zuxml_api_v1' not provided by package 'zuxml'` despite `Imports: zuxml` in `DESCRIPTION` and the symbols being present and registered in the shared object. **`Imports:` guarantees only that the package is installed; `R_GetCCallable()` resolves nothing until the namespace is actually loaded**, which needs an `importFrom()`/`import()` directive in the consumer's `NAMESPACE`. The design's claim that `Imports` ensures the package is "installed/loaded" was wrong on the second half and is now corrected. Finding this here rather than in `zuhttp` is exactly why this stage exists.
- `inst/include/zuxml.h` is now the single source of truth: `src/zux.h` includes it rather than redeclaring the types, so the public and internal views cannot drift.
- The consumer exercises streaming events, the tree and the serializer through the table, is chunk-independent, and links **zero** Expat symbols (`nm -u` count is 0).
- `tools/run-downstream-check` makes the whole thing re-runnable, including the header-purity grep and the Expat-symbol check.

---


---

## Stage 7 — Hardening · L — **complete, except the interrupt criterion**

**Do**
- libFuzzer targets for: whole-document parse, incremental feed, namespace splitting, tree builder, attribute copying, text coalescing, serializer.
- Seed from the corpus plus upstream Expat corpora where licensing permits.
- ASan + UBSan in CI; MSan where practical; a scheduled (not per-push) long fuzz run.
- Full security test suite as permanent regressions (§20), including namespace-separator injection.
- `-Wall -Wextra -Wpedantic` as CI failures for project-owned code only; clang-tidy pass.
- Small-stack tests for every iterative claim: free, descendant search, text concat, serialization.
- **Validate the Stage 4 interrupt criterion**, which could not be tested there: batch `Rscript` ignores `SIGINT`. Needs an interactive R session or a CI job that can signal a foreground R.

**Exit**
- 24h+ of fuzzing per target with no crash, leak, or UB in project-owned code.
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
- New `hardening.yaml` workflow runs lint, sanitizers with **LeakSanitizer** (the Linux-only gap called out at Stage 2), mutation, downstream and fuzz on every push, plus a nightly 30-minutes-per-target fuzz run.

**Still unverified: the interrupt criterion.** Three approaches were tried — batch `Rscript` + `SIGINT`, `setTimeLimit()`, and `R --interactive` + `SIGINT` — each with a control using no zuxml at all. **Every control also failed to interrupt**, including a pure R `repeat {}` loop that had to be `SIGKILL`ed. Signals cannot reach R in this environment, so the criterion is untestable here no matter what the code does. It remains implemented and reviewed (`R_CheckUserInterrupt` between 64 KiB feeds; `R_UnwindProtect` cleanup sharing the tested `zux_tree_abort` path) but **unexercised**. Validate by pressing Ctrl-C during a large `xml_parse()` in a real terminal.

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


---

## Stage 8 — Documentation, benchmarks, CRAN prep · M

**Do**
- roxygen2 docs for the full export surface; every function has a runnable example.
- ~~Getting-started article~~ **done**: `vignettes/articles/zuxml.Rmd`, pkgdown-only (excluded from the tarball via `.Rbuildignore`, so it never reaches CRAN or slows `R CMD check`). Writing it found a use-after-free that the fuzzers could not — they never read `zux_error.message`.
- Remaining vignettes: *Parsing untrusted XML* (the security model, and what `zuxml` deliberately refuses), *Streaming large documents*. Getting started is covered by the pkgdown article above and does not need a second, shipped copy.
- ~~README rewrite~~ **done**: states plainly that this is XML, **not HTML** (§17), with the `<br>` failure shown rather than described.
- Benchmarks against the §21 fixtures and targets, versus `xml2` for context.
- ~~`cran-comments.md`, `NEWS.md`, `LICENSE.note` with Expat provenance~~ **done**. `cran-comments.md` is `.Rbuildignore`d; it still needs the win-builder/R-hub results pasted in before submitting.
- ~~Resolve the `___stderrp` NOTE from Expat's `ENTROPY_DEBUG` (see Stage 1)~~ **done**, via the justification route: `cran-comments.md` quotes the `getDebugLevel("EXPAT_ENTROPY_DEBUG", 0) >= 1u` guard and argues that a local patch would cost more than it buys, because `tools/verify-vendor` compares the vendored tree byte-for-byte against upstream and a patch would weaken that. Offer to patch if CRAN asks.
- `R CMD check --as-cran` on win-builder (release + devel) and R-hub.

**Exit**
- Zero NOTEs beyond "New submission" and the `___stderrp` one from vendored Expat. (The anticipated "installed size" NOTE does not in fact appear.)
- Every example runs under `--run-donttest`.
- Benchmarks meet the §21 targets, or the gap is documented with a reason.
- The `_R_CHECK_*` compiled-code checks pass, including `--use-valgrind` on one Linux run.

---

## Stage 9 — first CRAN release · S

- **0.1.0 is the first CRAN release, not 1.0.0.** The C ABI already needed one
  bump (`zuxml_api_v1` → `v2`, §15) before a single real consumer existed;
  promising API stability before `zuhttp` has actually used it would be
  premature, and CRAN version numbers only go up.
- Verify all twelve acceptance criteria (design §23) explicitly, one by one, in `cran-comments.md`.
- Tag, submit, respond to CRAN.
- Then start `zuhttp`'s `resp_xml()`. v1.0.0 follows once the public R and C
  APIs have survived a real downstream consumer.

---

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| Expat vendoring fails on Windows | 1 | ~~Resolved.~~ Four traps hit, all fixed in configuration; green on all five CI jobs |
| Namespace triplet splitting is subtly wrong | 2 | Split-from-right rule specified; injection test written alongside the splitter |
| Undefined-entity errors on real feeds (`&nbsp;`) | post-v1 | Known and documented (§22 Q4). Decide the phase-2 answer from actual user reports, not speculation |
| C header proves unusable downstream | 6 | Fixture consumer package built before `zuhttp` commits to it |
| Users expect HTML to work | 8 | Say so in the README, the vignette, and the error message for `text/html` |
| CRAN objects to vendored source size | 8 | Parser subset only; provenance documented; precedent exists across CRAN |
| Scope creep toward libxml2 | all | §2's "Never" column is a commitment, not a suggestion |

---

## Explicitly not in v1

Tree construction and mutation · R pull/streaming API · `xml_as_list()` · pretty-printing · XPath or any query DSL · `zuhttp::resp_xml()` · HTML.

Each is either phase 2 in §2 or permanently out of scope. None blocks v1, and none is made harder by shipping v1 first — the index-addressed arena (§5) accommodates mutation, and the event seam (§3) accommodates a second producer.

---

## After v1

1. `zuhttp::resp_xml()` on buffered bodies (design §16).
2. R pull/batched streaming API.
3. Tree construction and mutation.
4. `zuhtml` — HTML5 tokenizer on the same event seam, sharing zuxml's tree, node API, and serializer (design §17). This is the stage that makes `resp_html()` possible, and the whole reason the seam exists.
5. `zuhttp` streaming: response chunks fed straight into `zux_parser_feed` with no body materialization.
