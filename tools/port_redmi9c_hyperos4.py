#!/usr/bin/env python3
"""Port and aggressively debloat HyperOS 4 (Android 17, Global 'dew') onto Redmi 9C ('blossom' OSS A17 base).

Preserves Linux modes, symlinks, ownership, and security.selinux xattrs.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def cp_preserve(src: Path, dst: Path) -> None:
    """Copy file or directory tree preserving mode, symlinks, timestamps, and SELinux xattrs."""
    if src.is_dir() and not src.is_symlink():
        if not dst.exists() and not dst.is_symlink():
            dst.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["cp", "-a", "--preserve=all", str(src), str(dst)], check=True)
        else:
            subprocess.run(["cp", "-a", "--preserve=all", f"{src}/.", str(dst)], check=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists() or dst.is_symlink():
            if dst.is_dir() and not dst.is_symlink():
                shutil.rmtree(dst)
            else:
                dst.unlink()
        subprocess.run(["cp", "-a", "--preserve=all", str(src), str(dst)], check=True)


def copy_missing_from_dir(src_dir: Path, dst_dir: Path, pattern: str = "*") -> list[str]:
    copied: list[str] = []
    if not src_dir.is_dir():
        return copied
    dst_dir.mkdir(parents=True, exist_ok=True)
    for item in sorted(src_dir.glob(pattern)):
        target = dst_dir / item.name
        if not target.exists() and not target.is_symlink():
            cp_preserve(item, target)
            copied.append(item.name)
    return copied


def resolve_sys_root(system_part: Path) -> Path:
    """Return actual /system dir inside system partition (handles SAR system/system/)."""
    nested = system_part / "system"
    if nested.is_dir() and (
        (nested / "build.prop").is_file()
        or (nested / "bin").is_dir()
        or (nested / "etc").is_dir()
    ):
        return nested
    return system_part


def dir_size_bytes(path: Path) -> int:
    total = 0
    for root, dirs, files in os.walk(path, followlinks=False):
        for fn in files:
            fp = Path(root) / fn
            try:
                if not fp.is_symlink():
                    total += fp.stat().st_size
            except OSError:
                pass
    return total


def read_props(path: Path) -> dict[str, str]:
    props: dict[str, str] = {}
    if not path.is_file():
        return props
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        props[k.strip()] = v.strip()
    return props


def patch_prop_file(
    path: Path,
    updates: dict[str, str],
    append_lines: Iterable[str] = (),
    replace_pairs: Iterable[tuple[str, str]] = (),
) -> None:
    if not path.is_file():
        return
    try:
        orig_ctx = os.getxattr(path, "security.selinux", follow_symlinks=False)
    except OSError:
        orig_ctx = None

    raw_lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out_lines: list[str] = []
    seen_keys: set[str] = set()

    for line in raw_lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            k, _ = stripped.split("=", 1)
            k = k.strip()
            if k in updates:
                if k not in seen_keys:
                    out_lines.append(f"{k}={updates[k]}")
                    seen_keys.add(k)
                continue
        new_line = line
        for old_s, new_s in replace_pairs:
            if old_s in new_line:
                new_line = new_line.replace(old_s, new_s)
        out_lines.append(new_line)

    for k, v in updates.items():
        if k not in seen_keys:
            out_lines.append(f"{k}={v}")
            seen_keys.add(k)

    existing_set = {ln.strip() for ln in out_lines}
    for extra in append_lines:
        if extra.strip() and extra.strip() not in existing_set:
            out_lines.append(extra.strip())
            existing_set.add(extra.strip())

    path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    if orig_ctx:
        try:
            os.setxattr(path, "security.selinux", orig_ctx, follow_symlinks=False)
        except OSError:
            pass


def merge_mi_ext(donor_mi_ext: Path, out_sys_root: Path, out_sys_ext: Path, out_prod: Path, log: list[str]) -> None:
    if not donor_mi_ext.is_dir():
        log.append("mi_ext: brak partycji mi_ext u donora (pomijam)")
        return

    merged = 0
    mapping = [
        (donor_mi_ext / "product", out_prod),
        (donor_mi_ext / "system", out_sys_root),
        (donor_mi_ext / "system_ext", out_sys_ext),
    ]
    for src_sub, dst_sub in mapping:
        if src_sub.is_dir():
            for item in src_sub.iterdir():
                cp_preserve(item, dst_sub / item.name)
                merged += 1

    # Top-level app/priv-app/etc/overlay/framework/media in mi_ext -> product
    for sub_name in ("app", "priv-app", "overlay", "framework", "media", "fonts", "permissions"):
        s = donor_mi_ext / sub_name
        if s.is_dir():
            cp_preserve(s, out_prod / sub_name)
            merged += 1

    mi_etc = donor_mi_ext / "etc"
    if mi_etc.is_dir():
        for item in mi_etc.iterdir():
            if item.name == "build.prop":
                mi_props = read_props(item)
                prod_prop = out_prod / "etc" / "build.prop"
                if prod_prop.is_file() and mi_props:
                    existing = read_props(prod_prop)
                    to_add = {k: v for k, v in mi_props.items() if k not in existing}
                    if to_add:
                        patch_prop_file(prod_prop, to_add)
                        log.append(f"mi_ext: scalono {len(to_add)} props do product/etc/build.prop")
                continue
            cp_preserve(item, out_prod / "etc" / item.name)
            merged += 1

    log.append(f"mi_ext: scalono {merged} elementow do product/system_ext/system (fstab blossom nie montuje /mi_ext)")


def detect_comms_apps(roots: list[Path]) -> dict[str, bool]:
    names: set[str] = set()
    for r in roots:
        for sub in ("app", "priv-app"):
            d = r / sub
            if d.is_dir():
                for child in d.iterdir():
                    names.add(child.name.lower())
    return {
        "has_miui_dialer": any(k in names for k in ("incallui", "miuidialer", "contacts")),
        "has_google_dialer": any("dialer" in k and "google" in k for k in names),
        "has_miui_mms": "mms" in names or "miuisms" in names,
        "has_google_mms": any(k in names for k in ("prebuiltbugle", "messages")),
        "has_miui_camera": any(k in names for k in ("miuicamera", "camera")),
        "has_miui_gallery": any(k in names for k in ("miuigallery", "gallery")),
        "has_gboard": any("latinimegoogle" in k or "gboard" in k for k in names),
    }


def debloat_trees(
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    level: str,
    log: list[str],
) -> None:
    roots = [out_sys_root, out_sys_ext, out_prod]
    comms = detect_comms_apps(roots)
    log.append(f"comms detection: {comms}")

    # Core protected package directory names (case-insensitive exact matches)
    protected = {
        "miuisystemui",
        "systemui",
        "miuihome",
        "settings",
        "miuisettings",
        "securitycenter",
        "powerkeeper",
        "packageinstaller",
        "miuiPackageInstaller".lower(),
        "permissioncontroller",
        "documentsui",
        "externalstorageprovider",
        "downloadprovider",
        "downloadproviderui",
        "webview",
        "webviewgoogle",
        "trichromelibrary",
        "prebuiltgmscore",
        "gmscore",
        "phonesky",
        "googleservicesframework",
        "googleloginservice",
        "googleonetimerinitializer",
        "setupwizard",
        "provision",
        "telephony",
        "telecom",
        "telephoneservice",
        "incallui",
        "contacts",
        "mms",
        "miuisms",
        "deskclock",
        "calculator",
        "miuiCalculator".lower(),
        "fileexplorer",
        "miuiFileExplorer".lower(),
        "camera",
        "miuicamera",
        "aperture",
        "gallery",
        "miuigallery",
        "gboard",
        "latinime",
        "latinimegoogle",
        "wallpaperbackup",
        "wallpapercropper",
        "managedprovisioning",
        "extshared",
        "extservices",
        "framework-res",
        "miui",
        "miuisdk",
        "miuirom",
        "miuiextservices",
        "android.ext.services",
        "networkstack",
        "captiveportallogin",
        "modulemetadata",
        "carrierconfig",
        "ims",
        "qti",
        "mtk",
        "nfc",
        "nfcnci",
        "bluetooth",
        "bluetoothmidiservice",
        "theme",
        "thememanager",
        "miuiThemeManager".lower(),
        "miwallpaper",
    }

    # Exact bloat names / prefixes (lowercase)
    bloat_exact = {
        "msa",
        "msaglobal",
        "analyticscore",
        "miuidaemon",
        "systemdaemon",
        "joyose",
        "gamecenter",
        "gamecenterglobal",
        "mibrowser",
        "mibrowserglobal",
        "mintbrowser",
        "mivideo",
        "mivideoglobal",
        "video",
        "music",
        "musicfx",
        "mipicks",
        "getapps",
        "hybridplatform",
        "quickapps",
        "yellowpage",
        "cloudservice",
        "cloudservicesysbase",
        "cloudbackup",
        "micloudsync",
        "mishare",
        "miconnectservice",
        "micast",
        "carwith",
        "smarthome",
        "soterservice",
        "paymentservice",
        "mipay",
        "fidoclient",
        "fidocrypto",
        "catchlog",
        "bugreport",
        "mibugreport",
        "feedback",
        "mifeedback",
        "health",
        "mihealth",
        "micoin",
        "mimover",
        "partnerbookmarksprovider",
        "bookmarkprovider",
        "voicetrigger",
        "aonservice",
        "aiasstvision",
        "aiengine",
        "hyperai",
        "miuiaiasst",
        "miuiaon",
        "migallerylockscreen",
        "wallpaper",
        "livewallpapers",
        "livewallpaperspicker",
        "magicsky",
        "velvet",
        "chrome",
        "youtube",
        "ytmusic",
        "youtubemusic",
        "gmail2",
        "prebuiltgmail",
        "maps",
        "drive",
        "photos",
        "meet",
        "duo",
        "videos",
        "googletts",
        "talkback",
        "androidauto",
        "projection",
        "wellbeing",
        "digitalwellbeing",
        "turbo",
        "ambientsenseprebuilt",
        "basicdreams",
        "phototable",
        "printspooler",
        "builtInPrintService".lower(),
        "playgames",
        "googleplaygames",
        "books",
        "newsstand",
        "playmovies",
        "keep",
        "lens",
        "filesgoogle",
        "filesbygoogle",
        "wps",
        "facebook",
        "tiktok",
        "spotify",
        "opera",
        "booking",
        "amazon",
        "linkedin",
        "netflix",
        "agoda",
        "globalfashion",
        "midrive",
        "midrop",
        "compass",
        "notes",
        "screenrecorder",
        "scanner",
        "weather",
        "weatherprovider",
        "calendar",
        "calendargoogle",
        "soundrecorder",
        "fm",
    }

    if level == "balanced":
        # Keep a few lightweight daily tools in balanced mode
        bloat_exact -= {"notes", "weather", "weatherprovider", "calendar", "soundrecorder", "screenrecorder"}

    # Only remove Google Dialer/Messages if MIUI equivalents exist
    if comms["has_miui_dialer"]:
        bloat_exact.add("googledialer")
    if comms["has_miui_mms"]:
        bloat_exact.update({"prebuiltbugle", "messages"})

    bloat_prefixes = (
        "com.facebook.",
        "com.zhiliaoapp.",
        "com.ss.android.",
        "com.booking",
        "com.amazon.",
        "com.spotify.",
        "com.opera.",
        "com.netflix.",
        "cn.wps.",
        "com.miui.analytics",
        "com.miui.msa",
        "com.miui.daemon",
        "com.xiaomi.joyose",
        "com.xiaomi.mipicks",
        "com.xiaomi.glgm",
        "com.xiaomi.payment",
        "com.mipay.",
        "com.mi.globalbrowser",
        "com.miui.video",
        "com.miui.player",
        "com.miui.hybrid",
        "com.xiaomi.aon",
        "com.xiaomi.aiasst",
        "com.google.android.apps.youtube",
        "com.google.android.apps.maps",
        "com.google.android.apps.docs",
        "com.google.android.apps.photos",
        "com.google.android.gm",
        "com.google.android.apps.tachyon",
        "com.google.android.projection",
        "com.google.android.googlequicksearchbox",
        "com.android.chrome",
        "com.google.android.apps.wellbeing",
    )

    removed_count = 0
    freed_bytes = 0

    for root in roots:
        # 1. Whole preload / data-app bloat directories (safe 3rd-party / preinstall folders)
        for bloat_dir_name in ("data-app", "preload", "preinstall", "cust"):
            bd = root / bloat_dir_name
            if bd.is_dir():
                sz = dir_size_bytes(bd)
                shutil.rmtree(bd)
                freed_bytes += sz
                removed_count += 1
                log.append(f"debloat dir: {bd} ({sz // (1024 * 1024)} MiB)")

        # 2. Heavy app/priv-app packages
        for sub in ("app", "priv-app"):
            app_dir = root / sub
            if not app_dir.is_dir():
                continue
            for pkg_dir in sorted(app_dir.iterdir()):
                if not pkg_dir.is_dir():
                    continue
                low = pkg_dir.name.lower()
                if low in protected:
                    continue
                hit = (low in bloat_exact) or any(low.startswith(p) for p in bloat_prefixes)
                if not hit:
                    # Also catch *Wallpaper* videos/live packs, *Game*, *Analytics*, *Msa*, *AiEngine*
                    if any(tok in low for tok in ("analytic", "joyose", "msa", "gamecenter", "mivideo", "mibrowser", "getapps", "mipay", "carwith", "aonservice", "hyperai")):
                        hit = True
                if hit:
                    sz = dir_size_bytes(pkg_dir)
                    shutil.rmtree(pkg_dir)
                    freed_bytes += sz
                    removed_count += 1
                    log.append(f"debloat pkg: {pkg_dir.relative_to(root.parent)} ({sz // (1024 * 1024)} MiB)")

        # 3. Heavy media & voice bloat
        for rel_rm in (
            "media/video",
            "media/wallpaper",
            "media/theme/miui_mod_icons",
            "etc/recovery-resource.dat",
        ):
            p = root / rel_rm
            if p.exists():
                sz = dir_size_bytes(p) if p.is_dir() else p.stat().st_size
                if p.is_dir():
                    shutil.rmtree(p)
                else:
                    p.unlink()
                freed_bytes += sz
                removed_count += 1
                log.append(f"debloat media: {p} ({sz // (1024 * 1024)} MiB)")

        # Strip huge boot audio (> 1 MiB) if present
        ba = root / "media" / "bootaudio.mp3"
        if ba.is_file():
            sz = ba.stat().st_size
            ba.unlink()
            freed_bytes += sz

        # Remove huge TTS voice packs (> 5 MiB)
        tts_dir = root / "tts"
        if tts_dir.is_dir():
            sz = dir_size_bytes(tts_dir)
            shutil.rmtree(tts_dir)
            freed_bytes += sz
            log.append(f"debloat tts: {tts_dir} ({sz // (1024 * 1024)} MiB)")

    log.append(f"DEBLOAT SUMMARY: removed {removed_count} items, freed ~{freed_bytes // (1024 * 1024)} MiB")


def adapt_blossom_hardware(
    base_dir: Path,
    out_dir: Path,
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    log: list[str],
) -> None:
    base_sys_root = resolve_sys_root(base_dir / "system")
    base_sys_ext = base_dir / "system_ext"
    base_prod = base_dir / "product"

    # 1. Hardware variant properties (/etc/properties/*.prop) for angelica/angelican/blossom
    for src_p, dst_p in (
        (base_sys_root / "etc" / "properties", out_sys_root / "etc" / "properties"),
        (base_sys_ext / "etc" / "properties", out_sys_ext / "etc" / "properties"),
        (base_prod / "etc" / "properties", out_prod / "etc" / "properties"),
    ):
        if src_p.is_dir():
            cp_preserve(src_p, dst_p)
            log.append(f"blossom properties copied: {src_p.name} -> {dst_p}")

    # 2. Missing VNDK / v3x / MTK compatibility libs in system & system_ext
    for src_lib, dst_lib in (
        (base_sys_root / "lib", out_sys_root / "lib"),
        (base_sys_root / "lib64", out_sys_root / "lib64"),
        (base_sys_ext / "lib", out_sys_ext / "lib"),
        (base_sys_ext / "lib64", out_sys_ext / "lib64"),
    ):
        copied = copy_missing_from_dir(src_lib, dst_lib, "*-v*.so")
        copied += copy_missing_from_dir(src_lib, dst_lib, "*mtk*.so")
        copied += copy_missing_from_dir(src_lib, dst_lib, "*mediatek*.so")
        if copied:
            log.append(f"copied {len(copied)} compat libs -> {dst_lib}: {', '.join(copied[:8])}")

    # 3. Missing VNDK APEXs
    vndk_copied = copy_missing_from_dir(
        base_sys_ext / "apex", out_sys_ext / "apex", "com.android.vndk*"
    )
    if vndk_copied:
        log.append(f"copied VNDK apex: {', '.join(vndk_copied)}")

    # 4. VINTF compatibility matrices from blossom base (critical for MTK HALs)
    for src_v, dst_v in (
        (base_sys_ext / "etc" / "vintf", out_sys_ext / "etc" / "vintf"),
        (base_sys_root / "etc" / "vintf", out_sys_root / "etc" / "vintf"),
    ):
        if src_v.is_dir():
            dst_v.mkdir(parents=True, exist_ok=True)
            for xml in sorted(src_v.glob("*.xml")):
                target = dst_v / xml.name
                if "compatibility_matrix" in xml.name:
                    # Prefer keeping blossom's device compatibility matrix alongside HyperOS framework matrix
                    if not target.exists():
                        cp_preserve(xml, target)
                        log.append(f"vintf added: {target}")
                    elif xml.name == "compatibility_matrix.device.xml":
                        cp_preserve(xml, target)
                        log.append(f"vintf replaced device matrix: {target}")
                elif not target.exists():
                    cp_preserve(xml, target)
                    log.append(f"vintf added: {target}")

    # Ensure vendor VNDK version is declared in system_ext/etc/vintf/manifest.xml
    vendor_props = read_props(out_dir / "vendor" / "build.prop")
    vndk_ver = vendor_props.get("ro.vndk.version", "")
    sys_ext_manifest = out_sys_ext / "etc" / "vintf" / "manifest.xml"
    if vndk_ver and sys_ext_manifest.is_file():
        mtxt = sys_ext_manifest.read_text(encoding="utf-8", errors="replace")
        if f"<version>{vndk_ver}</version>" not in mtxt and "</manifest>" in mtxt:
            mtxt = mtxt.replace(
                "</manifest>",
                f"    <vendor-ndk>\n        <version>{vndk_ver}</version>\n    </vendor-ndk>\n</manifest>",
            )
            sys_ext_manifest.write_text(mtxt, encoding="utf-8")
            log.append(f"vintf: added <vendor-ndk>{vndk_ver}</vendor-ndk> to system_ext manifest.xml")

    # 5. SELinux CIL mapping check/fallback from base
    plat_vers_file = out_dir / "vendor" / "etc" / "selinux" / "plat_sepolicy_vers.txt"
    if plat_vers_file.is_file():
        vers = plat_vers_file.read_text(encoding="utf-8", errors="replace").strip()
        log.append(f"vendor plat_sepolicy_vers={vers}")
        for rel_map in ("etc/selinux/mapping",):
            for base_r, out_r in ((base_sys_ext, out_sys_ext), (base_sys_root, out_sys_root)):
                src_m = base_r / rel_map
                dst_m = out_r / rel_map
                if src_m.is_dir():
                    added = copy_missing_from_dir(src_m, dst_m, "*.cil")
                    if added:
                        log.append(f"selinux mapping copied to {dst_m}: {', '.join(added)}")

    # 6. Blossom hardware RRO overlays (display cutout, wifi, carrier, telephony, framework-res)
    for ov_dir in (base_prod / "overlay", base_dir / "vendor" / "overlay"):
        if ov_dir.is_dir():
            for item in sorted(ov_dir.iterdir()):
                low = item.name.lower()
                if "blossom" in low and "systemui" not in low:
                    cp_preserve(item, out_prod / "overlay" / item.name)
                    log.append(f"RRO overlay copied: {item.name}")

    # 7. Device features XML adaptation (dew -> angelica / angelican / blossom, 60Hz phone)
    df_dir = out_prod / "etc" / "device_features"
    if df_dir.is_dir():
        xmls = sorted(df_dir.glob("*.xml"))
        if xmls:
            src_xml = xmls[0]
            txt = src_xml.read_text(encoding="utf-8", errors="replace")
            # Adapt refresh rate / blur / phone-class tweaks safely
            txt = re.sub(
                r'(<integer-array name="fpsList">).*?(</integer-array>)',
                r'\1\n        <item>60</item>\n    \2',
                txt,
                flags=re.S,
            )
            txt = re.sub(
                r'<integer name="support_screen_refresh_rate">.*?</integer>',
                '<integer name="support_screen_refresh_rate">60</integer>',
                txt,
            )
            txt = re.sub(
                r'<bool name="support_ir">true</bool>',
                '<bool name="support_ir">false</bool>',
                txt,
            )
            txt = re.sub(
                r'<bool name="is_pad">true</bool>',
                '<bool name="is_pad">false</bool>',
                txt,
            )
            for codename in ("angelica", "angelican", "dandelion", "cattail", "angelicain", "blossom"):
                (df_dir / f"{codename}.xml").write_text(txt, encoding="utf-8")
            log.append(f"device_features adapted from {src_xml.name} -> angelica/angelican/blossom (60Hz)")


def configure_props_and_zygote(
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    variant: str,
    log: list[str],
) -> None:
    has_32 = (out_sys_root / "bin" / "app_process32").exists()
    has_64 = (out_sys_root / "bin" / "app_process64").exists()
    hw_init = out_sys_root / "etc" / "init" / "hw"
    has_z64_32 = (hw_init / "init.zygote64_32.rc").is_file()
    has_z64 = (hw_init / "init.zygote64.rc").is_file()

    if has_64 and has_32 and has_z64_32:
        zygote_mode = "zygote64_32"
    elif has_64 and has_z64:
        zygote_mode = "zygote64"
    else:
        zygote_mode = "zygote64_32" if has_32 else "zygote64"
    log.append(f"zygote check: app_process64={has_64}, app_process32={has_32}, selected={zygote_mode}")

    if variant == "angelican":
        model, market, dev = "M2006C3MNG", "Redmi 9C NFC", "angelican"
    else:
        model, market, dev = "M2006C3MG", "Redmi 9C", "angelica"

    common_updates = {
        "ro.zygote": zygote_mode,
        "ro.sf.lcd_density": "320",
        "ro.mi.os.version.name": "OS4.0.8.0.XBNMIXM",
        "ro.build.display.id": "HyperOS 4.0.8.0 Debloated (Redmi 9C)",
        "persist.sys.background_blur_supported": "false",
        "ro.surface_flinger.supports_background_blur": "0",
        "persist.sys.miui.blur.level": "0",
        "persist.arm64.memtag.system_server": "off",
        "ro.lmk.use_psi": "true",
        "ro.lmk.kill_heaviest_task": "true",
        "ro.lmk.psi_partial_stall_ms": "70",
        "ro.lmk.psi_complete_stall_ms": "700",
        "ro.debuggable": "1",
        "ro.adb.secure": "0",
        "persist.sys.usb.config": "mtp,adb",
        "persist.service.adb.enable": "1",
        "ro.product.system.device": dev,
        "ro.product.system.model": model,
        "ro.product.system.marketname": market,
        "ro.product.product.device": dev,
        "ro.product.product.model": model,
        "ro.product.product.marketname": market,
        "ro.product.device": dev,
        "ro.product.model": model,
        "ro.product.marketname": market,
        "ro.product.mod_device": f"{dev}_global",
    }

    replace_pairs = [
        ("dew_global", f"{dev}_global"),
        ("Redmi 15C", market),
        ("POCO C85", market),
        ("=dew", f"={dev}"),
    ]

    for prop_path in (
        out_sys_root / "build.prop",
        out_sys_ext / "etc" / "build.prop",
        out_prod / "etc" / "build.prop",
    ):
        extra = ["import /system/etc/properties/${ro.boot.hwname}.prop"] if prop_path == (out_sys_root / "build.prop") else []
        patch_prop_file(prop_path, common_updates, append_lines=extra, replace_pairs=replace_pairs)
        log.append(f"patched props: {prop_path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-tree", required=True, help="Extracted blossom OSS A17 tree (system, system_ext, product, vendor, odm)")
    ap.add_argument("--donor-tree", required=True, help="Extracted HyperOS 4 donor tree (system, system_ext, product, [mi_ext])")
    ap.add_argument("--out-tree", required=True, help="Output assembled trees dir")
    ap.add_argument("--variant", default="angelica", choices=["angelica", "angelican"])
    ap.add_argument("--debloat-level", default="aggressive", choices=["aggressive", "balanced"])
    ap.add_argument("--report", required=True, help="Write build/debloat report path")
    args = ap.parse_args()

    base = Path(args.base_tree)
    donor = Path(args.donor_tree)
    out = Path(args.out_tree)
    log: list[str] = []

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    # Copy OS partitions from HyperOS 4 donor, hardware partitions from blossom OSS base
    for part in ("system", "system_ext", "product"):
        src = donor / part
        if not src.is_dir():
            raise FileNotFoundError(f"Missing donor partition tree: {src}")
        log.append(f"copy donor {part} -> {out / part}")
        cp_preserve(src, out / part)

    for part in ("vendor", "odm"):
        src = base / part
        if not src.is_dir():
            raise FileNotFoundError(f"Missing base hardware partition tree: {src}")
        log.append(f"copy base {part} -> {out / part}")
        cp_preserve(src, out / part)

    out_sys_root = resolve_sys_root(out / "system")
    out_sys_ext = out / "system_ext"
    out_prod = out / "product"

    merge_mi_ext(donor / "mi_ext", out_sys_root, out_sys_ext, out_prod, log)
    debloat_trees(out_sys_root, out_sys_ext, out_prod, args.debloat_level, log)
    adapt_blossom_hardware(base, out, out_sys_root, out_sys_ext, out_prod, log)
    configure_props_and_zygote(out_sys_root, out_sys_ext, out_prod, args.variant, log)

    sizes = {p: dir_size_bytes(out / p) for p in ("system", "system_ext", "product", "vendor", "odm")}
    total_mb = sum(sizes.values()) // (1024 * 1024)
    log.append("FINAL TREE SIZES (uncompressed):")
    for p, sz in sizes.items():
        log.append(f"  {p}: {sz // (1024 * 1024)} MiB ({sz} B)")
    log.append(f"  TOTAL: {total_mb} MiB")

    Path(args.report).write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
