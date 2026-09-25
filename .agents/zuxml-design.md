# zuxml — Design

**Status:** Implemented in 0.1.0 (not yet released). This is the specification; amend it in the same commit as the code that changes it.
**Package:** `zuxml`
**One line:** A small, strict, secure XML parser and immutable tree for R, vendoring Expat, usable standalone and from other packages' C code.

Every statement here is a decision. Things not yet decided live in §22 and nowhere else.

---

## 1. What zuxml is

A general-purpose XML library for R that:

- reads XML from files, strings, and raw vectors into a faithful tree;
- navigates that tree with a small vectorized R API;
- serializes it back;
- streams large documents through a C event API;
- is safe on untrusted input by construction, not by configuration;
- installs from source everywhere R does, with no system XML library.

Two audiences, one implementation:

- **R users** doing ordinary XML work — the tree and the navigation API.
- **Sibling C consumers** — the event API and a registered C-callable table. `zuhttp` was the intended one; it plans no XML support (§16), so the table has no consumer today, and `tools/zuxmltable` stands in for one (§15).

A third audience arrived after the design, and it bypasses the seam:

- **C code already written against Expat** — `xlsxio`, vendored by `zuxlsx`, is the case — gets Expat itself as a static archive (§15). It inherits the compile-time policy and nothing the seam enforces (§3).

Design principle:

> `xml_parse()` returns XML, not an interpretation of XML as generic R data.

Conversion to lists is a separate, explicitly lossy operation, and is not in v1.

---

## 2. Scope

| | v1 | Phase 2 | Never |
|---|---|---|---|
| Parse file / string / raw | yes | | |
| Elements, attributes, text | yes | | |
| Comments, PIs | yes (retained by default) | | |
| CDATA | yes (as text) | | |
| Namespaces | yes | prefix registries / aliases | |
| Mixed content ordering | yes | | |
| Immutable tree + navigation | yes | | |
| Vectorized nodesets | yes | | |
| Serialization | yes | pretty-printing options | canonical XML |
| Structured errors with line/column | yes | | |
| Resource limits | yes | | |
| C streaming/event API | yes | | |
| Registered C-callable table | yes | | |
| Static Expat archive (`libzuxml.a` + `expat.h`) | yes — for C written against Expat (§15) | | |
| Tree construction / mutation | | yes | |
| R pull/streaming API | | yes | R callback-per-event API |
| `xml_as_list()` | | yes (lossy, documented) | as the default return |
| `zuhttp::resp_xml()` | | yes | |
| HTML parsing | | see §17 — separate package | inside zuxml |
| XPath / XSLT / schema / XInclude / DTD validation | | | yes |
| External entity resolution, catalogs | | | yes |

The package should not gradually become a small clone of libxml2. When in doubt, the answer is no.

---

## 3. Architecture — the event seam

```text
  bytes
    │
    ▼
┌─────────────────┐
│ event producer  │   ← vendored Expat (the only producer in v1)
└────────┬────────┘
         │  zux_handlers  ← THE SEAM: normalized UTF-8, split namespaces,
         │                  project-owned types, no Expat types cross it
    ┌────┴────┬──────────────┐
    ▼         ▼              ▼
 tree      C consumer    (future: other producers — see §17)
 builder   (via the table)
    │
    ▼
 zux_document  ──►  R handles  ──►  R navigation API
```

Three rules that follow from this and are non-negotiable:

