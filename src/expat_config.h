/* zuxml: project-owned build configuration for the vendored Expat.
 *
 * This file is NOT from upstream. Everything under src/vendor/expat/ is a
 * byte-identical copy of the pinned release (see src/vendor/PROVENANCE and
 * tools/verify-vendor); all local configuration lives here instead. Expat's
 * sources include "expat_config.h" unconditionally, and because there is no
 * such file inside the vendor directory the quoted include falls through to
 * this one via -I in src/Makevars.
 *
 * Upstream generates this header with autotools or CMake. R packages cannot
 * run either at install time, so the values are derived from the compiler's
 * own predefined macros below.
 */

#ifndef ZUXML_EXPAT_CONFIG_H
#define ZUXML_EXPAT_CONFIG_H

/* ------------------------------------------------------------------ *
 * Parser feature policy.  See .agents/zuxml-design.md section 11.
 *
 * XML_GE 0 removes general-entity support outright, and Expat enforces
 * (xmlparse.c) that XML_DTD must then stay undefined. Together these
 * delete parameter entities, external subsets and the external-entity
 * machinery from the binary, so XXE and entity-amplification attacks are
 * impossible rather than merely switched off. The accepted cost is that
 * any entity reference beyond the five built-ins and numeric character
 * references is a hard parse error.
 * ------------------------------------------------------------------ */
#define XML_NS 1
#define XML_GE 0
/* #undef XML_DTD  -- deliberately never defined */
#define XML_CONTEXT_BYTES 1024

/* ------------------------------------------------------------------ *
 * Trap 1: BYTEORDER.
 *
 * Expat requires this and it must never be copied from a header that was
 * generated on some other machine. Derive it, and fail loudly rather than
 * guessing, because a wrong value miscompiles the tokenizer silently.
 * ------------------------------------------------------------------ */
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__)                \
    && defined(__ORDER_BIG_ENDIAN__)
#  if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#    define BYTEORDER 1234
#  elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#    define BYTEORDER 4321
#  else
#    error "zuxml: __BYTE_ORDER__ is neither little- nor big-endian."
#  endif
#elif defined(_WIN32) || defined(_M_IX86) || defined(_M_X64) || defined(_M_ARM)\
    || defined(_M_ARM64) || defined(__i386__) || defined(__x86_64__)           \
    || defined(__LITTLE_ENDIAN__) || defined(__ARMEL__)                        \
    || defined(__AARCH64EL__) || defined(__MIPSEL__)
#  define BYTEORDER 1234
#elif defined(__BIG_ENDIAN__) || defined(__ARMEB__) || defined(__AARCH64EB__)  \
    || defined(__MIPSEB__) || defined(__sparc__) || defined(__s390x__)         \
    || defined(__hppa__) || (defined(__PPC__) && ! defined(__LITTLE_ENDIAN__))
#  define BYTEORDER 4321
#else
#  error "zuxml: cannot determine byte order. Please report this platform at https://github.com/pedrobtz/zuxml/issues"
#endif

/* ------------------------------------------------------------------ *
 * Trap 2: entropy source for Expat's hash salt.
 *
 * Getting this wrong is the most common Expat vendoring failure, and
 * picking a weak source is a real hazard: Expat 2.8.4 fixed
 * CVE-2026-76956, hash-flooding via inverted getentropy() return
 * handling. Exactly one backend is selected here and compiled by
 * src/zux_expat_random.c.
 *
 * Deliberately NOT probing __GLIBC__ to choose getrandom() over the raw
 * syscall: that needs <features.h> included from this header, which runs
 * before the random_*.c files set _DEFAULT_SOURCE / _POSIX_C_SOURCE and
 * would freeze glibc's feature exposure at the wrong level. The syscall
 * path works on every Linux libc, so the ordering hazard is simply
 * avoided. Expat degrades to its own fallback if the syscall is absent.
 *
 * _WIN32 needs no macro: xmlparse.c selects rand_s automatically.
 * ------------------------------------------------------------------ */
#if defined(_WIN32)
   /* rand_s, chosen by xmlparse.c under #if defined(_WIN32) */
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__)       \
    || defined(__NetBSD__) || defined(__DragonFly__)
#  define HAVE_ARC4RANDOM_BUF 1
#elif defined(__linux__)
#  define HAVE_SYSCALL_GETRANDOM 1
#elif defined(__sun) || defined(_AIX) || defined(__hpux) || defined(__unix__)  \
    || defined(__unix)
#  define XML_DEV_URANDOM 1
#else
#  error "zuxml: no entropy source known for this platform. Please report it at https://github.com/pedrobtz/zuxml/issues rather than defining XML_POOR_ENTROPY, which would leave the parser open to hash flooding."
#endif

#endif /* ZUXML_EXPAT_CONFIG_H */
