/* zuxml: the event seam over Expat.
 *
 * Everything Expat-specific lives here. Consumers above see only zux.h.
 * Security policy and the resource limits are enforced at this layer so that
 * every consumer -- tree builder, zuhttp, anything later -- inherits them
 * rather than reimplementing them. See design sections 3 and 11.
 */

#include <stdlib.h>
#include <string.h>

#include "expat_config.h"
#include "vendor/expat/expat.h"
#include "zux.h"

/* Namespace separator. 0x0C (form feed) is not a legal XML 1.0 Char, so it
 * can appear neither literally nor via a character reference in a
 * well-formed document -- Expat rejects such input before we see it. That is
 * what makes the separator count authoritative when splitting a triplet.
 * See zux_split_name() and design section 8. */
#define ZUX_NS_SEP '\f'

#define ZUX_TEXT_CHUNK 4096

struct zux_parser {
  XML_Parser xp;
  zux_options opt;
  zux_handlers h;
  void *ctx;

  /* First error wins; later Expat aborts must not overwrite the real cause. */
  zux_status status;
  int expat_code;
  uint64_t line, column, byte_offset;
  char message[256];

  uint32_t depth;
  uint32_t nodes;

  char *text;
  size_t text_len, text_cap;

  zux_attr *attrs;
  size_t attrs_cap;

  size_t mem_used;

  int finished;
};

void
zux_options_init(zux_options *opt) {
  if (opt == NULL)
    return;
  opt->max_depth = 256u;
  opt->max_nodes = 10000000u;
  opt->max_attrs = 4096u;
  opt->max_text = (size_t)64 * 1024 * 1024;
  opt->max_memory = (size_t)1024 * 1024 * 1024;
  opt->encoding = NULL;
  opt->allow_doctype = 0;
  opt->keep_comments = 1;
  opt->keep_pis = 1;
}

const char *
zux_status_string(zux_status s) {
  switch (s) {
  case ZUX_OK: return "ok";
  case ZUX_DONE: return "done";
  case ZUX_ERR_INVALID_ARGUMENT: return "invalid argument";
  case ZUX_ERR_INVALID_XML: return "invalid XML";
  case ZUX_ERR_ENCODING: return "invalid or unsupported encoding";
  case ZUX_ERR_DOCTYPE: return "document type declaration is not allowed";
  case ZUX_ERR_UNDEFINED_ENTITY: return "undefined entity reference";
  case ZUX_ERR_DEPTH_LIMIT: return "maximum nesting depth exceeded";
  case ZUX_ERR_NODE_LIMIT: return "maximum node count exceeded";
  case ZUX_ERR_ATTR_LIMIT: return "maximum attribute count exceeded";
  case ZUX_ERR_TEXT_LIMIT: return "maximum text size exceeded";
  case ZUX_ERR_MEMORY_LIMIT: return "memory limit exceeded";
  case ZUX_ERR_MEMORY: return "out of memory";
  case ZUX_ERR_CANCELLED: return "cancelled by handler";
  case ZUX_ERR_INTERNAL: return "internal error";
  }
  return "unknown status";
}

void
zux_set_message(zux_error *e, const char *msg) {
  if (e == NULL)
    return;
  if (msg == NULL)
    msg = "";
  strncpy(e->message, msg, ZUX_MESSAGE_MAX - 1);
  e->message[ZUX_MESSAGE_MAX - 1] = '\0';
}

/* Record the first failure and stop Expat. Position is captured here, while
 * the parser still points at the offending construct. */
static void
zux_fail(zux_parser *p, zux_status s, const char *msg) {
  if (p->status != ZUX_OK)
    return;
  p->status = s;
  p->line = (uint64_t)XML_GetCurrentLineNumber(p->xp);
  p->column = (uint64_t)XML_GetCurrentColumnNumber(p->xp);
  p->byte_offset = (uint64_t)XML_GetCurrentByteIndex(p->xp);
  p->expat_code = (int)XML_GetErrorCode(p->xp);
  if (msg == NULL)
    msg = zux_status_string(s);
  strncpy(p->message, msg, sizeof(p->message) - 1);
  p->message[sizeof(p->message) - 1] = '\0';
  XML_StopParser(p->xp, XML_FALSE);
}

