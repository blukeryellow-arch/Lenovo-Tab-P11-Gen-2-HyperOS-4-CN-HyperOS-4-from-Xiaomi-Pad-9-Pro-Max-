# HyperOS 4 CN GSI — Lenovo Tab P11 Gen 2 (TB350FU)

Narzędzia i dokumentacja dla naprawy bootloopu `system_server` w porcie HyperOS
4 CN na vendorze Lenovo Android 14.

## Co zawiera repozytorium

- `tools/apply_compat_patches.py` — dodaje null-check / exception guard dla
  brakującego Lenovo `IBatteryServiceManager` oraz tymczasowy argument bootowy
  SELinux permissive do wskazanego `BoardConfig.mk`.
- `tools/build_system_image.sh` — buduje `system.img` z pasującego drzewa
  źródeł i opcjonalnie tworzy archiwum `.lz4hc` lub `.gz`.
- [`PATCHING.md`](PATCHING.md) — wymagania, ograniczenia GSI i pełna procedura.

> Obecny checkout nie zawiera obrazu wejściowego ani źródeł HyperOS. Skrypt
> jest celowo restrykcyjny: modyfikuje wyłącznie źródło zawierające dokładny
> hook Lenovo zgłoszony w logcat i nie generuje pozornie „naprawionego” obrazu
> z niepasującego frameworku.
