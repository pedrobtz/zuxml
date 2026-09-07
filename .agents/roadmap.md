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

## Stage 1 — Vendor Expat and prove it builds · L

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

---

## Stage 2 — Event seam and security policy · L

The core of the package. Everything downstream is a consumer of what this stage defines.

**Do**
- `src/zux_parser.c` — implement `zux_parser_new/feed/finish/free` and `zux_parser_error` (§14) over Expat.
- Namespace handling: `XML_ParserCreateNS` with `\f`, `XML_SetReturnNSTriplet(TRUE)`, and the **split-from-the-right** logic (§8). Write the URI-contains-separator test at the same time as the splitter, not after.
- Security policy at the seam: `XML_SetStartDoctypeDeclHandler` → `ZUX_ERR_DOCTYPE`; `XML_SetHashSalt` with per-parser entropy; all five limits with the §11 defaults, `max_text` enforced **on each coalescing append**.
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

---

## Stage 3 — Tree builder · M

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

---

## Stage 4 — R document and node API · M

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

---

## Stage 5 — Serializer and round-trip · M

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

---

## Stage 6 — Streaming C API and downstream contract · M

**Do**
- Finalize `inst/include/zuxml.h` (§14) and the `zuxml_api` table with `struct_size` as the sole discriminator (§15); register via `R_RegisterCCallable`.
- Build `tools/zuxmltest/` — a throwaway package that consumes zuxml **exactly as `zuhttp` will**: `Imports: zuxml`, `LinkingTo: zuxml`, `R_GetCCallable`, feeding chunks into `zux_parser_feed` from C. This is the only way to find out that the header is unusable before `zuhttp` depends on it.
- Document the string-lifetime contract prominently in the header — borrowed and non-NUL-terminated in handlers, owned and NUL-terminated from document accessors.

**Exit**
- The fixture package installs against zuxml and parses a document from C with no Expat header on its include path.
- `grep -riE 'XML_Parser|XML_Char|XML_ERROR' inst/include/` returns nothing.
- Feeding arbitrary chunk sizes through the C API matches the whole-buffer tree.
- `struct_size` degradation works: a consumer compiled against a shorter table still runs.

---

## Stage 7 — Hardening · L

**Do**
- libFuzzer targets for: whole-document parse, incremental feed, namespace splitting, tree builder, attribute copying, text coalescing, serializer.
- Seed from the corpus plus upstream Expat corpora where licensing permits.
- ASan + UBSan in CI; MSan where practical; a scheduled (not per-push) long fuzz run.
- Full security test suite as permanent regressions (§20), including namespace-separator injection.
- `-Wall -Wextra -Wpedantic` as CI failures for project-owned code only; clang-tidy pass.
- Small-stack tests for every iterative claim: free, descendant search, text concat, serialization.

**Exit**
- 24h+ of fuzzing per target with no crash, leak, or UB in project-owned code.
- Every §20 security fixture passes; none can pass vacuously (verify each fails when its guard is deliberately removed).
- Zero warnings from project-owned sources.
- No test performs network I/O — assert this, do not assume it.

---

## Stage 8 — Documentation, benchmarks, CRAN prep · M

**Do**
- roxygen2 docs for the full export surface; every function has a runnable example.
- Vignettes: *Getting started with zuxml*, *Parsing untrusted XML* (the security model, and what `zuxml` deliberately refuses), *Streaming large documents*.
- README rewrite — currently "The goal of zuxml is to ...". State plainly that this is XML, **not HTML** (§17), before anyone files the issue.
- Benchmarks against the §21 fixtures and targets, versus `xml2` for context.
- `cran-comments.md`, `NEWS.md`, `LICENSE.note` with Expat provenance.
- `R CMD check --as-cran` on win-builder (release + devel) and R-hub.

**Exit**
- Zero NOTEs beyond the unavoidable "installed size" from vendored sources.
- Every example runs under `--run-donttest`.
- Benchmarks meet the §21 targets, or the gap is documented with a reason.
- The `_R_CHECK_*` compiled-code checks pass, including `--use-valgrind` on one Linux run.

---

## Stage 9 — v1.0.0 · S

- Verify all twelve acceptance criteria (design §23) explicitly, one by one, in `cran-comments.md`.
- Tag, submit, respond to CRAN.
- Only then start `zuhttp`'s `resp_xml()`.

---

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| Expat vendoring fails on Windows | 1 | Front-loaded to Stage 1; three known traps named in §18 rather than discovered |
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
