---
title: two-way c interop
---

<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">

<div style="flex:1; min-width:250px;">

## two-way c<->revo interop

[docs](docs/basics) | [codeberg](https://codeberg.org/lung/revo) | [github (mirror)](https://github.com/if-not-nil/revo) | [license](#license)

> c is the only language that has everything a computer can do implemented in it
</div>

<pre class="ascii small">
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡰⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⢀⣠⢤⡤⡤⠤⣤⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⢾⣥⢻⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣶⣿⡱⣆⠤⡁⢎⡡⢵⠀⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⠆⣾⠸⣿⡎⢿⣿⣶⡀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⡿⢘⣠⠞⡧⣙⠤⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡼⢸⢿⡇⣿⣿⡘⣿⣿⣿⡀⠀⠀⠀⠀⢠⣼⣿⣿⣿⣿⡿⣃⣿⠣⢤⣤⢛⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡰⢥⣃⣏⣷⡜⣿⣧⠹⣿⣿⣿⡄⠀⠀⣴⣿⣿⣿⣿⣿⣯⢾⣿⣿⣾⡿⠶⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠵⣣⣟⣼⣷⣻⠸⣿⣦⠹⣿⣿⣿⡄⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠭⣘⠻⣿⣧⣿⣾⣧⠘⣿⡿⣹⣽⣿⡟⢿⣿⣿⣿⣿⣿⣿⣿⡧⣼⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠠⠤⡤⢤⠶⡤⣆⣤⡀⡄⠀⠀⠀⠈⠐⠃⢈⠻⢿⣿⣿⡇⠘⡍⡷⢘⣿⣌⡄⠀⣼⣿⣿⣿⣿⣿⡗⠺⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠰⠀⣀⠦⣑⢦⡙⡲⢍⡶⣋⠶⣡⠞⡝⢯⢷⣞⣶⢠⠀⠀⠀⠠⠀⠙⢿⡝⡄⡇⢱⢸⡏⢸⠆⢸⡟⣿⣿⣿⣿⣿⣟⠥⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠆⠀⠌⡄⡙⡘⠎⢷⡩⢏⠶⣩⠳⣡⠛⢬⢣⡍⠺⢞⢇⣾⠿⠆⠀⢎⡀⡄⠙⢡⣎⠞⡘⢿⡐⢀⡟⣲⢻⣿⣿⣿⣿⣏⡅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⠀⢂⠌⡑⢹⣛⢦⠹⢜⡲⡡⠜⡤⢃⠀⠁⠺⢑⢪⣌⢋⣄⠀⠡⠈⠳⣦⠅⠀⠻⡆⠇⣾⡄⢸⠘⢰⣼⣿⣿⣿⡟⠒⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠠⠂⠍⢢⠘⢎⠵⢢⠔⣉⡘⠔⠫⠜⢦⠠⡄⢌⠂⠳⣎⠷⣄⡀⠀⠀⠙⣆⠐⣿⡆⣿⠀⡧⠰⣟⣿⣻⣿⡟⠑⠀⢀⡀⣄⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠒⡄⠉⠎⡔⢃⠎⡱⠌⣙⠒⡆⣆⠀⠈⠃⠙⠀⠙⢼⣉⠷⢦⡐⠢⡘⢆⠙⢿⣿⠐⣱⠿⣀⣡⡶⠇⠀⢀⡐⣤⣻⣽⣯⣿⣶⣥⡄⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠃⡴⢠⢈⡐⠡⠒⠤⡈⢄⡘⢀⠀⠆⡡⠤⣀⣄⠰⠬⠡⢙⡳⢾⣮⣡⢌⠻⠀⡿⠙⡳⢃⠉⠀⠀⠈⣁⢋⠟⡻⠿⣿⣿⣿⣿⣷⣄⡀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠲⢤⠓⣌⠲⠤⣄⣈⢂⠒⡌⢰⡐⠤⡈⢍⡛⡫⢭⣍⣓⢾⣿⣝⢷⠤⠀⠀⠀⠤⢒⡈⣋⢛⡒⠾⠶⣴⣦⣀⡈⠍⠛⢿⣿⣽⢦⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠚⠥⡳⡄⣙⢪⣝⠺⣧⢟⣷⡾⣧⣱⣦⠚⢀⣉⣓⣊⡙⣻⣆⠒⠄⡀⠈⢆⢳⡸⢯⣿⣿⣷⣶⣬⣙⣛⠻⢦⣤⣌⠛⣯⠓⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⣀⠃⠮⢣⡹⢦⣛⠶⠛⠋⠀⢠⣳⡿⠟⠉⡼⢳⢌⡃⠌⠐⠀⠀⠎⠳⡛⠿⠛⡟⠿⠻⠿⢶⣻⠰⢦⡻⣝⢠⠏⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠄⢢⠐⠈⠄⠀⢄⠠⠀⢀⠀⡔⢁⠣⢃⠁⡐⢨⠑⡱⢊⠔⠈⠀⠀⢠⡈⡆⢁⣤⠡⠄⠄⠆⢁⡂⠰⠨⣥⢛⠬⡣⠍⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⢂⠔⠈⣠⢮⡑⠊⠁⠈⠀⡠⠂⣸⠁⠨⠑⡂⢌⠀⢄⢣⣿⢨⠀⠰⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠋⠺⠥⠃⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⢡⡞⣨⣾⣿⡗⠈⠁⠄⡡⢐⡁⢀⡏⣘⠀⢰⢁⡂⠀⣺⣼⣵⡎⠡⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡸⢡⡗⣰⣿⣿⣿⣼⣷⡏⣄⠣⢠⠂⢸⣷⣿⡀⣿⡘⢇⢲⣿⣿⣿⣏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡏⡟⣰⣿⣿⣿⣿⣿⡿⣟⡽⡂⠧⠀⣾⣿⣿⡟⣿⡇⣾⣿⣿⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡧⢁⣿⡟⣽⣿⣿⣿⡿⣉⡴⠳⠀⠀⣿⣿⣿⣧⢻⣇⢿⢾⣿⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⢻⡼⣽⣿⣿⣿⡿⠓⠈⠀⠀⠀⠀⢸⡟⢿⣿⣟⣿⣷⡌⢹⣿⣿⢿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠻⣜⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠘⣿⣼⣿⣿⡿⣽⣷⠀⡟⢿⣽⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠘⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⢣⡝⣿⣷⣿⣿⣧⠙⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠭⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⢾⣿⣿⣷⣿⣿⡄⣻⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠠⠌⠛⠿⡏⠙⠁⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
</pre>
</div>

despite being written in zig, revo gives you a real c api for embedding
and extensions. the header is auto-generated from zig `callconv(.c)`
functions, always in sync with what the library actually exports.
{{< ref "src/capi/exports.zig" >}}
{{< ref "src/capi/header_gen.zig" >}}

### build

```bash
zig build lib
```

you get a static library and an auto-generated header:

~ `zig-out/lib/liberevo.a`
~ `zig-out/include/revo/revo.h` (`#include "revo.h"` with `-Izig-out/include/revo`,
  or `#include <revo/revo.h>` with `-Izig-out/include`)

all generated decls are prefixed `REVO_API` (dllexport/dllimport on
windows, default visibility on gcc/clang, empty for `REVO_STATIC` builds)
and the header carries `#define REVO_VERSION "x.y.z"`. every `revo_*` /
`erevo_*` decl in it comes straight from an exported `callconv(.c)` zig fn,
so the header is always in sync with what the library actually exports.

{{< ref "src/capi/embed.zig" >}}

the opaque handles in `src/capi/embed.zig` are the ones you get in your C code

### vm lifecycle

```c
#include "revo.h"

ErevoVM *vm = erevo_vm_create();
if (!vm) return 1;

// ... use vm ...

erevo_vm_destroy(vm);
```

`ErevoVM` is an opaque handle

### compile and run

```c
ErevoProgram *prog = erevo_compile(vm, "main.rv", "1 + 2");
if (!prog) {
    puts(erevo_vm_last_error(vm));
    return 1;
}

RevoValue result;
if (!erevo_run(vm, prog, &result)) {
    puts(erevo_vm_last_error(vm));
}

// eval does compile + run + free in one step
if (!erevo_eval(vm, "main.rv", "1 + 2", &result)) {
    puts(erevo_vm_last_error(vm));
}

erevo_program_destroy(prog);
```

{{< ref "pub fn erevo_compile(" >}}
{{< ref "pub fn erevo_run(" >}}
{{< ref "pub fn erevo_eval(" >}}

`erevo_run` writes the result value through the optional `result` pointer

### errors

```c
const char *msg = erevo_vm_last_error(vm);
```

returns a null-terminated string, valid until the next api call on the
same vm

### value type

all values are a single nanboxed `uint64_t`:

```c
typedef uint64_t RevoValue;
```

numbers are the raw f64 bits; boxed values pack the type nibble (bits
51-48) and a payload (low 48 bits) behind a box tag. the payload is an
intern id,, except `opaque`, whose payload is the low 48 bits of the
wrapped pointer:

```c
typedef enum {
    revo_number = 0,
    revo_string = 8,
    revo_atom = 9,
    revo_function = 10,
    revo_table = 11,
    revo_opaque = 13,
} RevoType;
```

**constructors**

```c
RevoValue v = revo_nil();                  // :nil
RevoValue v = revo_bool(1);                // :true / :false
RevoValue v = revo_string_val(string_id);  // from interned id
RevoValue v = revo_num(3.14);              // number
RevoValue v = revo_atom_val(atom_id);      // atom by raw id
RevoValue v = revo_table_val(table_id);    // from table id
RevoValue v = revo_function_val(func_id);  // from function id
```

(`revo_string(id)` / `revo_table(id)` / `revo_function(id)` still work as
compat aliases for the `_val` forms.)

**extractors**

```c
double   revo_num_value(RevoValue);
uint64_t revo_string_id(RevoValue);
uint64_t revo_atom_id(RevoValue);
uint64_t revo_table_id(RevoValue);
void    *revo_opaque_ptr(RevoValue);  // null if not opaque (see below)
int      revo_bool_val(RevoValue);   // 0 or 1, 0 if not bool
int      revo_type(RevoValue);       // the RevoType of the value
```

**type checks**

```c
int revo_is_nil(RevoValue);
int revo_is_number(RevoValue);
int revo_is_string(RevoValue);
int revo_is_atom(RevoValue);
int revo_is_function(RevoValue);
int revo_is_table(RevoValue);
int revo_is_opaque(RevoValue);
int revo_is_bool(RevoValue);
```

built-in atoms have guaranteed and consistent values in the `RevoAtom` enum, such as

`ra_nil`, `ra_true`, `ra_false`, `ra_ok`, `ra_err`, `ra_some`,
`ra_none`, `ra_undef`, `ra_missing`, `ra_no_result`, `ra_range`

this means you don't have to intern them manually

{{< ref "pub const RevoAtom" >}}

### opaque

opaque handles. an opaque wraps a raw `void*` revo never touches.
caller owns the memory

```c
RevoValue v = revo_opaque_new(ptr);    // wrap
void *p = revo_opaque_ptr(v);         // unwrap
int is_f = revo_is_opaque(v);         // check
```

{{< ref "pub fn revo_opaque_new(" >}}
{{< ref "pub fn revo_opaque_ptr(" >}}

**null is ambiguous.** `revo_opaque_ptr` is null for non-opaque
values and null ptrs:

```c
if (!revo_is_opaque(v)) {
    // not opaque at all
} else {
    void *p = revo_opaque_ptr(v);  // null here means a genuine null ptr
}
```

**low 48 bits only** (`REVO_PAYLOAD_MASK`). fits canonical user ptrs on
x86_64/arm64; no tagged ptrs or high-bit integers

**lifetime.** the box holds the address, not the pointee. `malloc` +
explicit `free`; revo is never the owner:

```c
typedef struct { double total; } Total;

void total_new(void *vm, size_t argc, RevoValue *argv, RevoValue *out) {
    (void)argc; (void)argv;
    Total *t = malloc(sizeof(Total));
    if (!t) { *out = revo_nil(); return; }
    t->total = 0;
    *out = revo_opaque_new(t);
}

void total_add(void *vm, size_t argc, RevoValue *argv, RevoValue *out) {
    (void)vm;
    if (argc < 2 || !revo_is_opaque(argv[0]) || !revo_is_number(argv[1])) {
        *out = revo_nil();
        return;
    }
    Total *t = revo_opaque_ptr(argv[0]);
    if (!t) { *out = revo_nil(); return; }
    t->total += revo_num_value(argv[1]);
    *out = revo_num(t->total);
}

void total_free(void *vm, size_t argc, RevoValue *argv, RevoValue *out) {
    (void)vm; (void)argc;
    if (argc >= 1 && revo_is_opaque(argv[0])) free(revo_opaque_ptr(argv[0]));
    *out = revo_nil();
}
```

**transport.** ordinary values: globals, table fields, call args, `*out`

```revo
typeof(ptr)    # :opaque
opaque?(ptr) # :true
```

ptr identity, opaque render (`<opaque *>`)

### rooting

a `RevoValue` in a c local roots nothing. values reachable only from c
can be swept (ids reused) by the next collection. pin what you hold
across calls:

```c
uint64_t r = revo_ref(vm, val);  // 0 on failure
// eval / call freely; revo_getref(vm, r) stays valid
RevoValue same = revo_getref(vm, r);
revo_unref(vm, r);               // release exactly once
```

ids monotonic, never reused: stale reads `:nil`. `revo_ref` on `:nil`
is 0; `revo_getref` on 0/unknown/released is `:nil`; `revo_unref`
there is a noop. globals root too

{{< ref "pub fn revo_ref(" >}}
{{< ref "pub fn revo_getref(" >}}
{{< ref "pub fn revo_unref(" >}}

### finalizers

explicit `free` stays primary: gc promises no timing. a table can
carry a finalizer running once with the table as sole arg when swept
(leftovers run at destroy):

```c
bool ok = revo_table_set_finalizer(vm, handle_table, fin_fn);
bool dropped = revo_table_remove_finalizer(vm, handle_table);
```

same mechanism as `regex`/sockets: `_ptr` field, freed in finalizer
*and* explicit `free`, both tolerating a missing `_ptr`. keep `fin_fn`
reachable til it fires

{{< ref "pub fn revo_table_set_finalizer(" >}}
{{< ref "pub fn revo_table_remove_finalizer(" >}}

### strings

strings are interned! every unique string has a stable `uint64_t` id

```c
uint64_t sid = revo_intern(vm, "hello", 5);
RevoValue val = revo_string_val(sid);
```

the pointer must stay valid for the duration of the call

to read string data back:

```c
const unsigned char *data = revo_string_data(vm, sid);
uint64_t len = revo_string_length(vm, sid);
```

`revo_string_data` returns a pointer to the internal string buffer
(valid until the string is gc'd) and is **not** nul-terminated!!! use
`revo_string_length` for the byte count, copy when you need a c string
{{< ref "pub fn revo_intern(" >}}
{{< ref "pub fn revo_string_data(" >}}

### calling revo functions from c

```c
RevoValue fn_val;             // get from eval, global, etc.
RevoValue args[2] = { revo_num(10.0), revo_num(20.0) };
RevoValue result;

int ok = revo_call(vm, fn_val, 2, args, &result);
```

returns 0 if the value wasn't callable or the call threw. max 16 args.
{{< ref "pub fn revo_call(" >}}

### globals

```c
revo_setglobal(vm, "name", 4, revo_num(42.0));
RevoValue v = revo_getglobal(vm, "name", 4);

// or via c-string wrappers (call strlen internally)
revo_setglobal_cstr(vm, "name", revo_num(42.0));
RevoValue v = revo_getglobal_cstr(vm, "name");
```

missing keys return `:nil`
{{< ref "pub fn revo_getglobal(" >}}
{{< ref "pub fn revo_setglobal(" >}}

### tables

functions take the table value itself, lookups report presence
through the return value so missing keys are distinct from nil values:

```c
RevoValue t = revo_table_create(vm);

// named fields
revo_table_set_name(vm, t, "x", 1, revo_num(42.0));
RevoValue v;
bool found = revo_table_get_name(vm, t, "x", 1, &v);  // true

// generic keys (metatable-aware, like t[k])
RevoValue key = revo_atom_val(revo_intern_atom(vm, ...));
revo_table_set(vm, t, key, revo_num(42.0));

// array part
RevoValue arr = revo_table_from_items(vm, 2, (RevoValue[]){ revo_num(1.0), revo_num(2.0) });
revo_table_push(vm, arr, revo_num(3.0));
revo_table_get_idx(vm, arr, 1, &v);   // 2.0, false when out of range

uint64_t n = revo_table_len(vm, t);    // total entries
uint64_t a = revo_table_alen(vm, arr); // array part only
```

{{< ref "pub fn revo_table_create(" >}}
{{< ref "pub fn revo_table_set(" >}}
{{< ref "pub fn revo_table_get(" >}}

### results

host functions answer with `{:ok, v}` / `{:err, e}` tables:

```c
if (bad) {
    *out_result = revo_err(vm, revo_atom_val(
        revo_intern_atom(vm, "BadInput", 8)));
    return;
}
// ... later, on the receiving side:
if (revo_is_ok(vm, val)) {
    RevoValue payload;
    revo_ok_value(vm, val, &payload);
}
```

{{< ref "pub fn revo_ok(" >}}
{{< ref "pub fn revo_is_ok(" >}}

### writing c extensions

extensions are shared libraries that export a `revo_bindings` array.
every c function follows this signature:

```c
typedef int (*RevoFn)(void *vm, size_t argc, RevoValue *argv, RevoValue *out);
```

return `REVO_OK` (0), anything else raises (`*out` ignored on err):

```c
#define REVO_OK 0
#define REVO_ERR_ARITY 1
#define REVO_ERR_TYPE 2
#define REVO_ERR_OTHER 3
```

a minimal extension:

```c
#include "revo.h"

int greet(void *vm, size_t argc, RevoValue *argv, RevoValue *out) {
    (void)vm; (void)argc; (void)argv;
    *out = revo_num(42.0);
    return REVO_OK;
}

__attribute__((visibility("default")))
const RevoBinding revo_bindings[] = {
    {"greet", greet},
    {NULL, NULL},
};
```

**errors.** the big `HostResult` three: arity, type, other
return the helper's result directly:

```c
if (argc < 2) return revo_c_err_arity(vm, argc, 2);
if (!revo_is_number(argv[0])) return revo_c_err_type(vm, 0, "number", argv[0]);
if (!ok) return revo_c_err_other(vm, "boom");
```

```c
int revo_c_err_arity(void *vm, uint64_t got, uint64_t expected);
int revo_c_err_type(void *vm, uint64_t arg, const char *expected, RevoValue got);
int revo_c_err_other(void *vm, const char *msg);
```

`got` renders through `typeof`; messages copy before return, literals fine
bare `REVO_ERR_*` without a helper raises with a generic message

{{< ref "pub fn revo_c_err_arity(" >}}
{{< ref "pub fn revo_c_err_type(" >}}
{{< ref "pub fn revo_c_err_other(" >}}

each binding is just `name` and `fn_ptr`. the typed interface lives in a
sibling `.d.rv` manifest, and every binding lands in the module table under
the import's name

the last row is an all-null terminator

a worked-through example is at {{< ref "examples/c/extension.c" >}}, rebuild the `.so` after editing

**data conversion**

`RevoValue` is nanboxed: numbers are the raw f64 bits, everything else
is the type nibble plus a payload packed into the low 48 bits (an intern
id, except opaque, which stores the low 48 bits of the pointer).
the type helpers read a c value out of the same word:

```ruby
`revo type`    - `c check`          - `c extractor`

42 (number)    - revo_is_number   - revo_num_value
"hi" (string)  - revo_is_string   - revo_string_id
:atom          - revo_is_atom     - revo_atom_id
fn()           - revo_is_function - revo_function_id
{} (table)     - revo_is_table    - revo_table_id
{1, 2} (table) - revo_is_table    - revo_table_id
opaque ptr    - revo_is_opaque      - revo_opaque_ptr
```

a value can be moved through any of the constructors in its row
(the word is self-describing, no separate tag field)

strings must be interned before returning:

```c
const char *msg = "hello";
uint64_t id = revo_intern(vm, msg, 5);
*out = revo_string_val(id);
```

**loading from revo**

module members come from the sibling manifest, so call the import directly
and the calls are checked:

```revo
# extension.d.rv: the interface, plain revo
pub declare add = fn(a: number, b: number) -> number
pub declare concat = fn(parts: table, sep: string) -> string
```

```revo
import "extension.so"
extension.add 3, 4
extension.concat ({"a", "b", "c"}, "-")   # typed from the manifest
```

`import "extension.so"` finds `extension.d.rv` next to it by stem, types every
call against the `pub declare`s, and loads every binding into the module table.
the manifest is the whole description:

manifests are real revo source, so there's no grammar ceiling: unions,
nullables, error unions, varargs, and keyword names all work.

without a manifest the bindings still load into the module table, just untyped:
the `.so` is opaque to the compiler, so nothing checks those calls

for scripts where a `.d.rv` shows up without a library, the import still
typechecks but resolves to an empty table at runtime (edit-time only)

{{< ref "fn cload(" >}}

**building**

```bash
# linux
cc -shared -fPIC -o extension.so extension.c -I/path/to/zig-out/include

# macos
cc -shared -fPIC -o extension.dylib extension.c -I/path/to/zig-out/include
```

#### best practices

- validate arguments manually (functions are variadic for now);
  arity/type/other failures `return revo_c_err_*`, see above
- on success set `*out` (even nil) + `return REVO_OK`; `*out`
  ignored on err paths
- `-fPIC` for shared libraries
- don't store `RevoValue` values past the call; intern or copy what
  you need
- persistent native state is a `revo_opaque_new` ptr passed as context;
  otherwise a revo table
