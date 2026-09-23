/* Must crash: the fuzz gate's canary.
 *
 * tools/run-fuzz builds this first and requires it to fail through the same
 * function that runs the real targets. If it ever comes back clean, the gate
 * cannot see a crash either, and "fuzzing clean" means nothing -- which is
 * what happened while the fuzzer's status was read through a pipe into tail
 * (#35).
 *
 * It reads one byte past a heap buffer, so a pass proves that ASan is live
 * and that its report becomes a non-zero exit, not merely that abort() is
 * noticed. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  volatile uint8_t sink;
  uint8_t *copy;
  if (size == 0)
    return 0;
  copy = (uint8_t *)malloc(size);
  if (copy == NULL)
    return 0;
  memcpy(copy, data, size);
  sink = copy[size]; /* heap-buffer-overflow, on purpose */
  (void)sink;
  free(copy);
  return 0;
}
