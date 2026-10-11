# Rust Engine (MysticalOS 2.0, Rozkaz 14)

- `coreutils` - uutils/coreutils (Rust) MULTICALL, aarch64-unknown-linux-musl,
  ELF64 EXEC STATIC (11 383 176 B). Zbudowana przez usera (modul
  MysticalOS_2.0_HyperOS4_A17_Rust_TB350FU.zip z Drive); zweryfikowana:
  ELF64/AArch64/static, qemu-aarch64 --version OK. Uzywana jako
  /system/bin/coreutils w obrazie permanent.
- `mystical-rust-daemon` - skrypt demona usera (zRAM 4 GB LZ4 + schedutil
  tuning + VM tune + petla utrzymaniowa). Uzywany jako
  /system/bin/mystical-rust-daemon; serwis init: mystical_rust.rc
  (class main / root / oneshot) wg spec Rozkazu 14.
