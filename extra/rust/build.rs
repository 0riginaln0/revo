use std::env;
use std::path::PathBuf;
use std::process::Command;

fn check_zig_version() {
    let out = Command::new("zig")
        .arg("version")
        .output()
        .expect("`zig` not found in PATH (revo-sys needs zig 0.16 to build liberevo)");
    let version = String::from_utf8_lossy(&out.stdout);
    let mut nums = version
        .trim()
        .split(|c: char| !c.is_ascii_digit())
        .filter(|s| !s.is_empty())
        .filter_map(|s| s.parse::<u64>().ok());
    let (major, minor) = (nums.next().unwrap_or(0), nums.next().unwrap_or(0));
    if (major, minor) < (0, 16) {
        panic!("revo-sys needs zig >= 0.16, found `{}`", version.trim());
    }
}

fn main() {
    check_zig_version();

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());

    let repo_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("crate has to be <repo>/extra/rust");

    let lib_dir = repo_root.join("zig-out").join("lib");
    let header = repo_root.join("zig-out/include/revo/revo.h");

    let status = Command::new("zig")
        // cant use any external deps
        .args(["build", "lib", "-Dfeatures="])
        .current_dir(repo_root)
        .status()
        .expect("Failed to run `zig build lib`");

    if !status.success() {
        panic!("`zig build lib` failed");
    }

    let bindings = bindgen::Builder::default()
        // The input header we would like to generate
        // bindings for.
        .header(header.to_string_lossy())
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

    // Link the static library built by `zig build lib`.
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=erevo");
    // libm is linked separately by the Zig build for C consumers
    // (see `src/c/tests.c` link line); Rust doesn't link it automatically on Linux.
    if !cfg!(target_os = "macos") && !cfg!(target_env = "msvc") {
        println!("cargo:rustc-link-lib=m");
    }

    println!("cargo:rerun-if-changed=build.rs");
}
