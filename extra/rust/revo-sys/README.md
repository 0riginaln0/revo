# rust<->revo bindings

embed revo in rust, or expose rust to revo

## requirements

- zig >= 0.16 (`build.rs` checks; it builds `liberevo` out of the repo root)
- libclang (bindgen needs it)
- a one thread

## use as a dependency

when you have revo cloned locally into `./revo`:

```toml
[dependencies]
revo-sys = { path = "../revo/extra/rust" }
```

`cargo build` runs `zig build lib` for you, then links the static lib

## embedding

run revo code from rust

full runnable version in `examples/high-level.rs`
(`cargo run --example high-level`), edge cases in `tests/api.rs`.

```rust
use revo_sys::{Data, Program, Table, VM};

let mut vm = VM::new();

// oneshot
let v = vm.eval("40 + 2", None)?;
assert_eq!(v, Data::Num(42.0));

// compile once, run as often as you like
// > `Program` borrows the vm, so it can't outlive it
let mut prog = Program::compile(&vm, "41 + 1", None)?;
let v = prog.run()?;
drop(prog);

// share state across evals through globals
//   missing names read back as `:nil`
vm.set_global("x", &Data::Num(21.0))?;
let v = vm.eval("x * 2", None)?;

// call a revo function value from rust
let f = vm.eval("fn(a, b) a + b", None)?;
let v = vm.call(&f, &[Data::Num(20.0), Data::Num(22.0)])?;

// tables both ways
// : build one here, hand it over, read it back
let mut t = Table::new(&vm);
t.set_name("answer", &Data::Num(42.0))?;

let data = t.to_data(); // `t`'s borrow ends here, so `vm` is usable again
vm.set_global("t", &data)?;

let back = Table::from_data(&vm, &vm.get_global("t")?)?;
let answer = back.get_name("answer")?;
```

any datum is managed by gc, this is why all the clones happen automagically. it's not realistic to try and cooperate with it over the c abi

## extending

expose rust fns to revo as a shared library (`.dylib`/`.so`), the exact same way you would in C

this still needs much more work, especially by someone who can work proc macros

`examples/basic.rs`:

```rust
use std::ffi::*;
use revo_sys::ffi::*;

extern "C" fn hi(_vm: *mut c_void, _argc: usize, _argv: *mut RevoData, out: *mut RevoData) {
    unsafe {
        *out = 0; // `0u64` is `0.0`; numbers are raw f64 bits
    }
}

#[unsafe(no_mangle)]
pub static revo_bindings: [RevoBinding; 2] = [
    RevoBinding {
        name: c"hi".as_ptr(),
        fn_: Some(hi),
    },
    // null entry terminates the list
    RevoBinding {
        name: std::ptr::null(),
        fn_: None,
    },
];
```

```sh
cargo build --example basic
```

then from revo:

```rb
import "./target/debug/examples/libbasic.dylib".hi()
> 0
```

## threading

don't

## contributing

if you use this library and feel like something is missing, chances are- the omission is not intentional

try not to introduce dependencies

## TODO

- [ ] proper error types
- [ ] embedding proc macro
- [ ] cover 100% of the distinct `revo.h` functionality
