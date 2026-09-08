/* zuxml: selects exactly one of Expat's entropy backends.
 *
 * Upstream picks the backend with autotools/CMake conditionals and adds the
 * matching random_*.c to the source list. The files are NOT self-guarded --
 * random_arc4random_buf.c calls arc4random_buf() unconditionally, so
 * compiling them all would fail wherever a backend is unavailable.
 *
 * R packages need a fixed OBJECTS list in a portable Makevars (no GNU-make
 * conditionals), so the selection happens in the preprocessor here instead:
 * one translation unit, one backend, chosen by the same macros that
 * src/expat_config.h sets and that xmlparse.c reads.
 */

#include "expat_config.h"

#if defined(_WIN32)
#  include "vendor/expat/random_rand_s.c"
#elif defined(HAVE_ARC4RANDOM_BUF)
#  include "vendor/expat/random_arc4random_buf.c"
#elif defined(HAVE_ARC4RANDOM)
#  include "vendor/expat/random_arc4random.c"
#elif defined(HAVE_SYSCALL_GETRANDOM) || defined(HAVE_GETRANDOM)
#  include "vendor/expat/random_getrandom.c"
#elif defined(HAVE_GETENTROPY)
#  include "vendor/expat/random_getentropy.c"
#elif defined(XML_DEV_URANDOM)
#  include "vendor/expat/random_dev_urandom.c"
#else
#  error "zuxml: src/expat_config.h selected no entropy backend."
#endif