/* Split Expat's "uri SEP local SEP prefix" triplet into borrowed fields.
 *
 * Split from the RIGHT, because the URI is the leftmost field and is the
 * only one that could in principle contain a separator; local names and
 * prefixes are XML Names and cannot. Combined with the impossibility of a
 * literal 0x0C in well-formed XML 1.0, this is unambiguous. */
static void
zux_split_name(const char *s, zux_name *out) {
  size_t len = strlen(s);
  size_t seps = 0;
  size_t last = 0, prev = 0;
  size_t i;

  memset(out, 0, sizeof(*out));

  for (i = 0; i < len; i++) {
    if (s[i] == ZUX_NS_SEP) {
      prev = last;
      last = i;
      seps++;
    }
  }

  if (seps == 0) {
    out->local.ptr = s;
    out->local.len = len;
    return;
  }
  if (seps == 1) {
    out->uri.ptr = s;
    out->uri.len = last;
    out->local.ptr = s + last + 1;
    out->local.len = len - last - 1;
    return;
  }
  /* Two or more: prefix after the last separator, local between the last
   * two, URI everything before -- separators included, defensively. */
  out->uri.ptr = s;
  out->uri.len = prev;
  out->local.ptr = s + prev + 1;
  out->local.len = last - prev - 1;
  out->prefix.ptr = s + last + 1;
  out->prefix.len = len - last - 1;
}

static int
zux_charge(zux_parser *p, size_t delta) {
  if (delta > p->opt.max_memory - p->mem_used) {
    zux_fail(p, ZUX_ERR_MEMORY_LIMIT, NULL);
    return 0;
  }
  p->mem_used += delta;
  return 1;
}

static int
zux_count_node(zux_parser *p) {
  if (p->nodes >= p->opt.max_nodes) {
    zux_fail(p, ZUX_ERR_NODE_LIMIT, NULL);
    return 0;
  }
  p->nodes++;
  return 1;
}

/* Emit and reset any buffered character data. Called before every non-text
 * event and at finish, so text nodes are maximal. */
static int
zux_flush_text(zux_parser *p) {
  zux_str t;
  zux_status rc;

  if (p->text_len == 0)
    return 1;
  if (! zux_count_node(p)) {
    p->text_len = 0;
    return 0;
  }
  if (p->h.text != NULL) {
    t.ptr = p->text;
    t.len = p->text_len;
    rc = p->h.text(p->ctx, t);
    if (rc != ZUX_OK) {
      p->text_len = 0;
      zux_fail(p, rc, NULL);
      return 0;
    }
  }
  p->text_len = 0;
  return 1;
}

static void XMLCALL
on_text(void *user, const XML_Char *s, int len) {
  zux_parser *p = (zux_parser *)user;
  size_t need;

  if (p->status != ZUX_OK || len <= 0)
    return;

  /* Enforced on every append, not once at the end: checking after the fact
   * would let an attacker allocate freely before the limit ever trips. */
  if ((size_t)len > p->opt.max_text - p->text_len) {
    zux_fail(p, ZUX_ERR_TEXT_LIMIT, NULL);
    return;
  }

  need = p->text_len + (size_t)len;
  if (need > p->text_cap) {
    size_t cap = p->text_cap ? p->text_cap : ZUX_TEXT_CHUNK;
    char *grown;
    while (cap < need) {
      if (cap > p->opt.max_text - cap) {
        cap = need;
        break;
      }
      cap *= 2;
    }
    if (! zux_charge(p, cap - p->text_cap))
      return;
    grown = (char *)realloc(p->text, cap);
    if (grown == NULL) {
      zux_fail(p, ZUX_ERR_MEMORY, NULL);
      return;
    }
    p->text = grown;
    p->text_cap = cap;
  }
  memcpy(p->text + p->text_len, s, (size_t)len);
  p->text_len = need;
}

