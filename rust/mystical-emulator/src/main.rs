#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

pub mod state;
#[cfg(target_os = "windows")]
pub mod win32_ui;

const EMBEDDED_MANIFEST: &str = include_str!(concat!(env!("OUT_DIR"), "/embedded_manifest.json"));

fn main() {
    #[cfg(target_os = "windows")]
    {
        win32_ui::run_windows_emulator(EMBEDDED_MANIFEST);
    }

    #[cfg(not(target_os = "windows"))]
    {
        let m = state::parse_manifest(EMBEDDED_MANIFEST);
        println!(
            "MysticalOS Emulator ({} {} - {}), removed={} (-{} MiB). Build for x86_64-pc-windows-gnu to run GUI .exe on Windows.",
            m.os_name, m.os_version, m.market_name, m.removed_count, m.freed_mib
        );
    }
}
