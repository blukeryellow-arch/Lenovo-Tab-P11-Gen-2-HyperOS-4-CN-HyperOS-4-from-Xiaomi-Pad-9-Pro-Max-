use std::fs::{self, OpenOptions};
use std::io::Write;
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug, Default, PartialEq, Eq)]
pub struct MemSnapshot {
    pub mem_total_kib: u64,
    pub mem_available_kib: u64,
    pub swap_total_kib: u64,
    pub swap_free_kib: u64,
}

#[derive(Debug, Default, PartialEq)]
pub struct PsiMemory {
    pub some_avg10: f32,
    pub some_avg60: f32,
    pub full_avg10: f32,
}

pub fn parse_meminfo(raw: &str) -> MemSnapshot {
    let mut snap = MemSnapshot::default();
    for line in raw.lines() {
        let mut parts = line.split_whitespace();
        let key = match parts.next() {
            Some(k) => k,
            None => continue,
        };
        let val: u64 = parts
            .next()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        match key {
            "MemTotal:" => snap.mem_total_kib = val,
            "MemAvailable:" => snap.mem_available_kib = val,
            "SwapTotal:" => snap.swap_total_kib = val,
            "SwapFree:" => snap.swap_free_kib = val,
            _ => {}
        }
    }
    snap
}

pub fn parse_psi_memory(raw: &str) -> PsiMemory {
    let mut psi = PsiMemory::default();
    for line in raw.lines() {
        let is_some = line.starts_with("some ");
        let is_full = line.starts_with("full ");
        if !is_some && !is_full {
            continue;
        }
        for tok in line.split_whitespace().skip(1) {
            if let Some((k, v)) = tok.split_once('=') {
                if let Ok(num) = v.parse::<f32>() {
                    match (is_some, k) {
                        (true, "avg10") => psi.some_avg10 = num,
                        (true, "avg60") => psi.some_avg60 = num,
                        (false, "avg10") => psi.full_avg10 = num,
                        _ => {}
                    }
                }
            }
        }
    }
    psi
}

pub fn should_reclaim(snap: &MemSnapshot, psi: &PsiMemory) -> bool {
    if snap.mem_total_kib == 0 {
        return false;
    }
    let avail_mib = snap.mem_available_kib / 1024;
    let total_mib = snap.mem_total_kib / 1024;
    // Dynamic threshold for 2 GiB / 3 GiB / 4 GiB variants of Redmi 9C
    let low_mib = if total_mib <= 2200 { 260 } else { 360 };
    avail_mib < low_mib || psi.some_avg10 >= 18.0 || psi.full_avg10 >= 4.0
}

fn write_sysfs(path: &str, value: &str) -> bool {
    match OpenOptions::new().write(true).open(path) {
        Ok(mut f) => f.write_all(value.as_bytes()).is_ok(),
        Err(_) => false,
    }
}

fn kmsg(msg: &str) {
    let line = format!("<6>r9c-memd: {}\n", msg);
    if !write_sysfs("/dev/kmsg", &line) {
        eprintln!("r9c-memd: {}", msg);
    }
}

fn apply_initial_tuning() {
    let params = [
        ("/proc/sys/vm/swappiness", "130"),
        ("/proc/sys/vm/page-cluster", "0"),
        ("/proc/sys/vm/vfs_cache_pressure", "120"),
        ("/proc/sys/vm/watermark_scale_factor", "60"),
        ("/proc/sys/vm/dirty_background_ratio", "5"),
        ("/proc/sys/vm/dirty_ratio", "15"),
    ];
    let mut applied = 0usize;
    for (p, v) in params {
        if write_sysfs(p, v) {
            applied += 1;
        }
    }
    kmsg(&format!("initial VM/zRAM tuning applied ({}/{} params)", applied, params.len()));
}

fn read_snapshot() -> (MemSnapshot, PsiMemory) {
    let mem_raw = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let psi_raw = fs::read_to_string("/proc/pressure/memory").unwrap_or_default();
    (parse_meminfo(&mem_raw), parse_psi_memory(&psi_raw))
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--once") {
        let (snap, psi) = read_snapshot();
        println!(
            "total={}MiB avail={}MiB swap_free={}MiB psi_some10={:.2} psi_full10={:.2} reclaim={}",
            snap.mem_total_kib / 1024,
            snap.mem_available_kib / 1024,
            snap.swap_free_kib / 1024,
            psi.some_avg10,
            psi.full_avg10,
            should_reclaim(&snap, &psi)
        );
        return;
    }

    apply_initial_tuning();
    let mut last_reclaim = Instant::now() - Duration::from_secs(60);

    loop {
        let (snap, psi) = read_snapshot();
        if should_reclaim(&snap, &psi) && last_reclaim.elapsed() >= Duration::from_secs(45) {
            let ok = write_sysfs("/proc/sys/vm/drop_caches", "1");
            last_reclaim = Instant::now();
            kmsg(&format!(
                "pressure reclaim (avail={}MiB, psi_some10={:.1}, psi_full10={:.1}, drop_caches={})",
                snap.mem_available_kib / 1024,
                psi.some_avg10,
                psi.full_avg10,
                ok
            ));
            thread::sleep(Duration::from_secs(3));
        } else {
            thread::sleep(Duration::from_millis(2500));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_and_reclaim() {
        let mem = "MemTotal:        1920000 kB\nMemAvailable:     220000 kB\nSwapTotal:       1048576 kB\nSwapFree:         512000 kB\n";
        let psi = "some avg10=21.50 avg60=10.10 avg300=2.00 total=12345\nfull avg10=1.20 avg60=0.40 avg300=0.10 total=999\n";
        let snap = parse_meminfo(mem);
        let p = parse_psi_memory(psi);
        assert_eq!(snap.mem_total_kib, 1920000);
        assert_eq!(snap.mem_available_kib, 220000);
        assert!((p.some_avg10 - 21.5).abs() < 0.01);
        assert!(should_reclaim(&snap, &p));

        let ok_mem = "MemTotal:        1920000 kB\nMemAvailable:     750000 kB\n";
        let ok_psi = "some avg10=1.00 avg60=0.50 avg300=0.10 total=100\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n";
        assert!(!should_reclaim(&parse_meminfo(ok_mem), &parse_psi_memory(ok_psi)));
    }
}
