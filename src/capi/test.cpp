// compiled and run by `zig build test-c`
#include "revo.h"

int main() {
  ErevoVM *vm = erevo_vm_create();
  if (!vm)
    return 1;

  ErevoValue val = revo_nil();
  if (!erevo_eval(vm, "smoke", "1 + 2", &val)) {
    erevo_vm_destroy(vm);
    return 1;
  }
  if (!revo_is_number(val)) {
    erevo_vm_destroy(vm);
    return 1;
  }

  uint64_t sid = revo_intern(vm, "hi", 2);
  if (sid == 0) {
    erevo_vm_destroy(vm);
    return 1;
  }

  revo_setglobal_cstr(vm, "x", revo_num(1.0));
  (void)revo_getglobal_cstr(vm, "x");
  (void)revo_intern_cstr(vm, "y");

  erevo_vm_destroy(vm);
  return 0;
}
