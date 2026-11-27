#!/usr/bin/env python3
"""Inspekcja i bezpieczny patcher Dynamic Island + BigIcon/DeviceLevel dla HyperOS 4 (dew_global).

Zasada bezpieczenstwa:
- NIGDY nie psuje podpisow platformowych CN=MIUI w MiuiHome.apk ani MiuiSystemUI.apk
  (dla APK wykonuje tylko inspekcje diagnostyczna metod DynamicIsland/SuperIsland).
- Bezpiecznie modyfikuje wylacznie JAR-y boot/system classpath (framework.jar, miui-framework.jar,
  hyperos.rustruntime.v*.jar, itp.), gdzie nie obowiazuje sharedUserId weryfikacja PackageManagera,
  oraz wykonuje obowiazkowy roundtrip baksmali przed zapisem i czyszczenie powiazanego OAT.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from patch_services_spoof import SmaliRunner


TRUE_BOOL_METHOD_PATTERNS = (
    re.compile(r"^(?:is|get|has)?[Ss]upportDynamicIsland\w*\(\)Z$"),
    re.compile(r"^[dD]ynamicIsland(?:Supported|Enable|Enabled)\(\)Z$"),
    re.compile(r"^(?:is|get|has)?[Ss]upportSuperIsland\w*\(\)Z$"),
    re.compile(r"^(?:is|get|has)?[Ii]slandSupport\w*\(\)Z$"),
    re.compile(r"^(?:is|get|has)?[Ss]upport(?:Big|Large)Icon\w*\(\)Z$"),
)

FALSE_BOOL_METHOD_PATTERNS = (
    re.compile(r"^isMiuiLite(?:Version|Plus)?\(\)Z$"),
    re.compile(r"^isMiuiMiddle(?:Version)?\(\)Z$"),
)

HIGH_LEVEL_INT_PATTERNS = (
    re.compile(r"^get(?:Overall)?DeviceLevel\(\)I$"),
    re.compile(r"^getComputilityLevel\w*\(\)I$"),
)

ISLAND_DIAG_RE = re.compile(
    r"(DynamicIsland|SuperIsland|support_dynamic_island|support_largeicon|isSupportBigIcon|isMiuiLite|device_level)"
)


def patch_smali_file(smali_path: Path, is_device_level_scope: bool) -> list[str]:
    """Patch verified simple 0-arg boolean/int gate methods inside a single .smali file."""
    txt = smali_path.read_text(encoding="utf-8", errors="replace")
    lines = txt.splitlines()
    out: list[str] = []
    changes: list[str] = []

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        s = line.strip()
        if s.startswith(".method "):
            tokens = s.split()
            sig = tokens[-1] if tokens else ""
            is_abstract_or_native = (" abstract " in f" {s} ") or (" native " in f" {s} ")
            replacement: list[str] | None = None

            if not is_abstract_or_native:
                if any(p.match(sig) for p in TRUE_BOOL_METHOD_PATTERNS):
                    replacement = [
                        line,
                        "    .locals 1",
                        "    const/4 v0, 0x1",
                        "    return v0",
                        ".end method",
                    ]
                    changes.append(f"{smali_path.name}:{sig}->TRUE")
                elif is_device_level_scope and any(p.match(sig) for p in FALSE_BOOL_METHOD_PATTERNS):
                    replacement = [
                        line,
                        "    .locals 1",
                        "    const/4 v0, 0x0",
                        "    return v0",
                        ".end method",
                    ]
                    changes.append(f"{smali_path.name}:{sig}->FALSE")
                elif is_device_level_scope and any(p.match(sig) for p in HIGH_LEVEL_INT_PATTERNS):
                    replacement = [
                        line,
                        "    .locals 1",
                        "    const/4 v0, 0x3",
                        "    return v0",
                        ".end method",
                    ]
                    changes.append(f"{smali_path.name}:{sig}->3")

            if replacement is not None:
                # Consume original method body until .end method
                j = i + 1
                while j < n and lines[j].strip() != ".end method":
                    j += 1
                if j < n:
                    out.extend(replacement)
                    i = j + 1
                    continue

        out.append(line)
        i += 1

    if changes:
        smali_path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return changes


def inspect_apk_island_symbols(
    apk_path: Path,
    runner: SmaliRunner,
    tmp: Path,
    log: list[str],
) -> None:
    """Read-only diagnostic scan of Dynamic Island / Large Icon classes in APKs (never alters APK signature)."""
    if not apk_path.is_file():
        return
    with zipfile.ZipFile(apk_path, "r") as zf:
        dex_names = sorted(n for n in zf.namelist() if re.fullmatch(r"classes\d*\.dex", n))
    if not dex_names:
        log.append(f"island inspect {apk_path.name}: no DEX (native/vdex only)")
        return

    hits: list[str] = []
    for dn in dex_names[:4]:
        dex_p = tmp / f"ins_{apk_path.stem}_{dn}"
        with zipfile.ZipFile(apk_path, "r") as zf:
            dex_p.write_bytes(zf.read(dn))
        sm_dir = tmp / f"ins_{apk_path.stem}_{dn.replace('.dex', '')}"
        r = runner.baksmali(dex_p, sm_dir)
        dex_p.unlink(missing_ok=True)
        if r.returncode != 0:
            continue
        for sm in sorted(sm_dir.rglob("*.smali")):
            rel = str(sm.relative_to(sm_dir))
            if any(tok in rel.lower() for tok in ("island", "devicelevel", "bigicon", "largeicon")):
                hits.append(rel.replace(".smali", ""))
                txt = sm.read_text(encoding="utf-8", errors="replace")
                for ln in txt.splitlines():
                    if ln.startswith(".method ") and ISLAND_DIAG_RE.search(ln):
                        if len(hits) < 40:
                            hits.append(f"  {rel}: {ln.strip()}")
        shutil.rmtree(sm_dir, ignore_errors=True)
        if len(hits) >= 40:
            break

    log.append(f"island inspect {apk_path.name} ({len(dex_names)} dex): {len(hits)} matching symbols")
    for h in hits[:16]:
        log.append(f"  {h}")


def patch_framework_jar(
    jar_path: Path,
    runner: SmaliRunner,
    tmp: Path,
    oat_dirs: list[Path],
    log: list[str],
) -> int:
    if not jar_path.is_file():
        return 0
    with zipfile.ZipFile(jar_path, "r") as zf:
        dex_names = sorted(n for n in zf.namelist() if re.fullmatch(r"classes\d*\.dex", n))
    if not dex_names:
        log.append(f"island framework {jar_path.name}: skipped (no classes*.dex)")
        return 0

    patched_dex_map: dict[str, Path] = {}
    all_changes: list[str] = []

    for dn in dex_names:
        dex_p = tmp / f"{jar_path.stem}_{dn}"
        with zipfile.ZipFile(jar_path, "r") as zf:
            dex_p.write_bytes(zf.read(dn))
        sm_dir = tmp / f"{jar_path.stem}_{dn.replace('.dex', '')}"
        r = runner.baksmali(dex_p, sm_dir)
        dex_p.unlink(missing_ok=True)
        if r.returncode != 0:
            shutil.rmtree(sm_dir, ignore_errors=True)
            continue

        dex_changes: list[str] = []
        for sm in sorted(sm_dir.rglob("*.smali")):
            rel_low = str(sm.relative_to(sm_dir)).lower()
            is_dev_scope = any(
                k in rel_low
                for k in ("devicelevel", "miui/os/build", "island", "rustruntime", "launcher", "feature")
            )
            txt = sm.read_text(encoding="utf-8", errors="replace")
            if ISLAND_DIAG_RE.search(txt) or is_dev_scope:
                dex_changes.extend(patch_smali_file(sm, is_dev_scope))

        if dex_changes:
            new_dex = tmp / f"{jar_path.stem}_patched_{dn}"
            r2 = runner.smali(sm_dir, new_dex)
            rt_dir = tmp / f"{jar_path.stem}_rt_{dn.replace('.dex', '')}"
            if r2.returncode == 0 and new_dex.is_file():
                r3 = runner.baksmali(new_dex, rt_dir)
                if r3.returncode == 0:
                    patched_dex_map[dn] = new_dex
                    all_changes.extend(dex_changes)
                else:
                    new_dex.unlink(missing_ok=True)
            shutil.rmtree(rt_dir, ignore_errors=True)
        shutil.rmtree(sm_dir, ignore_errors=True)

    if not patched_dex_map:
        log.append(f"island framework {jar_path.name}: 0 gated methods needing DEX patch")
        return 0

    try:
        orig_ctx = os.getxattr(jar_path, "security.selinux", follow_symlinks=False)
    except OSError:
        orig_ctx = None

    rebuilt = tmp / f"{jar_path.stem}_rebuilt.jar"
    with zipfile.ZipFile(jar_path, "r") as zin, zipfile.ZipFile(rebuilt, "w") as zout:
        for item in zin.infolist():
            if item.filename in patched_dex_map:
                data = patched_dex_map[item.filename].read_bytes()
                zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                zi.compress_type = zipfile.ZIP_STORED
            else:
                data = zin.read(item.filename)
                zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                zi.compress_type = item.compress_type
            zout.writestr(zi, data)

    shutil.copy2(rebuilt, jar_path)
    os.chmod(jar_path, 0o644)
    if orig_ctx:
        try:
            os.setxattr(jar_path, "security.selinux", orig_ctx, follow_symlinks=False)
        except OSError:
            pass

    stem = jar_path.stem
    for od in oat_dirs:
        if od.is_dir():
            for f in list(od.rglob(f"{stem}.*")):
                if f.is_file():
                    f.unlink()

    log.append(f"island framework {jar_path.name}: PATCHED {len(all_changes)} methods ({', '.join(all_changes[:12])})")
    return len(all_changes)


def patch_tree(out_sys_root: Path, out_sys_ext: Path, out_prod: Path, apktool_jar: str, log: list[str]) -> int:
    if not apktool_jar or not Path(apktool_jar).is_file():
        log.append("island patcher: brak apktool.jar (pomijam skanowanie DEX)")
        return 0

    total_patched = 0
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        try:
            runner = SmaliRunner(Path(apktool_jar), tmp)
        except Exception as exc:
            log.append(f"island patcher init skip: {exc}")
            return 0

        # 1. Inspect SystemUI & MiuiHome APKs read-only (never break CN=MIUI signatures)
        apk_candidates = [
            out_sys_ext / "priv-app" / "MiuiSystemUI" / "MiuiSystemUI.apk",
            out_prod / "priv-app" / "MIUISystemUIPlugin" / "MIUISystemUIPlugin.apk",
            out_sys_ext / "priv-app" / "MIUISystemUIPlugin" / "MIUISystemUIPlugin.apk",
        ]
        for apk in apk_candidates:
            if apk.is_file():
                inspect_apk_island_symbols(apk, runner, tmp, log)

        # 2. Patch boot/framework JARs cleanly
        oat_dirs = [out_sys_root / "framework" / "oat", out_sys_ext / "framework" / "oat"]
        fw_candidates: list[Path] = []
        for fdir in (out_sys_ext / "framework", out_sys_root / "framework"):
            if not fdir.is_dir():
                continue
            for jar in sorted(fdir.glob("*.jar")):
                low = jar.name.lower()
                if (
                    "rustruntime" in low
                    or "miui" in low
                    or "hyper" in low
                    or low in ("framework.jar", "miui-framework.jar", "miui-services.jar")
                ):
                    fw_candidates.append(jar)

        for jar in fw_candidates:
            total_patched += patch_framework_jar(jar, runner, tmp, oat_dirs, log)

    return total_patched


def selftest() -> int:
    sample = """.class public final Lmiui/os/DynamicIslandFeature;
.super Ljava/lang/Object;

.method public static isSupportDynamicIsland()Z
    .locals 1
    const/4 v0, 0x0
    return v0
.end method

.method public static isMiuiLiteVersion()Z
    .locals 1
    const/4 v0, 0x1
    return v0
.end method

.method public static getDeviceLevel()I
    .locals 1
    const/4 v0, 0x1
    return v0
.end method
"""
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "DynamicIslandFeature.smali"
        p.write_text(sample, encoding="utf-8")
        changes = patch_smali_file(p, is_device_level_scope=True)
        out = p.read_text(encoding="utf-8")
        assert len(changes) == 3, f"expected 3 changes, got {changes}"
        assert "const/4 v0, 0x1\n    return v0" in out
        assert "const/4 v0, 0x0\n    return v0" in out
        assert "const/4 v0, 0x3\n    return v0" in out
    print("patch_hyperos4_island selftest OK!")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--sys-root", default="")
    ap.add_argument("--sys-ext", default="")
    ap.add_argument("--product", default="")
    ap.add_argument("--apktool-jar", default="")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    log: list[str] = []
    patch_tree(Path(args.sys_root), Path(args.sys_ext), Path(args.product), args.apktool_jar, log)
    print("\n".join(log))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
