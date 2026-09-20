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
    use revo::*;

    pub fn wow(_: VM, a: String, b: bool) -> String {
        format!("{} asd {}", a, b).to_string()
    }

    pub fn error(vm: crate::VM) -> Result<String, Error> {
        let _ = vm;
        Err(Error::Other(String::from("hi")))
    }

    #[name("cool.rename")]
    pub fn hi(_: VM, a: String, b: bool) -> String {
        format!("{} asd {}", a, b).to_string()
    }

    pub fn no_inputs() -> bool {
        true
    }
}