static void XMLCALL
on_start(void *user, const XML_Char *name, const XML_Char **atts) {
  zux_parser *p = (zux_parser *)user;
  size_t n = 0, i;
  zux_name qname;
  zux_status rc;

  if (p->status != ZUX_OK)
    return;
  if (! zux_flush_text(p))
    return;

  if ((uint32_t)(p->depth + 1u) > p->opt.max_depth) {
    zux_fail(p, ZUX_ERR_DEPTH_LIMIT, NULL);
    return;
  }
  if (! zux_count_node(p))
    return;

  while (atts[2 * n] != NULL)
    n++;
  if (n > (size_t)p->opt.max_attrs) {
    zux_fail(p, ZUX_ERR_ATTR_LIMIT, NULL);
    return;
  }

  if (n > p->attrs_cap) {
    zux_attr *grown;
    if (! zux_charge(p, (n - p->attrs_cap) * sizeof(zux_attr)))
      return;
    grown = (zux_attr *)realloc(p->attrs, n * sizeof(zux_attr));
    if (grown == NULL) {
      zux_fail(p, ZUX_ERR_MEMORY, NULL);
      return;
    }
    p->attrs = grown;
    p->attrs_cap = n;
  }
  for (i = 0; i < n; i++) {
    zux_split_name(atts[2 * i], &p->attrs[i].name);
    p->attrs[i].value.ptr = atts[2 * i + 1];
    p->attrs[i].value.len = strlen(atts[2 * i + 1]);
  }

  p->depth++;
  zux_split_name(name, &qname);
  if (p->h.start_element != NULL) {
    rc = p->h.start_element(p->ctx, &qname, p->attrs, n);
    if (rc != ZUX_OK)
      zux_fail(p, rc, NULL);
  }
}

static void XMLCALL
on_end(void *user, const XML_Char *name) {
  zux_parser *p = (zux_parser *)user;
  zux_name qname;
  zux_status rc;

  if (p->status != ZUX_OK)
    return;
  if (! zux_flush_text(p))
    return;
  if (p->depth > 0)
    p->depth--;

  zux_split_name(name, &qname);
  if (p->h.end_element != NULL) {
    rc = p->h.end_element(p->ctx, &qname);
    if (rc != ZUX_OK)
      zux_fail(p, rc, NULL);
  }
}

static void XMLCALL
on_comment(void *user, const XML_Char *data) {
  zux_parser *p = (zux_parser *)user;
  zux_str t;
  zux_status rc;

  if (p->status != ZUX_OK)
    return;
  if (! zux_flush_text(p))
    return;
  if (! p->opt.keep_comments || p->h.comment == NULL)
    return;
  if (! zux_count_node(p))
    return;
  t.ptr = data;
  t.len = strlen(data);
  rc = p->h.comment(p->ctx, t);
  if (rc != ZUX_OK)
    zux_fail(p, rc, NULL);
}

static void XMLCALL
on_pi(void *user, const XML_Char *target, const XML_Char *data) {
  zux_parser *p = (zux_parser *)user;
  zux_str t, d;
  zux_status rc;

  if (p->status != ZUX_OK)
    return;
  if (! zux_flush_text(p))
    return;
  if (! p->opt.keep_pis || p->h.pi == NULL)
    return;
  if (! zux_count_node(p))
    return;
  t.ptr = target;
  t.len = strlen(target);
  d.ptr = data == NULL ? "" : data;
  d.len = data == NULL ? 0 : strlen(data);
  rc = p->h.pi(p->ctx, t, d);
  if (rc != ZUX_OK)
    zux_fail(p, rc, NULL);
}

