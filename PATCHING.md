# HyperOS 4 / TB350FU compatibility patch set

This repository contains a **source-level** patching pipeline for the reported
`system_server` bootloop. It cannot produce a valid `system.img` until the
matching Android/HyperOS source checkout, or a modifiable unpacked framework
from the exact failing image, is available in the build workspace.

## Implemented change: missing Lenovo battery manager

`tools/apply_compat_patches.py` changes the exact standalone invocation below
in the **Lenovo runtime's** modified `BatteryService`:

```java
mBatteryServiceManager.updateHealthInfo(healthInfo);
```

It replaces it with a null guard and exception boundary:

```java
if (mBatteryServiceManager != null) {
    try {
        mBatteryServiceManager.updateHealthInfo(healthInfo);
    } catch (Exception e) {
        Slog.e(TAG, "Failed to update Lenovo custom battery info; bypassing.", e);
    }
} else {
    Slog.w(TAG, "Lenovo IBatteryServiceManager reference is null; "
            + "gracefully bypassing proprietary hooks.");
}
```

The tool stops rather than guessing if this exact call exists zero or multiple
times. That matters because a normal AOSP `BatteryService.java` has no Lenovo
manager and patching it would not repair the prebuilt framework that actually
crashed.

> **Donor verification:** the official `yingtian` China
> `OS4.0.11.0.XBMCNXM` fastboot archive was inspected directly. Its `system`
> and `system_ext` framework contains no `IBatteryServiceManager`,
> `mBatteryServiceManager`, or `com.lenovo.lgsi` reference. The Lenovo hook in
> the device log is therefore not a donor implementation waiting to be copied;
> it must be located in the Lenovo runtime/classpath that is actually loaded on
> TB350FU. See [`DONOR_AUDIT.md`](DONOR_AUDIT.md).

## Temporary SELinux diagnostic mode

The same tool appends the following line to the specific `BoardConfig.mk` used
to generate the device boot chain:

```make
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
```

It requires an explicit `--allow-insecure-permissive` acknowledgement. This is
a DSU diagnostic setting, not a `system.img` property. `ro.*` properties in a
GSI and a random `/system/etc/init/*.rc` file cannot reliably override the
SELinux state selected by first-stage init, the kernel command line, and
`boot`/`vendor_boot` on this device.

After identifying the AVCs that block hardware services, replace permissive
mode with the smallest compatible policy rules before any daily-use flash.

## Apply to a matching source checkout

```sh
python3 tools/apply_compat_patches.py \
  --android-root /work/hyperos-source \
  --boardconfig /work/hyperos-source/device/lenovo/tb350fu/BoardConfig.mk \
  --allow-insecure-permissive
```

The script changes:

- `services/core/java/com/android/server/BatteryService.java`
- the explicitly passed `BoardConfig.mk`

Review the generated diff before building:

```sh
git -C /work/hyperos-source diff -- \
  services/core/java/com/android/server/BatteryService.java \
  device/lenovo/tb350fu/BoardConfig.mk
```

## Build

```sh
tools/build_system_image.sh \
  --android-root /work/hyperos-source \
  --lunch aosp_tb350fu-userdebug \
  --compress lz4hc
```

The build target is deliberately not hard-coded: it must be the actual target
that packages the same patched framework and the appropriate `boot` or
`vendor_boot` image. `systemimage` rebuilds the framework; it does **not**
rebuild the boot chain by itself.

The output folder contains:

- `system_hyperos4_p11g2_fixed.img`
- optional `system_hyperos4_p11g2_fixed.img.lz4hc` or `.gz`
- SHA-256 manifest entries

Use the raw/sparse `.img` for DSU or fastbootd as appropriate. `.lz4hc` and
`.gz` are transport archives and must be decompressed before tools that do not
explicitly support them.

## Preconditions before an actual artifact can be released

1. The exact failing `system.img` must be copied into this workspace, or a
   matching source tree must be supplied.
2. For a prebuilt-only image, the matching `services.jar` plus ART/OAT/VDEX
   layout must be inspected and patched rather than compiling unrelated AOSP.
3. The exact `boot.img` / `vendor_boot.img` build path must be available before
   asserting that `androidboot.selinux=permissive` is active.
4. Test in DSU first. Confirm `sys.boot_completed=1`, no `system_server`
   restart, and collect a new AVC log before permanent flashing.