1. **No Expat type ever appears in `zuxml.h`.** Not `XML_Parser`, not `XML_Char`, not an Expat error code. An installed zuxml also carries `expat.h`, for the archive mode of §15; that is Expat's header, not zuxml's, and a table consumer never needs it.
2. **The tree builder is an ordinary consumer of `zux_handlers`.** It gets no privileged access. This is what makes a second producer (HTML, or a future Expat replacement) a bounded piece of work rather than a rewrite.
3. **Limits and security policy live at the seam**, not in the tree builder, so every consumer *of the seam* inherits them. An archive consumer (§15) links Expat directly and is not one. It inherits the compile-time policy (`XML_GE 0`, no `XML_DTD`), but not the DOCTYPE and internal-subset rejection and none of the five limits (#41).

---

## 4. Data model

Five node kinds:

```c
typedef enum {
    ZUX_DOCUMENT = 0,
    ZUX_ELEMENT,
    ZUX_TEXT,
    ZUX_COMMENT,
    ZUX_PI
} zux_node_type;
```

- **Attributes are not nodes.** They belong to their element.
- **CDATA is not a node kind.** It becomes text (§9).
- **Namespace declarations are not attributes.** `xmlns` / `xmlns:*` are consumed by the parser and surface as node namespace fields; they are not reported by `xml_attrs()`. They are re-emitted on serialization from the namespace fields.
- **The document node is always node 0** and always exists, even for an empty parse that failed.

---

## 5. Memory layout

One document owns everything. Three growable arrays, all addressed by index or offset — never by pointer — so `realloc` is always safe and there is no pointer-stability problem to reason about.

```c
typedef uint32_t zux_id;
#define ZUX_NONE 0xFFFFFFFFu

typedef struct {              /* 40 bytes */
    zux_id   parent, first_child, last_child, next_sibling;
    zux_id   name;            /* interned qname: element, PI target; else ZUX_NONE */
    uint32_t str_off, str_len;/* text body, comment body, PI data */
    uint32_t attr_start, attr_count;
    uint8_t  kind;
} zux_node;

typedef struct {              /* 24 bytes, one per DISTINCT name */
    uint32_t uri_off, uri_len, local_off, local_len, prefix_off, prefix_len;
} zux_qname;

typedef struct {              /* 12 bytes */
    zux_id   name;
    uint32_t val_off, val_len;
} zux_attr_slot;

struct zux_document {
    zux_node      *nodes;   uint32_t n_nodes,  cap_nodes;
    zux_attr_slot *attrs;   uint32_t n_attrs,  cap_attrs;
    zux_qname     *names;   uint32_t n_names,  cap_names;
    char          *strings; size_t   n_strings, cap_strings;
    uint32_t      *name_hash;  /* open-addressed index into names */
    /* document metadata: version, encoding, standalone */
};
```

Decisions this encodes:

- **Chunked vs single arena:** neither — growable arrays with index addressing. Simpler than a chunked arena and gives cache-friendly sequential traversal.
- **Name interning:** element names, attribute names, and namespace URIs are interned in `names`. Text and attribute *values* are not. Typical XML repeats a handful of names thousands of times; this is the single largest memory win available and it costs one small hash table.
- **String storage:** every string is `(offset, len)` into one byte buffer, NUL-terminated for C-consumer convenience. NUL is not a legal XML character, so termination is unambiguous, and the explicit length is always carried anyway.
- **No `prev_sibling`.** Saves 4 bytes/node; backwards traversal is rare and available via the parent's child list.
- **Node id width:** `uint32_t`. Node ids travel into R integer vectors, so `max_nodes` is capped at `INT_MAX`.
- **Immutability is a policy, not a structural constraint.** Phase-2 mutation appends nodes and relinks indices; nothing here has to be redesigned for it.

Budget: ~40 bytes/node plus text bytes plus 12 bytes/attribute. A 1 MiB feed with 20k nodes should land near 1.5–2 MiB resident.

---

## 6. R object model

The document is an external pointer with a finalizer that frees the arena.

**A node and a nodeset are the same object at different lengths** — an integer vector of node ids carrying the document as an attribute:

```r
structure(42L,          class = c("zuxml_node", "zuxml_nodeset"), doc = <xptr>)
structure(c(1L,5L,9L),  class =   "zuxml_nodeset",                doc = <xptr>)
```

Why this and not one external pointer per node:

- One allocation per handle, and a nodeset of 10,000 nodes is one allocation, not 10,000.
- The `doc` attribute is traced by R's GC, so the document stays reachable for free — no protection list, no reference counting, no finalizer ordering puzzle.
- Every accessor is naturally vectorized: it maps over an integer vector.
- `[`, `[[`, `length()`, `rev()` fall out of integer-vector semantics.

**Consequence, decided now because changing it later breaks every function:** `xml_children()` and friends return a `zuxml_nodeset`, and every accessor is vectorized over one. There is no list-of-nodes representation anywhere in the API.

Validity: node ids are validated against `n_nodes` on every call. A handle whose document has been finalized errors cleanly rather than reading freed memory.

---

## 7. Public R API (complete v1 surface)

### Parse

```r
xml_parse(x, ...)   # character (one string) or raw vector
xml_read(path, ...) # file
```

Common arguments, with defaults:

```r
xml_parse(
  x,
  encoding   = NULL,   # NULL = autodetect (BOM, then XML declaration)
  comments   = TRUE,
  pis        = TRUE,
  doctype    = FALSE,  # TRUE = accept and ignore the declaration; never defines entities
  max_depth  = 256L,
  max_nodes  = 1e7,
  max_attrs  = 4096L,
  max_text   = 64 * 1024^2,     # bytes, per text node after coalescing
  max_memory = 1024 * 1024^2    # bytes, total arena
)
```

`comments`/`pis` default to `TRUE` because zuxml is first a general XML library and faithful round-tripping is the least surprising default. `zuhttp` passes `FALSE` on the memory-sensitive path.

### Navigate

```r
xml_root(doc)
xml_parent(x)
xml_children(x)                        # all children, every node kind, in document order
xml_elements(x, name = NULL, ns = NULL) # element children, optionally filtered
xml_find(x, name, ns = NULL)            # element descendants, filtered, document order
xml_find_first(x, name = NULL, ns = NULL) # first such descendant per input, or a missing node
```

**Missing nodes (#59).** `xml_find()` is flat, so it cannot keep results aligned with its input: one `<book>` without a `<title>` shifts every later title into the wrong row. `xml_find_first()` returns exactly one node per input, and a *missing node* (`NA_integer_` in the handle) where there is no match. The contract, fixed before 0.1.0 because it is cheap now and a break later: every accessor returns `NA` for a missing node, `xml_attrs()` an empty named vector, `xml_serialize()` `NA`; traversals skip it (no parent, children or descendants), so a chained `xml_find_first()` keeps the slot; `xml_attr()`'s `default` applies to it. What has no answer for one refuses it with `zuxml_invalid_argument`: `xml_write()`, `xml_table()`, `xml_list()`. In C the rule sits in front of `check_id()`, which still rejects `NA` from any path that did not ask for it.

Filtering rule, uniform everywhere: `name` matches the **local** name. `ns = NULL` matches any namespace, `ns = NA` matches only nodes in no namespace, `ns = "uri"` matches that URI.

This replaces the eleven overlapping traversal functions in the previous drafts (`xml_child`, `xml_first`, `xml_all`, `xml_find_child`, `xml_find_children`, `xml_find_descendants`, …). Positional access is `[[`.

### Read

```r
xml_name(x)      # qualified name, e.g. "atom:entry"
xml_local(x)     # "entry"
xml_ns(x)        # namespace URI, NA if none
xml_prefix(x)    # "atom", NA if none
xml_type(x)      # "document" | "element" | "text" | "comment" | "pi"

xml_attrs(x)                                  # named character vector, names are qualified
xml_attr(x, name, ns = NULL, default = NA_character_)

xml_text(x, recursive = TRUE, trim = FALSE)
```

`xml_text()` is recursive by default, matching every other XML library. `recursive = FALSE` concatenates only direct text children — the distinction that matters for mixed content (§9).

Over a nodeset every accessor returns a vector of the same length; `xml_attrs()` returns a list of named character vectors.

### Extract (#57)

```r
xml_table(x, header = NA, trim = TRUE, ns = NULL, max_cells = 1e7)  # list of data frames
xml_list(x, trim = TRUE, ns = NULL)                                 # list of item lists
```

XML only: they read the tree a document has and apply no HTML parsing rules, so a `table` without `tbody` has exactly its rows. Elements match by local name, `ns` as everywhere else. Table cells are character; `colspan`/`rowspan` repeat the value, capped at HTML's 1000 and 65534, and the expanded table is bounded by `max_cells` (`zuxml_limit_error`) — without that bound one cell with both spans and a few thousand empty rows is a billion-cell allocation. Placement is one vector assignment per cell, so the work per row follows the expanded width, never the span values. A list item is a string, or `list(text, items)` when the `li` has `ul`/`ol` children; its text excludes theirs. Both are R over the accessors above; move to C only if profiling asks.

### Write

```r
xml_serialize(x)          # character(1)
xml_write(x, path)
as.character(node)        # = xml_serialize
```

### Metadata

```r
xml_version(doc); xml_encoding(doc); xml_standalone(doc)
zuxml_info()
```

### S3

`print`, `format`, `as.character`, `length`, `[`, `[[`, `c` on nodesets within one document.

That is the whole v1 export list — about 21 functions.

### Printing

```text
<zuxml_document>
root:     {http://www.w3.org/2005/Atom}feed
nodes:    143   attributes: 61
text:     18.2 kB   arena: 24.9 kB
encoding: UTF-8

<zuxml_node element>
{http://www.w3.org/2005/Atom}entry
attributes: 1   children: 7

<zuxml_nodeset[12]>
[1] <entry> [2] <entry> ...
```

Never dump the full document by default; that is what `xml_serialize()` is for.

---

## 8. Namespaces

Namespace-aware from v1. Construct with `XML_ParserCreateNS()` and enable `XML_SetReturnNSTriplet()` so prefixes survive.

Expat returns `uri SEP local SEP prefix`. Splitting it correctly is a security-relevant detail the previous drafts got wrong:

> There is **no** separator character that cannot occur in a namespace URI. Expat does not validate URIs, so a hostile document can embed the separator in the URI and forge a field boundary.

The rule:

1. Use a separator illegal in an XML `Name` — `\f` (0x0C).
2. Split from the **right** for the known field count (2 separators → uri/local/prefix; 1 → uri/local; 0 → local only, no namespace).
3. Any separator remaining in the leftmost field is URI data, not a boundary.

The separator is an internal detail. The public API only ever exposes `(uri, local, prefix)` as separate fields.

Semantics are keyed on `(uri, local)`. `prefix` is retained for faithful serialization and diagnostics and must never be used for matching — `{urn:a}item` and `{urn:b}item` are different elements regardless of prefix, and two different prefixes bound to the same URI are the same name.

Unqualified attributes are in **no** namespace (not the element's default namespace) — this is the XML rule and a common bug.

---

## 9. Text, mixed content, CDATA

Expat calls the character-data handler an arbitrary number of times for logically contiguous text, and the buffer it hands over is **not NUL-terminated**. Never assume one text run equals one callback.

- **Tree builder** coalesces adjacent character data into one text node, enforcing `max_text` **on each append**, not after — otherwise the limit is unenforceable and an attacker allocates freely before it trips.
- **Event API** may deliver text in chunks and says so; the seam coalesces within a bounded buffer as a convenience but makes no guarantee of maximality.
- **CDATA becomes text**, with no distinct node kind and no retained boundary. Round-tripping is semantic, not lexical. Serialization emits escaped text.
- **Whitespace is preserved exactly.** There is no parse-time trim option. Trimming is an extraction-time choice: `xml_text(x, trim = TRUE)`.

Mixed content preserves order absolutely. `<p>Hello <em>XML</em> world</p>` is:

```text
element(p)
├── text("Hello ")
├── element(em) └── text("XML")
└── text(" world")
```

`xml_text(p)` → `"Hello XML world"`; `xml_text(p, recursive = FALSE)` → `"Hello  world"`.

---

## 10. Encoding

Expat natively handles UTF-8, UTF-16 (both endians), ISO-8859-1, and US-ASCII. **It handles nothing else** — and `windows-1252` is common in real RSS. This is a practical gap, so it is handled explicitly rather than deferred.

Precedence:

1. Explicit `encoding=` argument (this is where `zuhttp` injects an HTTP `charset`) — passed to `XML_ParserCreate`, overriding the document's own declaration, which is the correct behaviour for a transport-level override.
2. Otherwise Expat autodetects: BOM, then the XML declaration.
3. Otherwise UTF-8.

If `encoding=` names something Expat cannot handle, transcode the whole input to UTF-8 with `iconv()` **before** feeding, then pass `encoding = "UTF-8"` explicitly so the now-stale declaration is overridden. Streaming inputs cannot be transcoded blind mid-stream, so a non-Expat encoding on the C streaming path is an error, not a silent guess. The R connection path (`xml_read()`, §16) has the whole input available in principle, so there it reads the connection to the end and takes the buffered route instead.

All output is UTF-8. Strings reach R via `Rf_mkCharLenCE(..., CE_UTF8)`.

Malformed input is an error. Never silently substitute replacement characters.

---

## 11. Security and limits

Threat model: **the input is hostile**. Secure behaviour is structural, not a setting the user has to find.

### Entities and DTDs

Expat is compiled **without `XML_DTD`**. This is the central decision. It removes parameter entities, external subsets, and the entire external-entity machinery from the binary — the whole class of XXE and entity-amplification attacks becomes impossible rather than merely disabled. Consequences, accepted:

- `XML_SetExternalEntityRefHandler` is irrelevant; there is nothing to disable.
- Billion-laughs is structurally impossible; `XML_SetBillionLaughsAttackProtection*` is not needed. (If `XML_DTD` is ever enabled, those APIs become mandatory, not optional.)
- The five built-in entities (`&amp; &lt; &gt; &quot; &apos;`) and all numeric character references work normally.
- **Any other entity reference is a hard error.** `&nbsp;` in an undeclared document fails. This is spec-correct — such documents are not well-formed XML — but it will surprise people parsing feeds. It is a known, documented v1 limitation with a phase-2 answer (§22, Q4).
- `DOCTYPE` is rejected by default via `XML_SetStartDoctypeDeclHandler` → `zuxml_doctype_error`. `doctype = TRUE` accepts a bare or `PUBLIC`/`SYSTEM` declaration — what real feeds carry — but **an internal subset is always rejected, even then**. Reason, found by testing rather than by reasoning: with `XML_GE 0` Expat does not record entity declarations, and a reference to one in a DTD-bearing document is passed through as *literal text* (`&e;` as four characters) rather than erroring, which is silent corruption. The internal subset is the only place a document can declare entities, so refusing it closes the hole; entity bombs are refused by the same rule.

Hash-flooding: **do not call `XML_SetHashSalt()`.** Expat already derives its own per-parser salt from the OS entropy backend selected in `src/expat_config.h`, which is the strongest source available to us; overriding it could only substitute something weaker. `XML_POOR_ENTROPY` is never an acceptable fallback, and an unknown platform is a compile error instead. (Earlier drafts of this document called for `XML_SetHashSalt()`; that was redundant at best and harmful at worst.)

### Limits

Five limits, not eight. The arena cap is the backstop that makes a longer list unnecessary.

| Limit | Default | Enforced |
|---|---|---|
| `max_depth` | 256 | at start-element, before push |
| `max_nodes` | 1e7 (hard cap `INT_MAX`) | at node allocation |
| `max_attrs` | 4096 | per element, at start-element |
| `max_text` | 64 MiB | per text node, on each coalescing append |
| `max_memory` | 1 GiB | at every arena growth |

Every limit failure is a distinct, stable error class (§12) — never a crash, never an OOM abort.

A limit must be a positive whole number, or `Inf` for the largest value its C type holds (`INT_MAX` for `max_nodes`, `SIZE_MAX` for the two byte limits). Anything else — `0`, `-1`, `0.5`, `NA`, a string, a vector, or a finite value above that maximum — is `zuxml_invalid_argument`. A limit is a security property: one silently replaced by the default, or truncated from a fraction, is a limit the caller did not set (#40).

Depth is tracked by the seam from start/end events. Never rely on stack exhaustion as a limit, and never build the tree recursively; freeing, descendant search, text concatenation, and serialization are all iterative with an explicit worklist.

### Interrupts and unwinding

A `longjmp` out of an Expat callback bypasses `XML_ParserFree` and leaks the parser — Expat has no cleanup hook. Therefore:

- **No R API is ever called from inside a handler.** Not `Rf_error`, not `R_CheckUserInterrupt`, not allocation.
- Handlers signal failure by returning non-`ZUX_OK`; the seam calls `XML_StopParser` and unwinds through C.
- Whole-buffer parsing is internally chunked (64 KiB) precisely so `R_CheckUserInterrupt()` has a safe call site *between* feeds.
- The R entry point wraps the parse in `R_UnwindProtect` so the arena and parser are freed on interrupt.

---

## 12. Errors

Project-owned throughout. The native Expat code is retained as metadata for diagnostics but never surfaces as the message.

```text
zuxml_error
├── zuxml_invalid_argument an unusable argument, or ZUX_ERR_INVALID_ARGUMENT
├── zuxml_parse_error      malformed XML, unexpected EOF, undefined entity
├── zuxml_encoding_error
├── zuxml_doctype_error
├── zuxml_limit_error
│   ├── zuxml_depth_limit
│   ├── zuxml_node_limit
│   ├── zuxml_attr_limit
│   ├── zuxml_text_limit
│   └── zuxml_memory_limit
├── zuxml_memory_error     allocation failure
└── zuxml_cancelled
```

Every condition a parse raises carries `line`, `column`, `byte_offset`, `status` (the C enumerator's name, such as `ZUX_ERR_DEPTH_LIMIT`) and `expat_code` (`NA` when the failure was not Expat's). A limit error adds `limit`, the argument's name, and `limit_value`, its value. A `zuxml_invalid_argument` carries `arg`, the argument at fault. The classes are documented for users in `?"zuxml-conditions"`.

R maps a C status to its class by the enumerator's name, which C returns beside the English status string. It never matches the English: rewording a message must not change which handler catches it. `ZUX_ERR_INTERNAL`, or a status the map does not know, is a bare `zuxml_error`. `zuxml_cancelled` is reachable only through the C API, where a downstream package supplies the handler.

Users see:

```text
XML parse error at line 18, column 7: mismatched closing tag </item>
```

not `XML_ERROR_TAG_MISMATCH`.

The C API must be able to produce this, which the previous draft's header could not — see `zux_parser_error()` in §14.

---

## 13. Serialization

**In v1**, contrary to the earlier drafts' "phase 2", for one reason: it is the test oracle. Parse → serialize → parse → compare gives property-based round-trip testing over the whole corpus, which is worth far more than the ~250 lines it costs.

Guarantees:

- element order, attribute order, text order, and mixed-content interleaving are preserved;
- namespaces are preserved *semantically*, with declarations re-emitted from the namespace fields at the node where they were first bound;
- output is UTF-8 with an XML declaration.

Explicitly not preserved, because parsing does not retain them: quote style, inter-attribute whitespace, CDATA boundaries, entity spelling, empty-element vs open/close spelling. `zuxml` is not a lossless source editor.

Escaping — the correct minimal set, not "escape everything":

| Context | Escaped |
|---|---|
| text | `&` `<`, and `>` when it would close `]]>` |
| attribute value (double-quoted) | `&` `<` `"` |
| comment | not escapable — `--` inside a comment is an error |
| PI data | not escapable — `?>` inside PI data is an error |

Canonical XML is out of scope. Pretty-printing is phase 2, because indentation is not whitespace-safe in general.

---

## 14. Public C API

Illustrative: this is the header as designed, and `inst/include/zuxml.h` is authoritative where they differ. The shipped header differs in four ways:

- **It declares no functions.** Every entry point is a member of the `zuxml_api` table (§15). The `zux_*` prototypes below live only in the internal `src/zux.h`, so a consumer calls `api->parser_feed`, never `zux_parser_feed`.
- `zux_error.message` is an inline `char[ZUX_MESSAGE_MAX]`, not a pointer (§15).
- The table also carries the incremental tree builder (`tree_begin`/`feed`/`end`/`error`/`abort`, over an opaque `zux_tree_builder`), `serialize` and `set_message`.
- It adds `zux_node_type`, `ZUXML_API_HAS()` for guarding appended members, and an opt-in `ZUXML_DEFINE_API_GET` resolver that reads `R_GetCCallable()`'s `DL_FUNC` through a union rather than casting it (a direct cast fails under clang's `-Wcast-function-type`).

```c
#ifndef ZUXML_H
#define ZUXML_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ZUX_OK = 0,
    ZUX_DONE,
    ZUX_ERR_INVALID_ARGUMENT,
    ZUX_ERR_INVALID_XML,
    ZUX_ERR_ENCODING,
    ZUX_ERR_DOCTYPE,
    ZUX_ERR_UNDEFINED_ENTITY,
    ZUX_ERR_DEPTH_LIMIT,
    ZUX_ERR_NODE_LIMIT,
    ZUX_ERR_ATTR_LIMIT,
    ZUX_ERR_TEXT_LIMIT,
    ZUX_ERR_MEMORY_LIMIT,
    ZUX_ERR_MEMORY,
    ZUX_ERR_CANCELLED,
    ZUX_ERR_INTERNAL
} zux_status;

/* ---- string contract ----------------------------------------------------
 * Strings reaching a HANDLER are borrowed and valid ONLY until that handler
 * returns. They are not NUL-terminated. Callees MUST copy what they keep.
 * Strings reaching a DOCUMENT accessor are owned by the document, are
 * NUL-terminated, and are valid for the document's lifetime.
 * ---------------------------------------------------------------------- */
typedef struct { const char *ptr; size_t len; } zux_str;

typedef struct { zux_str uri, local, prefix; } zux_name;
typedef struct { zux_name name; zux_str value; } zux_attr;

/* Handlers return ZUX_OK to continue, or any error status to stop the parse;
 * that status becomes the parse result. This is how cancellation works. */
typedef struct {
    zux_status (*start_element)(void *ctx, const zux_name *name,
                                const zux_attr *attrs, size_t n_attrs);
    zux_status (*end_element)  (void *ctx, const zux_name *name);
    zux_status (*text)         (void *ctx, zux_str text);
    zux_status (*comment)      (void *ctx, zux_str text);
    zux_status (*pi)           (void *ctx, zux_str target, zux_str data);
    zux_status (*xml_decl)     (void *ctx, zux_str version, zux_str encoding,
                                int standalone);
} zux_handlers;

typedef struct {
    uint32_t    max_depth, max_nodes, max_attrs;
    size_t      max_text, max_memory;
    const char *encoding;      /* NULL = autodetect */
    int         allow_doctype, keep_comments, keep_pis;
} zux_options;

void zux_options_init(zux_options *opt);   /* fills in the documented defaults */

/* ---- streaming ---- */
typedef struct zux_parser zux_parser;

zux_status zux_parser_new (zux_parser **out, const zux_options *opt,
                           const zux_handlers *h, void *ctx);
zux_status zux_parser_feed(zux_parser *p, const void *data, size_t n);
zux_status zux_parser_finish(zux_parser *p);
void       zux_parser_free (zux_parser *p);

typedef struct {
    zux_status  status;
    uint64_t    line, column, byte_offset;
    int         expat_code;      /* diagnostics only */
    const char *message;         /* owned by parser, valid until next feed/free */
} zux_error;

void        zux_parser_error (const zux_parser *p, zux_error *out);
const char *zux_status_string(zux_status s);

/* ---- tree ---- */
typedef struct zux_document zux_document;
typedef uint32_t zux_id;
#define ZUX_NONE 0xFFFFFFFFu

zux_status zux_tree_parse(zux_document **out, const void *data, size_t n,
                          const zux_options *opt, zux_error *err);
void       zux_document_free(zux_document *doc);

zux_id   zux_root        (const zux_document *d);
uint32_t zux_node_count  (const zux_document *d);
int      zux_node_kind   (const zux_document *d, zux_id id);
zux_id   zux_parent      (const zux_document *d, zux_id id);
zux_id   zux_first_child (const zux_document *d, zux_id id);
zux_id   zux_next_sibling(const zux_document *d, zux_id id);
zux_name zux_node_name   (const zux_document *d, zux_id id);
zux_str  zux_node_text   (const zux_document *d, zux_id id);
uint32_t zux_attr_count  (const zux_document *d, zux_id id);
zux_attr zux_attr_at     (const zux_document *d, zux_id id, uint32_t i);

#ifdef __cplusplus
}
#endif
#endif
```

Requirements the header must keep satisfying:

- no Expat type, anywhere;
- UTF-8 only;
- input buffers are caller-owned and never retained past `feed()`;
- usable with no `SEXP` and no R headers;
- any chunk boundary is legal, including 1 byte and mid-multibyte-sequence;
- cancellation from any handler;
- every failure reportable with a position.

---

## 15. C-callable registration

One versioned table, registered with `R_RegisterCCallable("zuxml", "zuxml_api_v2")`.

```c
typedef struct {
    uint32_t struct_size;   /* the ONLY version discriminator */
    void (*options_init)(zux_options *);
    zux_status (*parser_new)(zux_parser **, const zux_options *,
                             const zux_handlers *, void *);
    zux_status (*parser_feed)(zux_parser *, const void *, size_t);
    zux_status (*parser_finish)(zux_parser *);
    void       (*parser_free)(zux_parser *);
    void       (*parser_error)(const zux_parser *, zux_error *);
    zux_status (*tree_parse)(zux_document **, const void *, size_t,
                             const zux_options *, zux_error *);
    void       (*document_free)(zux_document *);
    /* … tree accessors … */
    const char *(*status_string)(zux_status);
} zuxml_api;
```

The member list above is a sketch; the member order that is ABI is the one in `zuxml.h`.

`struct_size` is the sole version discriminator **for this table** — the previous draft carried three overlapping schemes (`ZUXML_API_VERSION`, `abi_version`, `struct_size`). A consumer compares `struct_size` against the offset of the member it wants and degrades gracefully. Fields are only ever appended, never reordered or removed.

What `struct_size` cannot see is a layout change in any *other* public type — `zux_error`, `zux_options`, `zux_name`. The table is byte-identical in that case, so an old consumer goes on passing a differently shaped struct and smashes its own stack, and R does not rebuild `LinkingTo` dependents when zuxml is upgraded. The registered callable **name** versions those types: `zuxml_api_v1` → `zuxml_api_v2` when `zux_error.message` became an inline `char[ZUX_MESSAGE_MAX]` rather than a `const char *`. A stale consumer then fails loudly at `R_GetCCallable()` instead of writing through the wrong offsets. Bump the name for any such change; append to the table for everything else.

Downstream declares `Imports: zuxml` **and** `LinkingTo: zuxml` — and, critically, must also carry an actual import directive in its `NAMESPACE`:

```r
importFrom(zuxml, zuxml_info)   # or import(zuxml)
```

`Imports:` in `DESCRIPTION` only guarantees that zuxml is *installed*. `R_GetCCallable()` resolves nothing until zuxml's namespace is **loaded**, which is what the `NAMESPACE` directive causes; without it `R_init_zuxml` never runs and the consumer fails at run time with `function 'zuxml_api_v2' not provided by package 'zuxml'`. Earlier drafts of this document said `Imports` ensures the package is "installed/loaded", which is wrong on the second half. `LinkingTo:` exposes `inst/include/zuxml.h` (and, since the archive mode below, `expat.h` beside it).

`tools/zuxmltable` is that shape, run by `tools/run-downstream-check`. It calls all 26 members through `zuxml_api_get()`, and it carries a frozen copy of the 0.1.0 table whose member offsets must match the current header's, so reordering or removing a member fails its build rather than a consumer's run.

### Two consumption modes

The table above is one of two ways to consume zuxml from C, and they have different dependency shapes:

| | table (`zuxml_api`) | archive (`libzuxml.a`) |
|---|---|---|
| `DESCRIPTION` | `Imports:` **and** `LinkingTo:` | `LinkingTo:` only |
| `NAMESPACE` | an `importFrom()`/`import()` directive | nothing |
| Header | `inst/include/zuxml.h`, no Expat type in sight | `<expat.h>`, off the same `LinkingTo` include path |
| Symbols | resolved at run time by `R_GetCCallable()` | linked into the consumer's own shared object |
| zuxml at run time | must be installed **and** loadable | need not be installed at all |
| A zuxml fix reaches it | on zuxml's upgrade alone | only when the consumer is reinstalled |

The archive exists for a C library that is written against Expat itself and cannot be retargeted onto a callback table — `xlsxio` in `zuxlsx` is the case that prompted it, and it needs `XML_GetBuffer`/`XML_StopParser`/`XML_ResumeParser`, which the table does not offer. It holds `EXPAT_OBJECTS` and nothing else (see `src/Makevars`): no R glue, which would be both useless and a duplicate symbol inside a consumer.

What an archive consumer does **not** get is the seam. It inherits the compile-time policy (`XML_GE 0`, no `XML_DTD`), but not the DOCTYPE and internal-subset rejection and none of the §11 limits (§3, rule 3). With `XML_GE 0`, a reference to an entity declared in an internal subset reaches such a consumer as literal text — the defect roadmap Stage 2 found and closed only at the seam. The consumer has to install its own `XML_SetStartDoctypeDeclHandler` to refuse it (#41, zuxlsx#47); `vignette("linking")` shows the handler.

**No policy helper ships in the archive (#41, decided 2026-09-24).** A helper such as `zux_expat_apply_policy(XML_Parser)` cannot be written so that a consumer can just call it. A handler that refuses a DOCTYPE has to call `XML_StopParser()` on the parser, and Expat passes a handler the consumer's `userData`, not the parser. The only switch that changes that, `XML_UseParserAsHandlerArg()`, applies to every handler at once, and would take `userData` away from the consumer's own handlers — xlsxio's among them. So a helper would have to own `userData` and forward to the consumer's, which is an API of its own, would break the archive being plain Expat, and would still need every consumer to be changed to use it. Documenting the five-line handler costs a consumer the same change for less. The fix belongs in the consumer.

There is no `configure`-free way to point at the archive — `LinkingTo` adds `<pkg>/include` to `CLINK_CPPFLAGS` but has no library equivalent — so an archive consumer resolves the archive's directory in its own `configure` and substitutes it into `src/Makevars.in`. The archive installs under `lib${R_ARCH}`, as the shared object does under `libs${R_ARCH}` and as zukomp's archive does (#42); that is plain `lib/` where R sets no architecture. The consumer asks for `system.file("lib", .Platform$r_arch, ...)` first and falls back to `system.file("lib", ...)`, which is right under either layout. `tools/zuxmltest` is that shape, and its `lib_dir()` is `zuxlsx`'s.

One platform caveat, which `tools/run-downstream-check` checks with `nm -u` rather than trusting the build: on macOS R links a package `.so` with `-undefined dynamic_lookup`, so an archive consumer whose `PKG_LIBS` is wrong still builds, still loads and still parses — against whatever Expat the process happens to have. On Linux and Windows the same mistake fails at link time.

---

## 16. `zuhttp` integration

**Status (2026-09-22): `zuhttp` plans no XML support.** Its design does not mention XML, and it consumes no sibling in 0.x (§25). zuxml could at most be a `Suggests:` for a future `zu_resp_xml()`. What follows records the intended shape only; nothing in 0.1.0 depends on it.

Boundary: **`zuhttp` owns bytes and content types. `zuxml` owns XML semantics and knows nothing about HTTP.**

```text
TLS → HTTP framing → Content-Encoding → [zukomp] → bytes → zuxml → tree/events
```

`zuhttp` declares `Suggests: zuxml`, not `Imports`. Rationale: content decoding is transport-level and belongs in `zuhttp`'s core; XML is a high-level convenience, and most `zuhttp` users will never parse XML. `resp_xml()` errors with an install hint if `zuxml` is absent.

```r
resp_xml(resp, check_type = TRUE, encoding = NULL, ...)
```

- recognizes `application/xml`, `text/xml`, `*/*+xml` (`atom+xml`, `rss+xml`, `soap+xml`, `svg+xml`); `check_type = FALSE` overrides;
- passes the HTTP `charset` as `encoding=` when present, which by §10 overrides the document declaration;
- calls `zuxml::xml_parse(resp_body_raw(resp), comments = FALSE, pis = FALSE)`;
- re-raises `zuxml` conditions with the request URL and status added to the condition, preserving the original class so `tryCatch(zuxml_limit_error = …)` still works.

Buffered bodies in phase 2; feeding response chunks straight into `zux_parser_feed` without materializing the body is phase 3, and is the reason the streaming C API is v1 rather than later.

### `xml_read()` over a connection

Independently of `zuhttp`, `xml_read()` accepts a URL string or any R connection and streams it. A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is opened with `url()`, any other string with `file()`; the scheme is lower-cased first because `url()` is case-sensitive where RFC 3986 is not. R reads the connection with `readBin()` in 64 KiB pieces and hands each to an incremental builder held in an external pointer (`C_zux_stream_begin`/`feed`/`end`/`abort` in `r_document.c`, over the core's `zux_tree_begin`/`feed`/`end`). The body is never held whole; the limits bound the tree. R checks for an interrupt between iterations of its own loop, no R API runs inside a feed, and the builder is released by `on.exit()` -- or by the pointer's finalizer if that never runs -- so an interrupted or failed read gives its arena back.

**The reading is done in R, not in C, and this is a CRAN constraint, not a preference.** The first version used `R_ext/Connections.h` (`R_GetConnection`, `R_ReadConnection`, as iotools does) from a header-only C byte source. R 4.5's `R CMD check` reports both as non-API entry points (found on zuhtml first, then on this package's oldrel job), and CRAN treats non-API calls as something to remove. An R-level `readBin()` loop at 64 KiB costs nothing measurable and needs no unstable API.

The format-agnostic part lives in `R/zu_source.R`, meant to be copied verbatim into sibling packages (zuhtml, zujson, zuyaml) and carrying an origin line so drift is visible: `zu_open_input()` resolves a path, URL or connection to an open binary connection following `readBin()`'s convention (an unopened one is opened in `"rb"` and the caller closes it; an open one must already be binary and is left open), raising invalid-argument errors through a callback so each package keeps its own condition classes; `zu_read_chunks()` runs the read loop against a package-supplied `feed`, stopping when the feed reports failure and refusing a non-blocking connection that returns no data while `isIncomplete()`; `zu_read_all()` reads one whole. Each package supplies begin/feed/end over its own parser. `tests/testthat/test-source.R` is that file's suite, written against `read_input <- xml_read` and a `prefix` so a copy changes two lines. Base R's `url()` covers `http`, `https` and `ftp` with no dependency; `zuhttp`'s `resp_xml()` remains the path for anything needing headers, retries or a `charset` from the response.

---

## 17. HTML

**HTML parsing is out of scope for `zuxml`, and this needs saying plainly because it is the one place the package will disappoint expectations.**

Expat is a strict, non-recovering XML parser. Real-world HTML — `<br>`, unquoted attributes, `&nbsp;`, implied `<tbody>`, unclosed `<li>` — is not well-formed XML and Expat will hard-fail on it. No configuration changes this; error recovery is a different parsing algorithm, not a flag. Only XHTML served as well-formed XML parses today, and that is genuinely rare on the modern web.

The plan, which is why §3's event seam matters:

- A sibling package **`zuhtml`** vendors an HTML5 tokenizer/tree-constructor (lexbor or gumbo) and emits the **same `zux_handlers` events**.
- It reuses `zuxml`'s tree builder, document representation, R node handles, navigation API, and serializer via `LinkingTo: zuxml`. Only the producer differs.
- `zuhttp` then gets `resp_html()` alongside `resp_xml()`, over one shared node API, so user code that walks a tree does not care which parser produced it.

The cost of this plan is one extra package. The cost of the alternative — bolting HTML recovery onto Expat — is an unmaintainable parser that is wrong in ways users cannot predict. Building the tree on the event seam from day 1 is what keeps the option open at low cost.

---

## 18. Expat build configuration and vendoring

### Version

Pinned at **Expat 2.8.4** (2026-08-31), which is also the floor. It is a security release fixing four vulnerabilities: CVE-2026-66046 / CVE-2026-76641 (quadratic runtime in attribute `isCdata` lookups — remote DoS from moderately sized input, CVSS 7.5), CVE-2026-76957 (custom encoding callbacks unprotected against parser re-entry), and CVE-2026-76956 (inverted `getentropy()` return handling allowing hash flooding). The last of these directly informs the entropy choice below. Re-verify the current release at every re-vendoring. Never track `master`.

**Expat is not treated as a trusted component.** Upstream publicly tracks unfixed non-public vulnerabilities at libexpat issue #1160 — seven open at import time, three with reserved CVEs. That is normal for a heavily fuzzed XML parser and is not a reason to prefer a different one; it is the reason the security model does not rest on the parser being correct. `XML_GE 0` with no `XML_DTD` deletes whole vulnerability classes from the binary, and the project-owned limits at the event seam bound what a parser bug can cost. Re-vendor promptly on each upstream release.

Record in `src/vendor/PROVENANCE` — one level above the vendored tree, so the tree stays byte-identical to upstream: upstream repo, release tag, commit SHA, tarball SHA-256, import date, license, local patches, compile configuration.

### Configuration

| Setting | Value | Why |
|---|---|---|
| `XML_Char` | `char` (UTF-8) | natural bridge to `mkCharLenCE(CE_UTF8)` |
| `XML_DTD` | **not defined** | §11 — removes the entire XXE/amplification class |
| `XML_NS` | defined | §8 |
| `XML_GE` | **`0`** | must be *defined* as 0, not left undefined — Expat tests `XML_GE == 1`. Removes general-entity support outright; `xmlparse.c` enforces that `XML_DTD` must then stay undefined. |
| `XML_CONTEXT_BYTES` | 1024 | enough for error context, bounded |
| `BYTEORDER` | 1234/4321, set portably | see below |
| Allocator | libc default | Expat frees individually; routing through the arena does not fit, and routing through R risks `longjmp`. `XML_Memory_Handling_Suite` reserved for future accounting. |

### The four portability traps

These are the specific things that break Expat vendoring, named so CI does not have to discover them:

1. **`BYTEORDER`.** Expat's `expat_config.h` requires it. Do not copy a generated header from one machine. Derive it in a project-owned header from `__BYTE_ORDER__`/`_WIN32`/`__BIG_ENDIAN__`, with a compile-time `#error` on the unknown case rather than a silent wrong default.
2. **Entropy source.** Expat wants `getrandom`/`arc4random_buf`/`RtlGenRandom`, and availability differs per platform and glibc version. Getting this wrong is the most common vendoring build failure. Probe in the project-owned `src/expat_config.h`, and make an unknown platform a compile-time `#error`. There is no fallback: `XML_POOR_ENTROPY` is never acceptable, and `XML_SetHashSalt` is not a mitigation (§11).
3. **MinGW printf formats.** Expat's `internal.h` selects MSVC-style `"%I64x"` / `"%I64u"` whenever `_WIN32` is defined and `__USE_MINGW_ANSI_STDIO` is not. Rtools' GCC rejects those under `-Wformat`, which R CMD check escalates to a WARNING and CI to a hard failure. Define `-D__USE_MINGW_ANSI_STDIO=1` in `Makevars` — Expat supports the macro explicitly, so this is configuration, not a patch — and set it there rather than in a header so it precedes any system `stdio.h` in every translation unit.
4. **`src/Makevars`.** No GNU-make-only syntax unless `SystemRequirements: GNU make` is declared — and it is cleaner not to need it. Do not attempt `-Wno-*` suppression for vendored sources; CRAN rejects compiler-flag overrides. Vendor only the parser sources (`xmlparse.c`, `xmltok*.c`, `xmlrole.c`) plus headers. Never vendor `xmlwf`, examples, tests, benchmarks, or the CMake/autotools build.

`R CMD INSTALL` compiles plain `.c` files through R's own toolchain. No CMake, no autotools, at any point.

### Updating

`tools/update-expat <version>` fetches the release tarball and records its SHA-256 (trust on first use, as `PROVENANCE` says). It replaces `src/vendor/expat/` with the files listed in `tools/expat-files.txt`, `COPYING` and `AUTHORS` among them, rewrites `src/vendor/PROVENANCE`, and names the next steps: `tools/verify-vendor`, then `R CMD check`, then fuzzing. It does not run them itself. There is no `tools/patches/`, since no local patch is carried. Rewriting `PROVENANCE` drops its hand-written *Why this version is the floor* and *Known unfixed issues* sections, so restore them by hand. `tools/verify-vendor` re-derives the tree and fails if it differs from what is committed. XML parsers get security releases; this has to be a 10-minute job.

---

## 19. Portability and CRAN

- Project code is portable **C99**. No C++, no Rcpp, no compiler extensions.
- Targets: Windows, macOS, Linux, and other Unix-likes R supports. No system Expat, ever.
- Project-owned code compiles clean under `-Wall -Wextra -Wpedantic`; warnings there are CI failures. Vendored Expat has its own warning policy and is not held to it.
- `src/init.c` registers all entry points and calls `R_useDynamicSymbols(dll, FALSE)`.
- `LICENSE.note` records Expat's MIT license and provenance; package license is MIT, matching Expat and the rest of the `zu*` family.
- `.Rbuildignore` must cover `.agents/`, `tools/`, and any design docs at the root.

---

## 20. Testing

### Correctness

Empty document; single root; attributes; nesting; text; mixed content; CDATA; comments; PIs; XML declaration; UTF-8; UTF-16 LE/BE; namespaces (default, prefixed, nested shadowing, same local name in different namespaces, namespaced attributes, unqualified attributes, declaration scope); empty elements; built-in entities; numeric character references.

The representation must never confuse `{urn:a}item` with `{urn:b}item`.

### Round-trip (the reason §13 is in v1)

For every corpus fixture: `parse → serialize → parse` must produce structurally identical trees. Run as a property test, not a golden-file comparison, since serialization is not lexically faithful by design.

### Chunk independence

Feed every fixture at sizes 1, 2, 3, 7, 31, 4096 bytes and at random boundaries; assert the resulting tree is identical to the whole-buffer parse. Force splits inside: `<`, an element name, an attribute name, an attribute value, a UTF-8 multibyte sequence, an entity reference, a CDATA marker, a closing tag.

### Encoding

BOM and no BOM; UTF-16 LE/BE; declared encodings; declaration conflicting with actual bytes; malformed UTF-8; truncated multibyte sequences; a `windows-1252` document exercising the `iconv` path. Malformed input errors — it never silently substitutes.

### Security (permanent regressions, never deleted)

- **XXE**: `<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><foo>&xxe;</foo>` → hard error, **no file opened, no entity expanded**. Windows analogue with a local path. Assert at the syscall level where the platform allows.
- **Billion laughs** and nested-entity fixtures → DOCTYPE error before expansion can begin.
- Huge depth, huge node count, huge attribute, huge text node → the corresponding `zuxml_limit_error`, never a crash and never an OOM.
- Malformed DOCTYPE; unterminated CDATA; invalid encodings; namespace separator injection (a URI containing `\f` — see §8); cancellation from every handler.
- **No test may perform network I/O.** No test may pass because a file happened to be absent.

### Corpus

Small local fixtures only: Atom, RSS, SOAP, SVG, S3/AWS XML error responses, WebDAV multistatus. Plus the upstream Expat corpus where licensing permits.

### Fuzzing

Targets: whole-document parse, incremental feed, namespace splitting, tree builder, attribute copying, text coalescing, serializer. libFuzzer primary, AFL++ where useful, under ASan + UBSan (MSan where practical). Seed from the corpus and from upstream Expat corpora. Run in CI on a schedule, not only on push.

Built: **three** targets. `fuzz_tree` covers whole-document parse and tree building. `fuzz_feed` covers incremental feed, with the fuzzer choosing the chunk size. `fuzz_roundtrip` covers the serializer, as a fixed point. Namespace splitting, attribute copying and text coalescing are reached through those rather than targeted on their own. Neither MSan nor AFL++ is used, and the seeds are the 22 files in `fuzz/corpus/`, not upstream Expat corpora. `tools/run-fuzz` runs them only after `fuzz/fuzz_canary.c`, which must crash, has shown the gate can see a crash. CI caches the grown corpus between runs.

---

## 21. Performance targets

Not "beat xml2" — `xml2`/libxml2 is a mature, heavily optimized stack and matching it is not the point. The targets are:

| | Target |
|---|---|
| Tree parse throughput | within ~2× of `xml2` on a 1 MiB feed |
| Memory | ≤ 2.5× input size for typical API XML |
| Streaming | throughput independent of chunk size above 4 KiB |
| R object churn | zero R allocations during parsing; handles created lazily on access |
| Install time | seconds, from source, everywhere |

Benchmark fixtures: 1 KiB, 100 KiB API response, 1 MiB feed, 10 MiB synthetic, many-tiny-nodes, large-text-nodes, namespace-heavy. Plus the full `zu*` pipeline — gzip response → `zukomp` streaming → `zuxml` streaming → consumer — at 1/4/16/64 KiB chunks. (No consumer runs that pipeline today, §16, so this fixture is not built.)

The real wins are structural and already decided: parse into a compact C arena with zero R allocation, create R handles lazily, intern names, keep nodesets as one integer vector.

---

## 22. Decisions (the former open questions)

| # | Question | Decision |
|---|---|---|
| 1 | Expat release | Pinned 2.8.4; floor 2.8.4 (fixes 4 CVEs, incl. the entropy one) |
| 2 | Source subset | `xmlparse.c`, `xmltok*.c`, `xmlrole.c` + headers; nothing else |
| 3 | DTD: compiled out or runtime-rejected | **Both.** `XML_DTD` undefined; DOCTYPE also rejected at runtime |
| 4 | Entity configuration | Built-ins + numeric refs only. Undefined entity = error. **Open sub-question:** whether phase 2 adds an opt-in HTML named-entity table via a documented lexical pre-pass (Expat cannot do it without `XML_DTD`) or leaves it to `zuhtml`. Decide on user reports. |
| 5 | Always error on DOCTYPE | Default yes. `doctype = TRUE` accepts a bare/PUBLIC/SYSTEM declaration but never an internal subset |
| 6 | Limit defaults | §11 table |
| 7 | Retain comments/PIs | Yes, and **on by default** — general XML library first |
| 8 | Discard CDATA boundaries | Yes |
| 9 | Node id width | `uint32_t`, capped at `INT_MAX` |
| 10 | Arena shape | Growable index-addressed arrays, not a block arena |
| 11 | Document representation | External pointer with finalizer |
| 12 | Node handle | Integer vector + `doc` attribute; node and nodeset are one type |
| 13 | R streaming model | Pull/batched, phase 2. No callback-per-event API. |
| 14 | Namespace prefixes | Retained for serialization; matching is `(uri, local)` only |
| 15 | Serializer in v1 | Yes — it is the round-trip test oracle |
| 16 | `zuhttp` dependency | `Suggests` |
| 17 | `resp_xml()` type check | Yes, with `check_type = FALSE` override |
| 18 | Parse during transfer | Phase 3 |
| 19 | XML vs HTTP encoding | §10 precedence; HTTP charset arrives as `encoding=` and wins |
| 20 | Expat allocator | libc default |
| 21 | HTML | Out of scope; sibling `zuhtml` on the shared event seam (§17) |

---

## 23. Acceptance criteria for v1

1. Builds from source on standard R toolchains for Windows, macOS, and Linux with no system Expat and no CMake/autotools.
2. Parsing is byte-for-byte independent of input chunk boundaries.
3. Namespace-aware parsing is correct, including shadowing and unqualified attributes.
4. Mixed-content ordering is preserved exactly.
5. External entities never cause filesystem or network access — verified structurally (`XML_DTD` off) and by permanent regression test.
6. Every oversized or malformed input fails through an explicit, classed error; none crashes, hangs, or aborts on OOM.
7. Parse errors carry line, column, and byte offset in an R condition.
8. Round-trip (`parse → serialize → parse`) is structurally identical across the whole corpus.
9. Fuzzing under ASan/UBSan finds no memory-safety failure in project-owned code over a sustained run.
10. `inst/include/zuxml.h` exposes no Expat type; a fixture package consumes zuxml through `LinkingTo` plus `libzuxml.a` successfully, with zuxml uninstalled at run time.

    **10b.** A fixture package, `tools/zuxmltable`, consumes the registered table through `Imports:` + `LinkingTo:` + an `importFrom()` directive and calls every `zuxml_api` member, linking no Expat symbol (#36).
11. Vendored Expat provenance is recorded and `tools/verify-vendor` reproduces the tree.
12. `R CMD check --as-cran` is clean on all three platforms.

---

## 24. Summary

```text
                      zuxml
                        │
              R navigation API  (vectorized, ~21 functions)
                        │
         immutable tree — index-addressed arena
                        │
        ══════ zux_handlers: the event seam ══════
                        │
                 vendored Expat  (no DTD, no external entities)
                        │
                      bytes
```

> **`zuxml` is a small, strict, secure XML parser and tree for R — not a replacement for the XML ecosystem.**

Its value to other packages' C code is safe incremental parsing of untrusted XML with no libxml2 dependency. Code already written against Expat gets the archive instead, and with it only the compile-time half of that safety (§15). Its value on its own is that ordinary XML work in R gets an intuitive, vectorized API over a faithful tree. The event seam is what lets both of those, plus HTML later, share one implementation.

---

## 25. Position in the `zu*` family (reviewed 2026-09-22)

This table is identical in all five repositories' design documents. Change it in all five
together, or not at all.

| | zukomp | zuxml | zucrypt | zuxlsx | zuhttp |
|---|---|---|---|---|---|
| Role | provider | provider | provider | consumer | standalone |
| R prefix | `komp_` | `xml_` | `crypt_` | `read_xlsx()`, `xlsx_` | `zu_` |
| Info function | `komp_info()` | `zuxml_info()` | `crypt_info()` | `zuxlsx_native()` ([zuxlsx#46](https://github.com/pedrobtz/zuxlsx/issues/46)) | `zu_info()` |
| Root condition class | `zukomp_error` | `zuxml_error` | `zucrypt_error` | `zuxlsx_error` | `zu_error` ([zuhttp#19](https://github.com/pedrobtz/zuhttp/issues/19)) |
| Public C prefix | `zu_` / `ZU_` | `zux_` / `ZUX_` | `zuc_` / `ZUC_` | none | none — but the internal C code uses `zu_` and collides with `zukomp.h` ([zuhttp#15](https://github.com/pedrobtz/zuhttp/issues/15)) |
| Registered table | `zukomp_get_api(version)` via `zukomp-r.h` | `zuxml_api_v2` via `ZUXML_DEFINE_API_GET` in `zuxml.h` ([zuxml#36](https://github.com/pedrobtz/zuxml/issues/36)) | `zucrypt_get_api(version)` via `zucrypt-r.h` | — | — |
| Table consumers today | none (fixture `tools/zukomptest`) | none (no fixture) | none (fixture `tests/consumer/zucrypttest`) | — | — |
| Static archive | `lib${R_ARCH}/libzukomp.a` + `miniz.h` | `lib/libzuxml.a` + `expat.h`, `expat_external.h` | `lib/libzucrypt.a` + `zucrypt.h` | — | — |
| Archive consumers today | zuxlsx (miniz ZIP reader only); fixture `tools/zukomplink` | zuxlsx (xlsxio); fixture `tools/zuxmltest` | none; zuxlsx 0.2.0 agile decryption ([zuxlsx#22](https://github.com/pedrobtz/zuxlsx/issues/22)); no fixture package ([zucrypt#32](https://github.com/pedrobtz/zucrypt/issues/32)) | — | — |
| Upstream licence installed | `licenses/miniz-LICENSE` | no ([zuxml#42](https://github.com/pedrobtz/zuxml/issues/42)) | no ([zucrypt#33](https://github.com/pedrobtz/zucrypt/issues/33)) | Expat's and miniz's in `inst/licenses/`; xlsxio's not ([zuxlsx#62](https://github.com/pedrobtz/zuxlsx/issues/62)) | no: vendored picohttpparser and uriparser ([zuhttp#52](https://github.com/pedrobtz/zuhttp/issues/52)); zlib and TLS are system libraries |
| Symbols hidden (`$(C_VISIBILITY)`) | no ([zukomp#34](https://github.com/pedrobtz/zukomp/issues/34)) | no ([zuxml#39](https://github.com/pedrobtz/zuxml/issues/39)) | yes, audited | no | no ([zuhttp#15](https://github.com/pedrobtz/zuhttp/issues/15)) |
| r-actions pin | commit, v1.7.0 | mostly floating `@v1` ([zuxml#39](https://github.com/pedrobtz/zuxml/issues/39)) | commit, v1.9.0 | not used ([zuxlsx#44](https://github.com/pedrobtz/zuxlsx/issues/44)) | coverage only, `@v1` ([zuhttp#18](https://github.com/pedrobtz/zuhttp/issues/18)) |
| `Depends: R` | 4.0 | 4.1 | 4.1 | 4.1 | 3.5 |

**Relationships, as decided rather than as hoped:**

- **zuhttp consumes no sibling in 0.x.** Compression is system zlib (zuhttp D-7, accepted
  2026-09-07). Pin digests come from the TLS backend: OpenSSL computes them today, and
  macOS and Windows refuse pins until SubjectPublicKeyInfo extraction lands
  ([zuhttp#4](https://github.com/pedrobtz/zuhttp/issues/4), [zuhttp#12](https://github.com/pedrobtz/zuhttp/issues/12)). zuxml could at most
  be a `Suggests:` for a future `zu_resp_xml()`. So zukomp's criterion 11 is deferred beyond 0.1.0
  ([zukomp#32](https://github.com/pedrobtz/zukomp/issues/32)), and zucrypt's hope of a
  table-mode consumer in zuhttp ([zucrypt#14](https://github.com/pedrobtz/zucrypt/issues/14))
  has no taker today.
- **zuxlsx is the only real consumer in the family**, and it consumes archives only: zuxml's
  Expat and zukomp's miniz ZIP reader now, and zucrypt's primitives for agile decryption in
  0.2.0. None of zukomp's codec registry, stream driver or `max_output`/`max_ratio` limits
  reaches zuxlsx. Standard (ECB) encryption is out of scope there, so zucrypt's ECB has no
  consumer ([zucrypt#29](https://github.com/pedrobtz/zucrypt/issues/29)).
- **No sibling uses any registered table.** All three tables are proven only by fixtures (or,
  for zuxml, not at all). That is an argument for keeping each table small and marked as the
  part most likely to change before a first consumer exists.
- **An archive fix reaches a consumer only when the consumer is rebuilt.** A security bump
  in Expat, miniz or TF-PSA-Crypto therefore means re-releasing zuxlsx too
  ([zuxlsx#15](https://github.com/pedrobtz/zuxlsx/issues/15)).

**Convergence targets** (each tracked where the change has to happen):

- Archives install under `lib${R_ARCH}`, with the upstream licence under `licenses/` and every
  `file.copy()` checked, as zukomp does ([zuxml#42](https://github.com/pedrobtz/zuxml/issues/42),
  [zucrypt#33](https://github.com/pedrobtz/zucrypt/issues/33)).
- Table resolvers follow `zukomp-r.h`: a pure-C99 `<pkg>.h` with an R-only `<pkg>-r.h`, a
  union cast of `DL_FUNC`, lazy resolution, and NULL on a version mismatch.
- Only `R_init_<pkg>` is exported from each shared object.
- Each consumer shape has one fixture package under `tools/` that runs on all three OSes.
  A plain `main()` does not count ([zucrypt#32](https://github.com/pedrobtz/zucrypt/issues/32)).
- Providers that zuxlsx tracks at `@main` build zuxlsx in CI
  ([zukomp#35](https://github.com/pedrobtz/zukomp/issues/35), [zuxml#39](https://github.com/pedrobtz/zuxml/issues/39)).
- `main` carries a `.9000` development version between releases, so a consumer can test a
  version instead of probing for files.
- **CRAN order:** zuxml and zukomp first, then zuxlsx 0.1.0. zucrypt must reach CRAN before
  zuxlsx 0.2.0 (decryption). zuhttp is independent.