static void XMLCALL
on_xmldecl(void *user, const XML_Char *version, const XML_Char *encoding,
           int standalone) {
  zux_parser *p = (zux_parser *)user;
  zux_str v, e;
  zux_status rc;

  if (p->status != ZUX_OK || p->h.xml_decl == NULL)
    return;
  v.ptr = version == NULL ? "" : version;
  v.len = version == NULL ? 0 : strlen(version);
  e.ptr = encoding == NULL ? "" : encoding;
  e.len = encoding == NULL ? 0 : strlen(encoding);
  rc = p->h.xml_decl(p->ctx, v, e, standalone);
  if (rc != ZUX_OK)
    zux_fail(p, rc, NULL);
}

/* Defence in depth. Expat is built with XML_GE 0 and no XML_DTD, so there is
 * no entity machinery to exploit; rejecting DOCTYPE here too makes the policy
 * visible and testable rather than implicit in a compile flag.
 *
 * An internal subset is rejected even when allow_doctype is set. With
 * XML_GE 0 Expat does not record entity declarations, and a reference to one
 * is then passed through as literal text -- "&e;" arrives as four characters
 * of content instead of an error, so the document is silently wrong and a
 * later serialize would re-escape it to "&amp;e;". The internal subset is the
 * only place a document can declare entities, so refusing it removes that
 * corruption entirely while still accepting the bare and PUBLIC/SYSTEM
 * DOCTYPEs that real feeds actually carry. Entity bombs live in the internal
 * subset too, so they are rejected on the same rule. */
static void XMLCALL
on_doctype(void *user, const XML_Char *name, const XML_Char *sysid,
           const XML_Char *pubid, int has_internal_subset) {
  zux_parser *p = (zux_parser *)user;
  (void)name;
  (void)sysid;
  (void)pubid;
  if (p->status != ZUX_OK)
    return;
  if (! p->opt.allow_doctype) {
    zux_fail(p, ZUX_ERR_DOCTYPE, NULL);
    return;
  }
  if (has_internal_subset)
    zux_fail(p, ZUX_ERR_DOCTYPE,
             "document type declaration with an internal subset is not allowed");
}


/* Expat "skips" an entity reference it has no definition for whenever a DTD
 * was present but could not be processed. Rejecting internal subsets in
 * on_doctype() is what actually closes the pass-through-as-text hole; this
 * handler is a belt-and-braces guard so that if any other path ever skips an
 * entity, it surfaces as an error rather than as missing content. */
static void XMLCALL
on_skipped_entity(void *user, const XML_Char *name, int is_param) {
  zux_parser *p = (zux_parser *)user;
  (void)name;
  (void)is_param;
  if (p->status != ZUX_OK)
    return;
  zux_fail(p, ZUX_ERR_UNDEFINED_ENTITY, NULL);
}

zux_status
zux_parser_new(zux_parser **out, const zux_options *opt, const zux_handlers *h,
               void *ctx) {
  zux_parser *p;
  zux_options defaults;

  if (out == NULL)
    return ZUX_ERR_INVALID_ARGUMENT;
  *out = NULL;

  if (opt == NULL) {
    zux_options_init(&defaults);
    opt = &defaults;
  }
  if (opt->max_depth == 0u || opt->max_nodes == 0u || opt->max_text == 0u
      || opt->max_memory == 0u)
    return ZUX_ERR_INVALID_ARGUMENT;

  p = (zux_parser *)calloc(1, sizeof(*p));
  if (p == NULL)
    return ZUX_ERR_MEMORY;

  p->opt = *opt;
  if (h != NULL)
    p->h = *h;
  p->ctx = ctx;
  p->status = ZUX_OK;

  /* Namespace-aware, returning the full uri/local/prefix triplet. */
  p->xp = XML_ParserCreateNS(opt->encoding, (XML_Char)ZUX_NS_SEP);
  if (p->xp == NULL) {
    free(p);
    return ZUX_ERR_MEMORY;
  }
  XML_SetReturnNSTriplet(p->xp, XML_TRUE);
  XML_SetUserData(p->xp, p);
  XML_SetElementHandler(p->xp, on_start, on_end);
  XML_SetCharacterDataHandler(p->xp, on_text);
  XML_SetCommentHandler(p->xp, on_comment);
  XML_SetProcessingInstructionHandler(p->xp, on_pi);
  XML_SetXmlDeclHandler(p->xp, on_xmldecl);
  XML_SetStartDoctypeDeclHandler(p->xp, on_doctype);
  XML_SetSkippedEntityHandler(p->xp, on_skipped_entity);
  /* No XML_SetHashSalt: Expat already salts from the OS entropy backend
   * chosen in src/expat_config.h, which is the strongest source we have. */

  *out = p;
  return ZUX_OK;
}

