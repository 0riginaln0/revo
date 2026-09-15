use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let status = Command::new("zig")
        .args(["build", "lib"])
        .status()
        .expect("Failed to run `zig build lib`");

    if !status.success() {
        panic!("`zig build lib` failed");
    }

    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header("../../zig-out/include/revo/revo.h")
        // Tell cargo to invalidate the built crate whenever any of the
        // included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .raw_line("unsafe impl Sync for RevoBinding {}")
        .allowlist_item(".?(?i-u:revo).*")
        .generate()
        .expect("Unable to generate bindings");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
