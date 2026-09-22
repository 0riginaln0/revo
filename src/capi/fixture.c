#include <errno.h>

int ffi_test_add(int a, int b) { return a + b; }
double ffi_test_mul(double a, double b) { return a * b; }
int ffi_test_fail(void) {
  errno = 22;
  return -1;
}