/* Translate an Expat failure into a project status, preserving any richer
 * cause we already recorded (limits, cancellation, DOCTYPE). */
static void
zux_absorb_expat_error(zux_parser *p) {
  enum XML_Error code;

  if (p->status != ZUX_OK)
    return;
  code = XML_GetErrorCode(p->xp);
  switch (code) {
  case XML_ERROR_UNDEFINED_ENTITY:
  case XML_ERROR_RECURSIVE_ENTITY_REF:
  case XML_ERROR_PARAM_ENTITY_REF:
    zux_fail(p, ZUX_ERR_UNDEFINED_ENTITY, XML_ErrorString(code));
    break;
  case XML_ERROR_UNKNOWN_ENCODING:
  case XML_ERROR_INCORRECT_ENCODING:
    zux_fail(p, ZUX_ERR_ENCODING, XML_ErrorString(code));
    break;
  case XML_ERROR_ABORTED:
    zux_fail(p, ZUX_ERR_INTERNAL, "parser aborted without a recorded cause");
    break;
  default:
    zux_fail(p, ZUX_ERR_INVALID_XML, XML_ErrorString(code));
    break;
  }
}

zux_status
zux_parser_feed(zux_parser *p, const void *data, size_t n) {
  if (p == NULL)
    return ZUX_ERR_INVALID_ARGUMENT;
  if (p->status != ZUX_OK)
    return p->status;
  if (p->finished)
    return ZUX_ERR_INVALID_ARGUMENT;
  if (n > (size_t)0x7fffffff)
    return ZUX_ERR_INVALID_ARGUMENT;

  if (XML_Parse(p->xp, (const char *)data, (int)n, 0) == XML_STATUS_ERROR)
    zux_absorb_expat_error(p);
  return p->status;
}

zux_status
zux_parser_finish(zux_parser *p) {
  if (p == NULL)
    return ZUX_ERR_INVALID_ARGUMENT;
  if (p->status != ZUX_OK)
    return p->status;
  if (p->finished)
    return ZUX_DONE;
  p->finished = 1;

  if (XML_Parse(p->xp, "", 0, 1) == XML_STATUS_ERROR) {
    zux_absorb_expat_error(p);
    return p->status;
  }
  if (! zux_flush_text(p))
    return p->status;
  return p->status == ZUX_OK ? ZUX_DONE : p->status;
}

void
zux_parser_error(const zux_parser *p, zux_error *out) {
  if (p == NULL || out == NULL)
    return;
  out->status = p->status;
  out->line = p->line;
  out->column = p->column;
  out->byte_offset = p->byte_offset;
  out->expat_code = p->expat_code;
  /* Copied, never borrowed: see the note on zux_error in zuxml.h. */
  zux_set_message(out, p->message[0] ? p->message
                                     : zux_status_string(p->status));
}

void
zux_parser_free(zux_parser *p) {
  if (p == NULL)
    return;
  if (p->xp != NULL)
    XML_ParserFree(p->xp);
  free(p->text);
  free(p->attrs);
  free(p);
}
