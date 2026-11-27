use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=MYSTICALOS_MANIFEST");
    println!("cargo:rerun-if-changed=default_manifest.json");

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let dst = out_dir.join("embedded_manifest.json");

    let src = match env::var("MYSTICALOS_MANIFEST") {
        Ok(p) if !p.is_empty() && PathBuf::from(&p).is_file() => PathBuf::from(p),
        _ => PathBuf::from("default_manifest.json"),
    };

    fs::copy(&src, &dst).expect("copy embedded_manifest.json");
}
