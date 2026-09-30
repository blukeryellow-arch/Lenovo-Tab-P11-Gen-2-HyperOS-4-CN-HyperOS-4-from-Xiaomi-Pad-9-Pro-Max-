# MysticalOS 3 — Build V16 repack toolkit

Reproducible tooling for **Lenovo Tab P11 Gen 2 (TB350FU / MT6789)** dynamic-partition research. This repository does not contain Lenovo, Google, Xiaomi, microG, or Aurora binaries.

> **Current status:** tooling and safety checks are present, but no ROM has been built in this checkout because the required factory `super.img`, Lenovo flash manifest, HyperOS donor dump, and APK inputs are not in the repository.

## Important corrections to the V16 design

* A modified `super.img` is not accepted by a locked production device merely because it was repacked. AVB authenticates logical partitions through `vbmeta*`. A bootable development build requires either Lenovo's private signing keys (not publicly available), or an **unlocked bootloader** and a device-specific, explicitly tested AVB strategy. This toolkit never claims that test keys reproduce an OEM signature.
* DSU verification and a display flash do not, by themselves, prove a SHA-256 watchdog power cut. Preserve `logcat`, `dmesg`, pstore/ramoops, and bootloader logs before assigning a cause.
* Android dynamic partitions are logical block devices inside `super`; flashing a logical `system` from **fastbootd** is supported on many devices and is not inherently partition-table corruption. Device geometry and the actual Lenovo flash manifest are authoritative.
* “32 chunks” is an RSA-package format detail, not an Android requirement. Arbitrarily splitting an Android sparse image does not create 32 independently flashable sparse images. Chunking is deliberately excluded until the original Lenovo manifest/chunk format is supplied.
* microG signature spoofing requires framework support. Copying FakeStore or a permissions XML does not add signature spoofing. The preflight report flags this rather than silently patching version-specific framework bytecode.
* Xiaomi Launcher/SystemUI components are platform-signed and depend on Xiaomi framework resources, permissions, services, and native libraries. The toolkit stages and audits them; it does not promise that copying APKs will make them work on Lenovo's framework.
* Closed-source Binder proxy code cannot be automatically “refactored into Rust” during image repacking. That request is intentionally not implemented. Rust conversion requires source code, ABI design, tests, and integration into the Android build graph.

## Required local inputs

Copy these outside Git (the paths are ignored):

```text
inputs/
├── lenovo/
│   ├── super.img                 # reconstructed full factory image, not one arbitrary chunk
│   └── flash_manifest/           # all XML/JSON/bat metadata from the same RSA release
├── hyperos/
│   ├── MiuiHome.apk
│   └── ...                       # only components you are licensed to use
└── apks/
    ├── GmsCore.apk
    ├── FakeStore.apk
    ├── AuroraStore.apk
    └── privapp-permissions-microg.xml # reviewed allowlist matching that GmsCore build
```

Also provide SHA-256 values in `config/inputs.sha256`. Obtain open-source APKs from their official release channels and verify signatures/checksums before use; the script does not silently download a moving “latest” release.

Host dependencies (AOSP versions matching or newer than the image are recommended):

```text
lpdump lpunpack lpmake simg2img img2simg avbtool
file jq sha256sum e2fsck resize2fs mount umount rsync getfattr setfattr
apkanalyzer (or aapt2) readelf
```

Image mutation uses a private mount namespace and loop mount, so it requires Linux root. Extraction and planning do not.

## Usage

```bash
# 1. Verify tools, files, sparse format, hashes, and AVB-related inputs.
python3 tools/preflight.py --config config/v16.json

# 2. Extract every logical partition and record the original LP geometry.
scripts/build_v16.sh extract

# 3. Produce an auditable mutation plan (no image writes).
scripts/build_v16.sh plan

# 4. Only on an unlocked development device, after reviewing reports/plan.txt:
sudo scripts/build_v16.sh mutate --apply --i-understand-avb

# 5. Rebuild using geometry parsed from the stock image.
scripts/build_v16.sh assemble --apply --i-understand-avb

# 6. Verify the result by unpacking it again and comparing geometry/content.
scripts/build_v16.sh verify
```

Outputs are placed in `work/` and `out/`, both ignored by Git. `out/SHA256SUMS` and `out/build-report.json` provide provenance. No upload occurs automatically; publishing multi-gigabyte firmware without a successful local verification would be unsafe.

## Flashing warning

Do not flash output from this toolkit unless the bootloader is unlocked, the exact stock package and recovery path are available, every relevant partition has been backed up, and the AVB consequences are understood. Keep `preloader`, bootloader, RPMB, and calibration/NVRAM data out of experiments. Commands are intentionally not provided as a universal recipe because wrong slot/AVB instructions can hard-brick a MediaTek device.

## Repository layout

* `tools/preflight.py` — deterministic input/tool validation
* `tools/lp_metadata.py` — parses `lpdump` text and creates reviewed `lpmake` arguments
* `scripts/build_v16.sh` — phase-oriented orchestrator
* `scripts/mutate_ext4.sh` — exact, logged ext4 changes
* `config/v16.json` — package paths and conservative removal allowlist
* `tests/` — metadata parser tests

## What is needed to produce the requested binary

Attach or otherwise place the exact RSA `super.img` plus its flash manifest and the licensed HyperOS donor files in `inputs/`. State whether the TB350FU bootloader is unlocked and include `fastboot getvar all` (serial number redacted), `lpdump` output, and `avbtool info_image` output for `vbmeta.img`, `vbmeta_system.img`, and the extracted logical images. Without those inputs, generating or uploading a genuine device-specific `super.img` is not technically possible.
