# V15 forensic correction (TB350FU)

Source artifacts inspected on 2026-09-30:

* `bugreport_v15_rgb.zip` from the connected Drive (MD5 `a568912684cf066560d5a880c51fc0c1`)
* `hyperos_boot.txt` from the connected Drive (MD5 `a00cbdadaa9ba0ae35c1c663ac3a4006`)

The artifacts are intentionally not committed because they contain device logs and may contain identifiers.

## Proven device baseline

The bugreport properties identify:

```text
ro.product.device=TB350FU
ro.build.version.release=14
ro.build.version.sdk=34
ro.build.fingerprint=Lenovo/TB350FU_EEA/TB350FU:14/UP1A.231005.007/TB350FU_S231044_260105_ROW:user/release-keys
ro.boot.slot_suffix=_a
ro.boot.verifiedbootstate=orange
```

`orange` means the bootloader reports an unlocked/custom-verification state. It does not mean AVB can be ignored, but it disproves the assumption that this capture came from a normally locked green verified-boot state.

## What the log actually shows

The supplied boot log does **not** show a 50 ms cryptographic watchdog shutdown:

1. SurfaceFlinger starts at approximately `15:21:34.023`.
2. It connects physical display 0 and enables power mode 2.
3. Zygote and SystemServer continue starting.
4. Android reaches boot phase 1000 around `15:21:45.9` — roughly 12 seconds after SurfaceFlinger starts.
5. `mBootCompleted=true` is visible in DisplayPowerController/PowerManager logging.
6. The focused windows include `com.android.settings.FallbackHome` and `NotificationShade`.
7. The boot log contains no matching fatal signal, AVB failure, dm-verity failure, watchdog bite, or `sys.powerctl` shutdown.
8. The hardware-composer `SWWatchDog` messages are anchor bookkeeping messages during initialization, not evidence of a watchdog power cut.

The later host bugreport reports:

```text
gsid.image_installed=1
ro.gsid.image_running=0
```

and the recorded `com.android.dynsystem` process deaths are `OTHER KILLS BY SYSTEM / TOO MANY EMPTY PROCS`, not a cryptographic verification kill.

## Likely investigation direction

The recurring graphics evidence is more relevant than the AVB theory:

* `Unrecognized RenderEngineType`
* repeated Mali EGL messages (`eglp_winsys_populate_image_templates`)
* MediaTek HWC/SF vendor extensions running against a foreign Android userspace
* refresh-rate transitions among 120/60/30 Hz
* guest/host framework and vendor generation mismatch

The donor is Xiaomi Pad 9 Pro Max `yingtian`, Android 17 / HyperOS 4, built for XRing O3. The Lenovo base is Android 14 on MediaTek MT8781/Helio G99. Therefore donor `vendor`, `odm`, `vendor_dlkm`, `boot`, HWC, GPU, camera, audio, thermal, power, and hardware-specific native libraries must **not** replace Lenovo equivalents. Safe transplant candidates are limited to independently testable resources and applications; even MiuiHome/SystemUI can require Xiaomi platform signatures and framework services.

## Build consequence

Use the exact `TB350FU_S231044_260105_ROW` factory package matching the installed device, not the older `S230982` base embedded in the downloaded local kit. Preserve Lenovo kernel/vendor/odm and perform an allowlisted userspace transplant. A whole-HyperOS framework replacement is not a credible bootable target without source-level framework and SELinux/VINTF integration.
