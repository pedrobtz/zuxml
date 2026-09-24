/* zu_source.h -- a byte source over a raw vector or an R connection.
 *
 * Origin: zuxml 0.1.0, src/zu_source.h. This file is meant to be copied
 * verbatim into sibling packages (zuhtml, zujson, zuyaml); keep this line
 * current so drift between copies is visible. It depends on R's headers
 * only and knows nothing about the parser it feeds.
 *
 * A parser wants bytes in pieces. From R those pieces come either from a
 * raw vector already in memory or from a connection -- a file, a url(), a
 * gzfile(), a socket -- read as it goes, so the body is never held whole.
 * This header hides which, behind one read call:
 *
 *   zu_source s = zu_source_raw(x);                       // or
 *   zu_source s = zu_source_connection(scon, 65536);
 *   while ((n = zu_source_read(&s, &chunk)) > 0) feed(chunk, n);
 *
 * or, for a push parser, zu_source_pump(&s, sink, ctx).
 *
 * Rules the caller must respect:
 *
 * - zu_source_read() on a connection runs R code: it checks for a user
 *   interrupt and then calls R_ReadConnection(), which may raise an R
 *   error (a dropped network connection) and longjmp out. So call it only
 *   where a longjmp is safe -- between feeds of a push parser, never from
 *   inside a parser callback -- and run the whole loop under
 *   R_UnwindProtect() with a cleanup that frees the parser. A raw-vector
 *   source never longjmps except for the interrupt check.
 * - A pull parser (libyaml-style) that calls zu_source_read() from its own
 *   read handler gets the longjmp inside the library. That is safe only if
 *   the cleanup frees the parser without re-entering it.
 * - zu_source_connection() validates the handle and Rf_error()s if it is
 *   unusable, so call it before any resource is held.
 * - The connection must be open, readable, binary and blocking. On a
 *   non-blocking connection a zero-byte read means "nothing yet", not end
 *   of input, and the two cannot be told apart; the R side is expected to
 *   open an unopened connection in "rb" first (see R/zu_source.R).
 * - Everything is static inline; no symbols leave the translation unit and
 *   nothing needs registering.
 * - Define ZU_SOURCE_PREFIX (e.g. "zuxml: ") before including this header
 *   and every error it raises carries the package's prefix; the file
 *   itself stays identical between packages.
 */
#ifndef ZU_SOURCE_H
#define ZU_SOURCE_H

#ifndef ZU_SOURCE_PREFIX
# define ZU_SOURCE_PREFIX ""
#endif

#include <stddef.h>
#include <Rinternals.h>
#include <R_ext/Connections.h>

/* R's connection API is declared unstable: the header itself says a caller
 * must check the version and stop if it is not the one it was written for.
 * This is the same guard iotools uses. */
#if R_CONNECTIONS_VERSION != 1
# error "zu_source.h: unsupported R connections API version"
#endif

typedef struct {
  /* Raw vector: borrowed bytes, handed out one chunk at a time. */
  const unsigned char *data;
  size_t n;
  size_t pos;
  /* Connection: read into buf, cap bytes at a time. NULL for a raw source. */
  Rconnection con;
  unsigned char *buf;
  size_t cap;
} zu_source;

/* A source over a raw vector, which must stay protected for the source's
 * lifetime. chunk is the most bytes one read hands out. */
static inline zu_source
zu_source_raw(SEXP x, size_t chunk) {
  zu_source s;
  if (TYPEOF(x) != RAWSXP)
    Rf_error(ZU_SOURCE_PREFIX "expected a raw vector");
  s.data = RAW(x);
  s.n = (size_t)Rf_xlength(x);
  s.pos = 0;
  s.con = NULL;
  s.buf = NULL;
  s.cap = chunk;
  return s;
}

/* A source over an R connection. The buffer comes from R_alloc, so it is
 * released when the enclosing .Call returns -- on error too -- and cannot
 * leak. The checks are on the connection as it is, not as R opened it: an
 * already-open connection arrives however the caller opened it. */
static inline zu_source
zu_source_connection(SEXP scon, size_t chunk) {
  zu_source s;
  Rconnection con;
  if (!Rf_inherits(scon, "connection"))
    Rf_error(ZU_SOURCE_PREFIX "expected a connection");
  con = R_GetConnection(scon); /* errors on a stale or invalid handle */
  if (!con->isopen)
    Rf_error(ZU_SOURCE_PREFIX "the connection is not open");
  if (!con->canread)
    Rf_error(ZU_SOURCE_PREFIX "the connection is not readable");
  if (con->text)
    Rf_error(ZU_SOURCE_PREFIX
             "the connection must be open in binary mode (\"rb\")");
  if (!con->blocking)
    Rf_error(ZU_SOURCE_PREFIX "the connection must be blocking");
  s.data = NULL;
  s.n = 0;
  s.pos = 0;
  s.con = con;
  s.buf = (unsigned char *)R_alloc(chunk, 1);
  s.cap = chunk;
  return s;
}

/* The next chunk, or 0 at end of input. The pointer is valid until the
 * next read. Checks for a user interrupt first, which is why this must be
 * called only where a longjmp is safe. */
static inline size_t
zu_source_read(zu_source *s, const void **chunk) {
  size_t got;
  R_CheckUserInterrupt();
  if (s->con != NULL) {
    got = R_ReadConnection(s->con, s->buf, s->cap);
    *chunk = s->buf;
    return got;
  }
  got = s->n - s->pos;
  if (got > s->cap)
    got = s->cap;
  *chunk = s->data + s->pos;
  s->pos += got;
  return got;
}

/* Push form: hands every chunk to sink until it returns non-zero or the
 * input ends. Returns the sink's last result, or 0 on a clean end. */
typedef int (*zu_sink)(void *ctx, const void *chunk, size_t n);

static inline int
zu_source_pump(zu_source *s, zu_sink sink, void *ctx) {
  const void *chunk;
  size_t n;
  int rc = 0;
  while (rc == 0 && (n = zu_source_read(s, &chunk)) > 0)
    rc = sink(ctx, chunk, n);
  return rc;
}

#endif /* ZU_SOURCE_H */
