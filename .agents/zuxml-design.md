# zuxml — Design

**Status:** Design agreed, pre-implementation
**Package:** `zuxml`
**One line:** A small, strict, secure XML parser and immutable tree for R, vendoring Expat, usable standalone and as the XML backend for `zuhttp`.
**Supersedes:** `design-zuxml.md` (delete once this is accepted).

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
- **`zuhttp` and sibling C consumers** — the event API and a registered C-callable table.

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
| Tree construction / mutation | | yes | |
| R pull/streaming API | | yes | R callback-per-event API |
| `xml_as_list()` | | yes (lossy, documented) | as the default return |
| `zuhttp::resp_xml()` | | yes | |
| HTML parsing | | see §17 — separate package | inside zuxml |
| XPath / XSLT / schema / XInclude / DTD validation | | | |
| External entity resolution, catalogs | | | |

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
 builder   (zuhttp)
    │
    ▼
 zux_document  ──►  R handles  ──►  R navigation API
```

Three rules that follow from this and are non-negotiable:

1. **No Expat type ever appears in a `zuxml` header.** Not `XML_Parser`, not `XML_Char`, not an Expat error code.
2. **The tree builder is an ordinary consumer of `zux_handlers`.** It gets no privileged access. This is what makes a second producer (HTML, or a future Expat replacement) a bounded piece of work rather than a rewrite.
3. **Limits and security policy live at the seam**, not in the tree builder, so every consumer inherits them.

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
```

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

If `encoding=` names something Expat cannot handle, transcode the whole input to UTF-8 with `iconv()` **before** feeding, then pass `encoding = "UTF-8"` explicitly so the now-stale declaration is overridden. Streaming inputs cannot be transcoded blind mid-stream, so a non-Expat encoding on the streaming path is an error, not a silent guess.

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
- `DOCTYPE` is rejected by default via `XML_SetStartDoctypeDeclHandler` → `zuxml_doctype_error`. `doctype = TRUE` accepts and *ignores* the declaration; it never defines entities.

Additionally: call `XML_SetHashSalt()` with per-parser entropy to blunt hash-flooding.

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

Every condition carries `line`, `column`, `byte_offset`, `expat_code`, and for `zuxml_limit_error` the limit name and its value.

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

One versioned table, registered with `R_RegisterCCallable("zuxml", "zuxml_api")`.

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

`struct_size` is the sole version discriminator — the previous draft carried three overlapping schemes (`ZUXML_API_VERSION`, `abi_version`, `struct_size`). A consumer compares `struct_size` against the offset of the member it wants and degrades gracefully. Fields are only ever appended, never reordered or removed.

Downstream declares `Imports: zuxml` (guarantees the package is installed and loaded, so the symbols are registered) and `LinkingTo: zuxml` (exposes `inst/include/zuxml.h`). No downstream package ever links against Expat.

---

## 16. `zuhttp` integration

Boundary: **`zuhttp` owns bytes and content types. `zuxml` owns XML semantics and knows nothing about HTTP.**

```text
TLS → HTTP framing → Content-Encoding → [zudeflate] → bytes → zuxml → tree/events
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

Pin **Expat 2.7.x, minimum 2.7.1**. Rationale for the floor: 2.7.0 fixed CVE-2024-8176 (stack overflow via deeply nested entities). Verify the current release at vendoring time and record it. Never track `master`.

Record in `src/vendor/expat/PROVENANCE`: upstream repo, release tag, commit SHA, tarball SHA-256, import date, license, local patches, compile configuration.

### Configuration

| Setting | Value | Why |
|---|---|---|
| `XML_Char` | `char` (UTF-8) | natural bridge to `mkCharLenCE(CE_UTF8)` |
| `XML_DTD` | **not defined** | §11 — removes the entire XXE/amplification class |
| `XML_NS` | defined | §8 |
| `XML_GE` | not defined | follows from no DTD |
| `XML_CONTEXT_BYTES` | 1024 | enough for error context, bounded |
| `BYTEORDER` | 1234/4321, set portably | see below |
| Allocator | libc default | Expat frees individually; routing through the arena does not fit, and routing through R risks `longjmp`. `XML_Memory_Handling_Suite` reserved for future accounting. |

### The three portability traps

These are the specific things that break Expat vendoring, named so CI does not have to discover them:

1. **`BYTEORDER`.** Expat's `expat_config.h` requires it. Do not copy a generated header from one machine. Derive it in a project-owned header from `__BYTE_ORDER__`/`_WIN32`/`__BIG_ENDIAN__`, with a compile-time `#error` on the unknown case rather than a silent wrong default.
2. **Entropy source.** Expat wants `getrandom`/`arc4random_buf`/`RtlGenRandom`, and availability differs per platform and glibc version. Getting this wrong is the most common vendoring build failure. Probe in a project-owned header and fall back to `XML_POOR_ENTROPY` with a documented consequence (weaker hash-salt only — mitigated by `XML_SetHashSalt` in §11).
3. **`src/Makevars`.** No GNU-make-only syntax unless `SystemRequirements: GNU make` is declared — and it is cleaner not to need it. Do not attempt `-Wno-*` suppression for vendored sources; CRAN rejects compiler-flag overrides. Vendor only the parser sources (`xmlparse.c`, `xmltok*.c`, `xmlrole.c`) plus headers. Never vendor `xmlwf`, examples, tests, benchmarks, or the CMake/autotools build.

`R CMD INSTALL` compiles plain `.c` files through R's own toolchain. No CMake, no autotools, at any point.

### Updating

`tools/update-expat` — fetch the pinned release, verify SHA-256, extract the parser subset, install `COPYING`, reapply ordered patches from `tools/patches/`, regenerate `PROVENANCE`, run the portability and fuzz suites, print a diff summary. `tools/verify-vendor` re-derives the tree and fails if it differs from what is committed. XML parsers get security releases; this has to be a 10-minute job.

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

Benchmark fixtures: 1 KiB, 100 KiB API response, 1 MiB feed, 10 MiB synthetic, many-tiny-nodes, large-text-nodes, namespace-heavy. Plus the full `zu*` pipeline — gzip response → `zudeflate` streaming → `zuxml` streaming → consumer — at 1/4/16/64 KiB chunks.

The real wins are structural and already decided: parse into a compact C arena with zero R allocation, create R handles lazily, intern names, keep nodesets as one integer vector.

---

## 22. Decisions (the former open questions)

| # | Question | Decision |
|---|---|---|
| 1 | Expat release | 2.7.x, floor 2.7.1 (CVE-2024-8176) |
| 2 | Source subset | `xmlparse.c`, `xmltok*.c`, `xmlrole.c` + headers; nothing else |
| 3 | DTD: compiled out or runtime-rejected | **Both.** `XML_DTD` undefined; DOCTYPE also rejected at runtime |
| 4 | Entity configuration | Built-ins + numeric refs only. Undefined entity = error. **Open sub-question:** whether phase 2 adds an opt-in HTML named-entity table via a documented lexical pre-pass (Expat cannot do it without `XML_DTD`) or leaves it to `zuhtml`. Decide on user reports. |
| 5 | Always error on DOCTYPE | Default yes; `doctype = TRUE` accepts and ignores |
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
10. `inst/include/zuxml.h` exposes no Expat type; a fixture package consumes the C API through `Imports` + `LinkingTo` successfully.
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

Its value to `zuhttp` is safe incremental parsing of untrusted XML with no libxml2 dependency. Its value on its own is that ordinary XML work in R gets an intuitive, vectorized API over a faithful tree. The event seam is what lets both of those, plus HTML later, share one implementation.
