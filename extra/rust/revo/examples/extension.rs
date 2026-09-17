//! # Use this example
//!
//! make sure headers are built into zig-out/include/
//! ```
//! zig build lib
//! ```
//! build bindgen with
//! ```
//! cargo build -p revo --example extension
//! ```
//! then, open `revo` and use the extension's function to return 0
//! ```rb
//! import "./target/debug/examples/libextension.dylib".wow("hi", :true)
//! > 0
//! ```

use revo::*;

#[revo_bindings]
mod bindings {

    pub fn wow(vm: VM, a: String, b: bool) -> String {
        format!("{} asd {}", a, b).to_string()
    }

    #[name("cool.rename")]
    pub fn hi(vm: VM, a: String, b: bool) -> String {
        format!("{} asd {}", a, b).to_string()
    }
}
