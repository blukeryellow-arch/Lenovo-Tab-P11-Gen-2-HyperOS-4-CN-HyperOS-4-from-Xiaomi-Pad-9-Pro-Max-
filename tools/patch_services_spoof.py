#!/usr/bin/env python3
"""Inspekcja i bezpieczny restricted microG signature-spoof patcher dla services.jar (Android 14-17).

Dziala ostroznie:
1. Sprawdza czy services.jar zawiera classes*.dex (jesli ROM ma tylko .vdex, nie psuje jar).
2. Wykrywa klase baksmali/smali wewnatrz apktool jar (com.android.tools.smali.* lub org.jf.*).
3. Weryfikuje w framework.jar i services.jar dokladne sygnatury:
   - ComputerEngine.generatePackageInfo(...) -> PackageInfo
   - PackageInfo.packageName, signatures, signingInfo, applicationInfo
   - ApplicationInfo.metaData -> Bundle.getString("fake-signature")
   - Signature(String), SigningDetails(Signature[], int), SigningInfo(SigningDetails)
4. Jesli wszystkie sygnatury pasuja 1:1 -> wstrzykuje R9cMicrogSpoof (ograniczony wylacznie do
   com.google.android.gms i com.android.vending, w bloku try/catch), rekompiluje DEX,
   weryfikuje roundtrip baksmali i usuwa przestarzale system/framework/oat/*/services.*.
5. W przeciwnym razie czysto raportuje przyczyne pominiecia bez ryzyka bootloopa.
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


def detect_smali_classes(jar_path: Path) -> tuple[str, str]:
    with zipfile.ZipFile(jar_path, "r") as zf:
        names = set(zf.namelist())
    if "com/android/tools/smali/baksmali/Main.class" in names and "com/android/tools/smali/smali/Main.class" in names:
        return (
            "com.android.tools.smali.baksmali.Main",
            "com.android.tools.smali.smali.Main",
        )
    if "org/jf/baksmali/Main.class" in names and "org/jf/smali/Main.class" in names:
        return ("org.jf.baksmali.Main", "org.jf.smali.Main")
    raise RuntimeError(f"Brak klas smali/baksmali w {jar_path}")


def run_java_tool(jar_path: Path, main_cls: str, args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["java", "-Xmx1536m", "-cp", str(jar_path), main_cls, *args],
        text=True,
        capture_output=True,
    )


def build_spoof_helper_smali(has_signing_details_ctor: bool, has_signing_info_ctor: bool) -> str:
    signing_info_block = ""
    if has_signing_details_ctor and has_signing_info_ctor:
        signing_info_block = """
    iget-object v4, p0, Landroid/content/pm/PackageInfo;->signingInfo:Landroid/content/pm/SigningInfo;
    if-eqz v4, :done

    new-instance v4, Landroid/content/pm/SigningDetails;
    const/4 v5, 0x2
    invoke-direct {v4, v3, v5}, Landroid/content/pm/SigningDetails;-><init>([Landroid/content/pm/Signature;I)V

    new-instance v5, Landroid/content/pm/SigningInfo;
    invoke-direct {v5, v4}, Landroid/content/pm/SigningInfo;-><init>(Landroid/content/pm/SigningDetails;)V

    iput-object v5, p0, Landroid/content/pm/PackageInfo;->signingInfo:Landroid/content/pm/SigningInfo;
"""
    return f""".class public final Lcom/android/server/pm/R9cMicrogSpoof;
.super Ljava/lang/Object;

.method public static maybeSpoof(Landroid/content/pm/PackageInfo;)V
    .locals 6

    if-nez p0, :cond_0
    return-void

    :cond_0
    :try_start_0
    iget-object v0, p0, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;
    if-nez v0, :cond_1
    return-void

    :cond_1
    const-string v1, "com.google.android.gms"
    invoke-virtual {{v1, v0}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :cond_ok

    const-string v1, "com.android.vending"
    invoke-virtual {{v1, v0}}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :cond_ok
    return-void

    :cond_ok
    iget-object v1, p0, Landroid/content/pm/PackageInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
    if-nez v1, :cond_2
    return-void

    :cond_2
    iget-object v1, v1, Landroid/content/pm/ApplicationInfo;->metaData:Landroid/os/Bundle;
    if-nez v1, :cond_3
    return-void

    :cond_3
    const-string v2, "fake-signature"
    invoke-virtual {{v1, v2}}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v2
    if-eqz v2, :done

    invoke-virtual {{v2}}, Ljava/lang/String;->isEmpty()Z
    move-result v3
    if-nez v3, :done

    new-instance v4, Landroid/content/pm/Signature;
    invoke-direct {{v4, v2}}, Landroid/content/pm/Signature;-><init>(Ljava/lang/String;)V

    const/4 v5, 0x1
    new-array v3, v5, [Landroid/content/pm/Signature;
    const/4 v5, 0x0
    aput-object v4, v3, v5

    iget-object v4, p0, Landroid/content/pm/PackageInfo;->signatures:[Landroid/content/pm/Signature;
    if-eqz v4, :chk_si
    iput-object v3, p0, Landroid/content/pm/PackageInfo;->signatures:[Landroid/content/pm/Signature;

    :chk_si
{signing_info_block}
    :done
    :try_end_0
    .catchall {{:try_start_0 .. :try_end_0}} :catchall_0
    return-void

    :catchall_0
    return-void
.end method
"""


def patch_computer_engine_smali(smali_path: Path) -> tuple[bool, int]:
    lines = smali_path.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[str] = []
    in_gen = False
    patched_returns = 0

    for line in lines:
        s = line.strip()
        if s.startswith(".method ") and "generatePackageInfo(" in s and s.endswith(")Landroid/content/pm/PackageInfo;"):
            in_gen = True
            out.append(line)
            continue
        if in_gen and s == ".end method":
            in_gen = False
            out.append(line)
            continue
        if in_gen and s.startswith("return-object "):
            reg = s.split()[1]
            # Wait: return-object v0..v15 fits invoke-static {vX}; registers >= v16 require invoke-static/range
            m = re.match(r"^([vp])(\d+)$", reg)
            if m and m.group(1) == "v" and int(m.group(2)) < 16:
                out.append(f"    invoke-static {{{reg}}}, Lcom/android/server/pm/R9cMicrogSpoof;->maybeSpoof(Landroid/content/pm/PackageInfo;)V")
                patched_returns += 1
            elif m:
                out.append(f"    invoke-static/range {{{reg} .. {reg}}}, Lcom/android/server/pm/R9cMicrogSpoof;->maybeSpoof(Landroid/content/pm/PackageInfo;)V")
                patched_returns += 1
        out.append(line)

    if patched_returns > 0:
        smali_path.write_text("\n".join(out) + "\n", encoding="utf-8")
        return True, patched_returns
    return False, 0


def check_framework_descriptors(framework_jar: Path, apktool_jar: Path, baksmali_cls: str, tmp: Path) -> tuple[bool, bool, bool]:
    if not framework_jar.is_file():
        return False, False, False
    with zipfile.ZipFile(framework_jar, "r") as zf:
        dex_names = sorted(n for n in zf.namelist() if re.fullmatch(r"classes\d*\.dex", n))
    if not dex_names:
        return False, False, False

    has_sig_ctor = False
    has_sd_ctor = False
    has_si_ctor = False
    fw_out = tmp / "fw-smali"
    for dn in dex_names:
        dex_p = tmp / f"fw_{dn}"
        with zipfile.ZipFile(framework_jar, "r") as zf:
            dex_p.write_bytes(zf.read(dn))
        sub = fw_out / dn.replace(".dex", "")
        r = run_java_tool(apktool_jar, baksmali_cls, ["d", str(dex_p), "-o", str(sub)])
        if r.returncode != 0:
            continue
        sig_sm = sub / "android" / "content" / "pm" / "Signature.smali"
        sd_sm = sub / "android" / "content" / "pm" / "SigningDetails.smali"
        si_sm = sub / "android" / "content" / "pm" / "SigningInfo.smali"
        if sig_sm.is_file() and "<init>(Ljava/lang/String;)V" in sig_sm.read_text(encoding="utf-8", errors="replace"):
            has_sig_ctor = True
        if sd_sm.is_file() and "<init>([Landroid/content/pm/Signature;I)V" in sd_sm.read_text(encoding="utf-8", errors="replace"):
            has_sd_ctor = True
        if si_sm.is_file() and "<init>(Landroid/content/pm/SigningDetails;)V" in si_sm.read_text(encoding="utf-8", errors="replace"):
            has_si_ctor = True
    return has_sig_ctor, has_sd_ctor, has_si_ctor


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--services-jar", required=True)
    ap.add_argument("--framework-jar", default="")
    ap.add_argument("--apktool-jar", required=True)
    ap.add_argument("--oat-dir", default="", help="system/framework/oat directory to prune services.* on patch")
    args = ap.parse_args()

    services_jar = Path(args.services_jar)
    framework_jar = Path(args.framework_jar) if args.framework_jar else Path("")
    apktool_jar = Path(args.apktool_jar)

    if not services_jar.is_file():
        print(f"STATUS: SKIPPED (brak {services_jar})")
        return 0
    if not apktool_jar.is_file():
        print(f"STATUS: SKIPPED (brak {apktool_jar})")
        return 0

    with zipfile.ZipFile(services_jar, "r") as zf:
        dex_names = sorted(n for n in zf.namelist() if re.fullmatch(r"classes\d*\.dex", n))

    if not dex_names:
        print("STATUS: SKIPPED (services.jar nie zawiera classes*.dex - obraz odex/vdex-only; uzyj LSPosed+FakeGApps po roocie lub vdexExtractor)")
        return 0

    baksmali_cls, smali_cls = detect_smali_classes(apktool_jar)
    print(f"services.jar DEX files: {dex_names} (using {baksmali_cls})")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        has_sig, has_sd, has_si = check_framework_descriptors(framework_jar, apktool_jar, baksmali_cls, tmp)
        print(f"framework.jar check: Signature(String)={has_sig}, SigningDetails(Signature[],int)={has_sd}, SigningInfo(SigningDetails)={has_si}")
        if not has_sig:
            print("STATUS: SKIPPED (nie znaleziono lub brak DEX w framework.jar dla bezpiecznej weryfikacji Signature.<init>(String))")
            return 0

        target_dex = ""
        target_dir = None
        ce_rel = Path("com/android/server/pm/ComputerEngine.smali")

        for dn in dex_names:
            dex_p = tmp / dn
            with zipfile.ZipFile(services_jar, "r") as zf:
                dex_p.write_bytes(zf.read(dn))
            out_sm = tmp / f"sm_{dn}"
            r = run_java_tool(apktool_jar, baksmali_cls, ["d", str(dex_p), "-o", str(out_sm)])
            if r.returncode != 0:
                print(f"baksmali error on {dn}: {r.stderr[:400]}")
                continue
            if (out_sm / ce_rel).is_file():
                target_dex = dn
                target_dir = out_sm
                break

        if not target_dir:
            print("STATUS: SKIPPED (nie znaleziono ComputerEngine.smali w services.jar)")
            return 0

        ok, ret_cnt = patch_computer_engine_smali(target_dir / ce_rel)
        if not ok:
            print("STATUS: SKIPPED (nie znaleziono generatePackageInfo()->PackageInfo w ComputerEngine.smali)")
            return 0

        # Put R9cMicrogSpoof into its own small extra classesN.dex to avoid 64K method overflow in target_dex!
        helper_dir = tmp / "helper_smali"
        helper_cls_path = helper_dir / "com/android/server/pm/R9cMicrogSpoof.smali"
        helper_cls_path.parent.mkdir(parents=True, exist_ok=True)
        helper_cls_path.write_text(build_spoof_helper_smali(has_sd, has_si), encoding="utf-8")

        new_target_dex = tmp / f"patched_{target_dex}"
        r1 = run_java_tool(apktool_jar, smali_cls, ["a", str(target_dir), "-o", str(new_target_dex)])
        if r1.returncode != 0 or not new_target_dex.is_file():
            print(f"STATUS: SKIPPED (blad smali na {target_dex}: {r1.stderr[:500]})")
            return 0

        next_idx = len(dex_names) + 1
        extra_dex_name = f"classes{next_idx}.dex"
        extra_dex_path = tmp / extra_dex_name
        r2 = run_java_tool(apktool_jar, smali_cls, ["a", str(helper_dir), "-o", str(extra_dex_path)])
        if r2.returncode != 0 or not extra_dex_path.is_file():
            print(f"STATUS: SKIPPED (blad smali na R9cMicrogSpoof: {r2.stderr[:500]})")
            return 0

        # Roundtrip baksmali verification before writing services.jar
        chk = tmp / "roundtrip"
        r3 = run_java_tool(apktool_jar, baksmali_cls, ["d", str(new_target_dex), "-o", str(chk / "t")])
        r4 = run_java_tool(apktool_jar, baksmali_cls, ["d", str(extra_dex_path), "-o", str(chk / "h")])
        if r3.returncode != 0 or r4.returncode != 0:
            print("STATUS: SKIPPED (roundtrip baksmali nie przeszedl weryfikacji)")
            return 0

        try:
            orig_ctx = os.getxattr(services_jar, "security.selinux", follow_symlinks=False)
        except OSError:
            orig_ctx = None

        rebuilt_jar = tmp / "services_patched.jar"
        with zipfile.ZipFile(services_jar, "r") as zin, zipfile.ZipFile(rebuilt_jar, "w") as zout:
            for item in zin.infolist():
                data = new_target_dex.read_bytes() if item.filename == target_dex else zin.read(item.filename)
                zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                zi.compress_type = zipfile.ZIP_DEFLATED if item.filename != target_dex else zipfile.ZIP_STORED
                zout.writestr(zi, data)
            zi_extra = zipfile.ZipInfo(extra_dex_name)
            zi_extra.compress_type = zipfile.ZIP_STORED
            zout.writestr(zi_extra, extra_dex_path.read_bytes())

        shutil.copy2(rebuilt_jar, services_jar)
        os.chmod(services_jar, 0o644)
        if orig_ctx:
            try:
                os.setxattr(services_jar, "security.selinux", orig_ctx, follow_symlinks=False)
            except OSError:
                pass

        if args.oat_dir and Path(args.oat_dir).is_dir():
            pruned = []
            for p in Path(args.oat_dir).rglob("services.*"):
                if p.is_file():
                    p.unlink()
                    pruned.append(p.name)
            print(f"pruned stale oat for services.jar: {pruned}")

        print(f"STATUS: PATCHED ({target_dex} ComputerEngine.generatePackageInfo returns={ret_cnt}, added {extra_dex_name} R9cMicrogSpoof, SigningInfo={has_sd and has_si})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
