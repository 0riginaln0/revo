//! # Use this example
//!
//! make sure headers are built into zig-out/include/
//! ```
//! zig build lib
//! ```
//! build bindgen with
//! ```
//! cargo build -p revo-sys --example basic
//! ```
//! then, open `revo` and use the extension's function to return 0
//! ```rb
//! import "./target/debug/examples/libbasic.dylib".hi()
//! > 0
//! ```

use std::ffi::*;

use revo_sys::ffi::*;

extern "C" fn hi(_vm: *mut c_void, _argc: usize, _argv: *mut RevoData, out: *mut RevoData) {
    unsafe {
        *out = 0;
    }
}

#[unsafe(no_mangle)]
pub static revo_bindings: [RevoBinding; 2] = [
    RevoBinding {
        name: c"hi".as_ptr(),
        fn_: Some(hi),
    },
    // null termination defines the end of a list of bindings
    RevoBinding {
        name: std::ptr::null(),
        fn_: None,
    },
];
