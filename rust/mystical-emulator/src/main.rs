#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

pub mod image_reader;
pub mod state;
#[cfg(target_os = "windows")]
pub mod win32_ui;

const EMBEDDED_MANIFEST: &str = include_str!(concat!(env!("OUT_DIR"), "/embedded_manifest.json"));

fn run_cli_verify(img_path: &str, extract_out: Option<&str>) -> Result<(), String> {
    let p = std::path::Path::new(img_path);
    let mut st = state::EmulatorState::new(EMBEDDED_MANIFEST);
    st.load_image_from_path(p)?;
    let img = st.loaded_image.as_ref().ok_or("Brak loaded_image")?;
    println!("=== MysticalOS Emulator Image Verification ===");
    println!("Container: {}", img.container_kind);
    for part in &img.partitions {
        println!("  partition: {:12} size={} MiB  fs={}", part.name, part.size_mib, part.fs_kind);
    }
    println!("  build.prop entries: {}", img.props.len());
    for key in [
        "ro.mysticalos.version",
        "ro.mysticalos.launcher",
        "ro.mysticalos.dynamic_island",
        "ro.mysticalos.icon_engine",
        "ro.build.display.id",
        "ro.build.version.release",
        "ro.product.system.model",
    ] {
        if let Some(v) = img.props.get(key) {
            println!("    {} = {}", key, v);
        }
    }
    println!("  HyperOS 4 launcher: {}", img.has_hyperos4_launcher);
    println!("  Dynamic Island ON : {}", img.has_dynamic_island_config);
    println!("  services.jar spoof: {}", img.services_spoof_verified);
    println!("  r9c-memd present  : {}", img.has_r9c_memd);
    println!("  bootanimation PNGs: {}", img.boot_frames.len());
    println!("  scanned APKs      : {}", img.apks.len());
    for apk in img.apks.iter().take(15) {
        println!("    apk: {} -> {} ({} KiB, launcher={})", apk.path, apk.package, apk.size_kib, apk.is_launcher);
    }
    println!("  xiaomi bloat left : {}", img.xiaomi_bloat_left.len());
    if let Some(out_sys) = extract_out {
        let out_p = std::path::Path::new(out_sys);
        let bytes = st.extract_system_img_to(out_p)?;
        println!("  extracted system.img: {} bytes -> {}", bytes, out_p.display());
        let mut st2 = state::EmulatorState::new(EMBEDDED_MANIFEST);
        st2.load_image_from_path(out_p)?;
        let img2 = st2.loaded_image.as_ref().ok_or("Brak img2")?;
        println!(
            "  verified extracted system.img: {} props={}, apks={}, spoof={}",
            img2.container_kind, img2.props.len(), img2.apks.len(), img2.services_spoof_verified
        );
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(pos) = args.iter().position(|a| a == "--verify-image") {
        let img = args.get(pos + 1).map(|s| s.as_str()).unwrap_or("super.img");
        let ext = args
            .iter()
            .position(|a| a == "--extract-system")
            .and_then(|ep| args.get(ep + 1))
            .map(|s| s.as_str());
        if let Err(e) = run_cli_verify(img, ext) {
            eprintln!("VERIFY FAILED: {}", e);
            std::process::exit(1);
        }
        return;
    }

    #[cfg(target_os = "windows")]
    {
        win32_ui::run_windows_emulator(EMBEDDED_MANIFEST);
    }

    #[cfg(not(target_os = "windows"))]
    {
        let m = state::parse_manifest(EMBEDDED_MANIFEST);
        println!(
            "MysticalOS Emulator ({} {} - {}), removed={} (-{} MiB). Build for x86_64-pc-windows-gnu to run GUI .exe on Windows, or pass --verify-image <super.img|system.img>.",
            m.os_name, m.os_version, m.market_name, m.removed_count, m.freed_mib
        );
    }
}
