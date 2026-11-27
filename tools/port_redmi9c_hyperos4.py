#!/usr/bin/env python3
"""Port and aggressively debloat HyperOS 4 (Android 17, Global 'dew') onto Redmi 9C ('blossom' OSS A17 base).

Preserves Linux modes, symlinks, ownership, and security.selinux xattrs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Iterable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mysticalos_brand


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


def top_space_hogs(roots: list[tuple[str, Path]], top_n: int = 45) -> list[str]:
    entries: list[tuple[int, str]] = []
    for label, r in roots:
        if not r.is_dir():
            continue
        for child in r.iterdir():
            if child.is_symlink():
                continue
            if child.is_dir():
                if child.name in ("app", "priv-app", "apex", "media", "pangu", "data-app", "preload", "preinstall", "overlay", "etc"):
                    for sub in child.iterdir():
                        if sub.is_symlink():
                            continue
                        if child.name == "pangu" and sub.is_dir():
                            for psub in sub.iterdir():
                                if psub.is_dir() and psub.name in ("app", "priv-app", "data-app"):
                                    for pkg in psub.iterdir():
                                        sz = dir_size_bytes(pkg) if pkg.is_dir() else pkg.stat().st_size
                                        entries.append((sz, f"{label}/pangu/{sub.name}/{psub.name}/{pkg.name}"))
                                else:
                                    sz = dir_size_bytes(psub) if psub.is_dir() else psub.stat().st_size
                                    entries.append((sz, f"{label}/pangu/{sub.name}/{psub.name}"))
                        else:
                            sz = dir_size_bytes(sub) if sub.is_dir() else sub.stat().st_size
                            entries.append((sz, f"{label}/{child.name}/{sub.name}"))
                    continue
                entries.append((dir_size_bytes(child), f"{label}/{child.name}"))
            else:
                try:
                    entries.append((child.stat().st_size, f"{label}/{child.name}"))
                except OSError:
                    pass
    entries.sort(reverse=True)
    return [
        f"  {sz // (1024 * 1024):4d} MiB  {name}"
        for sz, name in entries[:top_n]
        if sz >= 5 * 1024 * 1024
    ]


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
        "has_miui_dialer": any(k in names for k in ("incallui", "miuidialer", "contacts", "hyperphone")),
        "has_google_dialer": any("dialer" in k and "google" in k for k in names),
        "has_miui_mms": any(n in ("mms", "miuisms") or ("mms" in n and "miui" in n) for n in names),
        "has_google_mms": any(n in ("prebuiltbugle", "messages") or n.startswith("messages_") for n in names),
        "has_miui_camera": any(k in names for k in ("miuicamera", "camera")),
        "has_miui_gallery": any("miuigallery" in k or k == "gallery" for k in names),
        "has_gboard": any("latinimegoogle" in k or "gboard" in k for k in names),
    }


def debloat_trees(
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    level: str,
    gms_mode: str,
    log: list[str],
    remove_xiaomi_apps: bool = True,
) -> tuple[list[str], int]:
    roots = [out_sys_root, out_sys_ext, out_prod]
    comms = detect_comms_apps(roots)
    log.append(f"comms detection: {comms}, gms_mode={gms_mode}, remove_xiaomi_apps={remove_xiaomi_apps}")

    # Core protected package directory names (case-insensitive exact matches)
    # Keep ONLY boot/HAL/framework/SystemUI/Settings/Telephony essentials; user-facing Xiaomi apps are removed when remove_xiaomi_apps=True.
    protected = {
        "miuisystemui",
        "miuisystemuiplugin",
        "systemui",
        "settings",
        "powerkeeper",
        "packageinstaller",
        "miuipackageinstaller",
        "permissioncontroller",
        "documentsui",
        "externalstorageprovider",
        "downloadprovider",
        "webview",
        "provision",
        "telephony",
        "telecom",
        "telephoneservice",
        "mtkteleservice",
        "latinime",
        "wallpaperbackup",
        "wallpapercropper",
        "managedprovisioning",
        "extshared",
        "extservices",
        "framework-res",
        "miui",
        "miuisdk",
        "miuirom",
        "miuisystem",
        "miuix",
        "miuiwmshellresources-install",
        "miuiaudiomonitor",
        "misound",
        "miuisound",
        "miuiextservices",
        "miuibiometric",
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
        "bluetoothextension",
        "mysticallauncher",
    }
    if not remove_xiaomi_apps:
        protected.update({
            "miuihome",
            "miuisettings",
            "securitycenter",
            "miuisecuritycenterglobal",
            "downloadproviderui",
            "incallui",
            "hyperphone",
            "contacts",
            "mms",
            "miuisms",
            "miuimmsglobal",
            "deskclock",
            "calculator",
            "miuicalculator",
            "fileexplorer",
            "miuifileexplorer",
            "camera",
            "miuicamera",
            "aperture",
            "gallery",
            "miuigallery",
            "miuigalleryglobal",
            "theme",
            "thememanager",
            "miuithememanager",
            "miuithememanagerglobal",
            "miwallpaper",
        })
    if gms_mode == "keep":
        protected.update({
            "webviewgoogle",
            "webviewgoogle64",
            "trichromelibrary",
            "trichromelibrary64",
            "prebuiltgmscore",
            "gmscore",
            "phonesky",
            "googleservicesframework",
            "googleloginservice",
            "googleonetimerinitializer",
            "setupwizard",
            "gboard",
            "latinimegoogle",
        })

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
        "facebook-appmanager",
        "facebook-installer",
        "facebook-services",
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

    # Expand bloat names for HyperOS 4 Global (Android 17)
    bloat_exact.update({
        "chrome64",
        "trichromechrome",
        "trichromechrome6432",
        "trichromechromelib",
        "velvetcts",
        "speechservicesbygoogle",
        "personalsafety",
        "safetyhub",
        "androidautostub",
        "devicehealthservices",
        "androidsystemintelligence_features_arm64",
        "privatecomputeservices_arm64",
        "googleone",
        "docs",
        "sheets",
        "slides",
        "familylink",
        "familylinkparentalcontrols",
        "parentalcontrols",
        "googleone_arm64",
        "googlefeedback",
        "googlepartnersetup",
        "pixelbuds",
        "androidswitch",
        "migrateprebuilt",
        "restore",
        "datarestore",
        "hotwordenrollment",
        "hotwordenrollmentokgoogle",
        "hotwordenrollmentxgoogle",
        "googlelocationhistory",
        "playautoinstallconfig",
        "switchaccess",
        "soundamplifier",
        "livetranscribe",
        "miuiupdater",
        "updater",
        "systemupdater",
        "otaservice",
        "miuinotes",
        "miuiweather",
        "miuiscanner",
        "miuicompass",
        "miuiscreenrecorder",
        "miuisoundrecorder",
        "miuiradio",
        "miuimivideo",
        "miuivideoplayer",
        "miuiplayer",
        "miuimimusic",
        "miuimusicglobal",
        "miuigamecenter",
        "miuimipicks",
        "mediaviewerglobal",
        "miuiextraphoto",
        "miuiaicr",
        "miuicleanmasterglobal-cleaner",
        "milauncherglobal",
        "miuicontentextension",
        "contentextension",
        "miuiaiasst",
        "translationservice",
        "miuitranslation",
        "galleryeditor",
        "mediaeditor",
        "micloud",
        "milink",
        "milinkservice",
        "miplayclient",
        "mijia",
        "modemtestbox",
        "logkit",
        "wallet",
        "mipaywallet",
        "miuiaod",
        "miuisuperwallpaper",
        "superwallpaper",
        "superwallpapermars",
        "superwallpaperearth",
        "superwallpapersnow",
        "superwallpapersaturn",
        "superwallpapergeometry",
        "superwallpapermoon",
        "miuiemail",
        "email",
        "thirdappassistant",
        "mibrowserglobal_builtin_before_2021",
        "appfinder",
        "voiceunlock",
        "miuisecurityadd",
        "mibugreportos4global",
        "mi_connect_service",
    })

    # Detect WebView packages so we NEVER remove TrichromeLibrary if TrichromeWebView depends on it (when keeping GMS)
    pkg_names_lower: set[str] = set()
    scan_roots: list[Path] = []
    for r in roots:
        scan_roots.append(r)
        for psub in (r / "pangu", r / "pangu" / "system"):
            if psub.is_dir():
                scan_roots.append(psub)

    for sr in scan_roots:
        for sub in ("app", "priv-app"):
            ad = sr / sub
            if ad.is_dir():
                for pd in ad.iterdir():
                    if pd.is_dir():
                        pkg_names_lower.add(pd.name.lower())

    if gms_mode == "keep":
        has_trichrome_webview = any("trichromewebview" in n for n in pkg_names_lower)
        if has_trichrome_webview:
            protected.update({n for n in pkg_names_lower if "trichromelibrary" in n or "trichromewebview" in n})
        else:
            if any(n in pkg_names_lower for n in ("webviewgoogle", "androidsystemwebview", "webview")):
                bloat_exact.update({"trichromelibrary", "trichromelibrary6432", "trichromelibrary64"})
    else:
        # Full de-Googling for microG / vanilla FOSS mode
        bloat_exact.update({
            "prebuiltgmscore",
            "gmscore",
            "phonesky",
            "googleservicesframework",
            "googleloginservice",
            "googleonetimerinitializer",
            "googlebackupadapter",
            "googlebackuptransport",
            "googlecontactssyncadapter",
            "googlecalendarsyncadapter",
            "googlerestore",
            "setupwizard",
            "setupwizardprebuilt",
            "webviewgoogle",
            "webviewgoogle64",
            "trichromewebview",
            "trichromewebview64",
            "trichromelibrary",
            "trichromelibrary64",
            "trichromelibrary6432",
            "gboard",
            "latinimegoogle",
            "latinimegoogleprebuilt",
        })

    if level == "balanced":
        # Keep a few lightweight daily tools in balanced mode
        bloat_exact -= {"notes", "miuinotes", "weather", "miuiweather", "weatherprovider", "calendar", "soundrecorder", "miuisoundrecorder", "screenrecorder", "miuiscreenrecorder"}

    # Remove Google Dialer/Messages when replacing with MIUI or FOSS equivalents
    if comms["has_miui_dialer"] or remove_xiaomi_apps:
        bloat_exact.update({"googledialer", "googledialer_arm64"})
    if comms["has_miui_mms"] or remove_xiaomi_apps:
        bloat_exact.update({"prebuiltbugle", "messages", "messages_arm64_hdpi"})

    if remove_xiaomi_apps:
        bloat_exact.update({
            "miuihome",
            "miuicamera",
            "camera",
            "aperture",
            "miuigallery",
            "miuigalleryglobal",
            "gallery",
            "miuithememanager",
            "miuithememanagerglobal",
            "thememanager",
            "miuixiaomiaccountglobal",
            "xiaomiaccount",
            "account",
            "miuicloudserviceglobal",
            "cloudservice",
            "cloudbackup",
            "miuifileexplorerglobal",
            "miuifileexplorer",
            "fileexplorer",
            "miexplorer",
            "miuimmsglobal",
            "mms",
            "miuisms",
            "hyperphone",
            "miuidialer",
            "incallui",
            "contacts",
            "googlecontacts",
            "miuisecuritycenterglobal",
            "securitycenter",
            "securitycoreadd",
            "misettings",
            "backup",
            "miuibackup",
            "deskclock",
            "miuideskclock",
            "miuiclock",
            "clock",
            "calculator",
            "miuicalculator",
            "exactcalculator",
            "downloadproviderui",
            "miwallpaper",
            "finddevice",
            "miuifrequentphrase",
            "cit",
            "miuiaccessibility",
            "miuiaccessibilityglobal",
            "miuiaod",
            "miuisuperwallpaper",
            "miservice",
            "miserviceglobal",
            "aiservice",
            "mishareglobal",
            "hypergallerypluginglobal",
            "tiktoksubpkg",
            "bard",
            "gemini",
            "fm",
            "fmradio",
            "fm_global",
        })

    bloat_prefixes = [
        "com.facebook.",
        "com.zhiliaoapp.",
        "com.ss.android.",
        "tiktok",
        "com.booking",
        "com.amazon.",
        "com.spotify.",
        "com.opera.",
        "com.netflix.",
        "cn.wps.",
        "com.miui.analytics",
        "com.miui.msa",
        "com.miui.daemon",
        "com.miui.miservice",
        "com.miui.fm",
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
        "com.google.android.apps.bard",
        "com.google.android.gm",
        "com.google.android.apps.tachyon",
        "com.google.android.projection",
        "com.google.android.googlequicksearchbox",
        "com.android.chrome",
        "com.google.android.apps.wellbeing",
        "com.google.android.tts",
        "com.google.android.apps.safetyhub",
        "bard",
        "gemini",
        "miservice",
        "aiservice",
        "mishare",
        "hypergallery",
        "superwallpaper",
        "miuisuperwallpaper",
        "trichromechrome",
        "hotwordenrollment",
        "velvet",
        "androidsystemintelligence",
        "privatecomputeservices",
        "miuicleanmaster",
        "miuiextraphoto",
        "miuiaicr",
        "miuimusic",
        "miuivideo",
        "miuimipicks",
    ]
    if gms_mode != "keep":
        bloat_prefixes.extend([
            "com.google.android.gms",
            "com.android.vending",
            "com.google.android.gsf",
            "com.google.android.setupwizard",
            "com.google.android.webview",
            "com.google.android.trichromelibrary",
            "com.google.android.inputmethod.latin",
            "com.google.android.apps.restore",
            "webviewgoogle",
            "trichrome",
            "messages_arm64",
        ])
    bloat_prefixes_t = tuple(bloat_prefixes)

    removed_count = 0
    removed_items: list[str] = []
    freed_bytes = 0

    for root in scan_roots:
        # 1. Whole preload / data-app bloat directories (safe 3rd-party / preinstall folders)
        for bloat_dir_name in ("data-app", "preload", "preinstall", "cust", "ai"):
            bd = root / bloat_dir_name
            if bd.is_dir():
                sz = dir_size_bytes(bd)
                shutil.rmtree(bd)
                freed_bytes += sz
                removed_count += 1
                removed_items.append(bloat_dir_name)
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
                hit = (low in bloat_exact) or any(low.startswith(p) for p in bloat_prefixes_t)
                if not hit and remove_xiaomi_apps and (low.startswith("miui") or low.startswith("xiaomi") or low.startswith("mi_")):
                    if not any(keep_tok in low for keep_tok in (
                        "framework", "core", "telephony", "telecom", "wifi", "bluetooth",
                        "nfc", "biometric", "provision", "sdk", "systemui", "overlay",
                        "rro", "extservices", "config", "location", "powerkeeper",
                    )):
                        hit = True
                if not hit and comms["has_miui_dialer"] and low.startswith("googledialer"):
                    hit = True
                if not hit:
                    if any(tok in low for tok in ("analytic", "joyose", "msa", "gamecenter", "mivideo", "mibrowser", "getapps", "mipay", "carwith", "aonservice", "hyperai", "superwallpaper", "speechservices", "galleryeditor", "mediaeditor", "micloud", "milink")):
                        hit = True
                if hit:
                    sz = dir_size_bytes(pkg_dir)
                    shutil.rmtree(pkg_dir)
                    freed_bytes += sz
                    removed_count += 1
                    removed_items.append(pkg_dir.name)
                    log.append(f"debloat pkg: {pkg_dir.relative_to(root.parent)} ({sz // (1024 * 1024)} MiB)")

        # 2b. Google GMS Mainline APEX (only remove in non-keep mode if verified not core AOSP extservices/permission)
        if gms_mode != "keep":
            apex_dir = root / "apex"
            if apex_dir.is_dir():
                for apx in sorted(apex_dir.glob("com.google.android.gmssystem*")):
                    safe_rm = True
                    if apx.is_file() and apx.suffix == ".apex":
                        try:
                            with zipfile.ZipFile(apx, "r") as zf:
                                mf = zf.read("apex_manifest.pb") if "apex_manifest.pb" in zf.namelist() else b""
                                if b"permission" in mf.lower() or b"extservices" in mf.lower():
                                    safe_rm = False
                        except Exception:
                            pass
                    if safe_rm and apx.exists():
                        sz = dir_size_bytes(apx) if apx.is_dir() else apx.stat().st_size
                        if apx.is_dir():
                            shutil.rmtree(apx)
                        else:
                            apx.unlink()
                        freed_bytes += sz
                        removed_count += 1
                        log.append(f"debloat apex: {apx.name} ({sz // (1024 * 1024)} MiB)")

        # 3. Heavy media & voice bloat
        for rel_rm in (
            "media/video",
            "media/wallpaper",
            "media/theme/miui_mod_icons",
            "etc/precust_theme",
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
    return removed_items, freed_bytes


def find_pkg_dir(root_tree: Path, names: tuple[str, ...]) -> Path | None:
    low_set = {n.lower() for n in names}
    for sub in ("app", "priv-app"):
        d = root_tree / sub
        if d.is_dir():
            for child in d.iterdir():
                if child.is_dir() and child.name.lower() in low_set:
                    return child
    return None


def trim_to_budget(
    base_dir: Path,
    out_dir: Path,
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    target_os_mib: int,
    log: list[str],
) -> None:
    if target_os_mib <= 0:
        return

    def os_mib() -> int:
        return (dir_size_bytes(out_dir / "system") + dir_size_bytes(out_sys_ext) + dir_size_bytes(out_prod)) // (1024 * 1024)

    cur = os_mib()
    if cur <= target_os_mib:
        log.append(f"budget check: OS={cur} MiB <= {target_os_mib} MiB (OK)")
        return

    log.append(f"budget check: OS={cur} MiB > {target_os_mib} MiB -> bezpieczne odchudzanie nadmiaru")

    # 1. Swap oversized donor MiuiCamera (> 120 MiB) with base Aperture/Camera2 if available
    base_cam = None
    for bp in (base_dir / "product", base_dir / "system_ext", resolve_sys_root(base_dir / "system")):
        base_cam = find_pkg_dir(bp, ("Aperture", "Camera2", "Snap"))
        if base_cam:
            break
    if base_cam:
        for tree in (out_prod, out_sys_ext, out_sys_root):
            dcam = find_pkg_dir(tree, ("MiuiCamera", "Camera"))
            if dcam and dir_size_bytes(dcam) > 120 * 1024 * 1024:
                sz = dir_size_bytes(dcam)
                shutil.rmtree(dcam)
                cp_preserve(base_cam, out_prod / "priv-app" / base_cam.name)
                log.append(f"budget swap camera: {dcam.name} ({sz // (1024 * 1024)} MiB) -> {base_cam.name}")
                break

    if os_mib() <= target_os_mib:
        log.append(f"budget check: po zmianie aparatu OS={os_mib()} MiB <= {target_os_mib} MiB")
        return

    # 2. Trim offline AI/OCR/srec data blobs inside product
    for rel in ("usr/srec", "etc/ai", "etc/ocr", "etc/miui_feature", "media/theme"):
        p = out_prod / rel
        if p.is_dir() and dir_size_bytes(p) > 25 * 1024 * 1024:
            sz = dir_size_bytes(p)
            shutil.rmtree(p)
            log.append(f"budget trim dir: product/{rel} ({sz // (1024 * 1024)} MiB)")
            if os_mib() <= target_os_mib:
                return

    # 3. Swap oversized Gboard (> 120 MiB) with base LatinIME if available
    base_ime = None
    for bp in (base_dir / "product", base_dir / "system_ext", resolve_sys_root(base_dir / "system")):
        base_ime = find_pkg_dir(bp, ("LatinIME",))
        if base_ime:
            break
    if base_ime:
        for tree in (out_prod, out_sys_ext, out_sys_root):
            dime = find_pkg_dir(tree, ("Gboard", "LatinIMEGoogle", "LatinIMEGooglePrebuilt"))
            if dime and dir_size_bytes(dime) > 120 * 1024 * 1024:
                sz = dir_size_bytes(dime)
                shutil.rmtree(dime)
                cp_preserve(base_ime, out_prod / "app" / base_ime.name)
                log.append(f"budget swap keyboard: {dime.name} ({sz // (1024 * 1024)} MiB) -> {base_ime.name}")
                break

    log.append(f"budget check po odchudzaniu: OS={os_mib()} MiB (limit {target_os_mib} MiB)")


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

    # 5. SELinux CIL mapping check/fallback from base + policycap alignment with blossom kernel
    base_plat_cil = base_sys_root / "etc" / "selinux" / "plat_sepolicy.cil"
    out_plat_cil = out_sys_root / "etc" / "selinux" / "plat_sepolicy.cil"
    if base_plat_cil.is_file() and out_plat_cil.is_file():
        cap_re = re.compile(r"^\(policycap\s+([^\s\)]+)\)")
        base_caps = {m.group(1) for ln in base_plat_cil.read_text(encoding="utf-8", errors="replace").splitlines() if (m := cap_re.match(ln.strip()))}
        out_lines = out_plat_cil.read_text(encoding="utf-8", errors="replace").splitlines()
        out_caps = {m.group(1) for ln in out_lines if (m := cap_re.match(ln.strip()))}
        extra_caps = sorted(out_caps - base_caps)
        log.append(f"selinux policycaps base={sorted(base_caps)} donor={sorted(out_caps)}")
        if extra_caps:
            try:
                orig_ctx = os.getxattr(out_plat_cil, "security.selinux", follow_symlinks=False)
            except OSError:
                orig_ctx = None
            filtered = [ln for ln in out_lines if not ((m := cap_re.match(ln.strip())) and m.group(1) in extra_caps)]
            out_plat_cil.write_text("\n".join(filtered) + "\n", encoding="utf-8")
            if orig_ctx:
                try:
                    os.setxattr(out_plat_cil, "security.selinux", orig_ctx, follow_symlinks=False)
                except OSError:
                    pass
            log.append(f"selinux policycaps removed unsupported by base kernel: {', '.join(extra_caps)}")

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


def install_apk_dir(apk_src: Path, dst_dir: Path, log: list[str]) -> None:
    if not apk_src.is_file():
        return
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    dst_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(dst_dir, 0o755)
    dst_apk = dst_dir / f"{dst_dir.name}.apk"
    shutil.copy2(apk_src, dst_apk)
    os.chmod(dst_apk, 0o644)

    extracted = []
    try:
        with zipfile.ZipFile(dst_apk, "r") as zf:
            for member in zf.namelist():
                if not member.endswith(".so"):
                    continue
                if member.startswith("lib/arm64-v8a/"):
                    out_so = dst_dir / "lib" / "arm64" / Path(member).name
                elif member.startswith("lib/armeabi-v7a/"):
                    out_so = dst_dir / "lib" / "arm" / Path(member).name
                else:
                    continue
                out_so.parent.mkdir(parents=True, exist_ok=True)
                os.chmod(out_so.parent, 0o755)
                if out_so.parent.parent.is_dir():
                    os.chmod(out_so.parent.parent, 0o755)
                out_so.write_bytes(zf.read(member))
                os.chmod(out_so, 0o644)
                extracted.append(str(out_so.relative_to(dst_dir)))
    except Exception as exc:
        log.append(f"warn extract libs {dst_apk.name}: {exc}")
    log.append(f"installed APK: {dst_apk.name} ({dst_apk.stat().st_size // 1024} KiB, libs={len(extracted)})")


def query_apk_permissions(apk_path: Path, aapt2_bin: str) -> list[str]:
    if not aapt2_bin or not apk_path.is_file():
        return []
    r = subprocess.run([aapt2_bin, "dump", "permissions", str(apk_path)], text=True, capture_output=True)
    if r.returncode != 0:
        return []
    perms: list[str] = []
    for line in r.stdout.splitlines():
        m = re.search(r"name='([^']+)'", line)
        if m and m.group(1) not in perms:
            perms.append(m.group(1))
    return perms


def query_apk_package(apk_path: Path, aapt2_bin: str) -> str:
    if not aapt2_bin or not apk_path.is_file():
        return ""
    r = subprocess.run([aapt2_bin, "dump", "badging", str(apk_path)], text=True, capture_output=True)
    if r.returncode != 0:
        return ""
    m = re.search(r"package:\s*name='([^']+)'", r.stdout)
    return m.group(1) if m else ""


def integrate_microg_and_foss(
    base_dir: Path,
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    extra_apps_dir: Path | None,
    apktool_jar: str,
    aapt2_bin: str,
    gms_mode: str,
    log: list[str],
) -> None:
    if gms_mode == "keep":
        return

    # 1. Inspect donor framework-res.apk WebView config before choosing OSS WebView
    donor_fw_res = out_sys_root / "framework" / "framework-res.apk"
    wv_xml_dump = ""
    if aapt2_bin and donor_fw_res.is_file():
        r = subprocess.run(
            [aapt2_bin, "dump", "xmltree", str(donor_fw_res), "--file", "res/xml/config_webview_packages.xml"],
            text=True,
            capture_output=True,
        )
        if r.returncode == 0:
            wv_xml_dump = r.stdout
            pkgs = re.findall(r'packageName[^=]*="([^"]+)"', wv_xml_dump)
            if not pkgs:
                log.append(f"donor config_webview_packages.xml raw: {' | '.join(wv_xml_dump.splitlines()[:12])}")
            else:
                log.append(f"donor config_webview_packages.xml allows: {pkgs}")

    # Check blossom base OSS WebView (usually multi-ABI com.android.webview)
    base_wv = None
    for bp in (base_dir / "product", base_dir / "system_ext", resolve_sys_root(base_dir / "system")):
        base_wv = find_pkg_dir(bp, ("webview", "AndroidSystemWebView", "WebView", "CromiteWebView"))
        if base_wv:
            break

    cromite_apk = (extra_apps_dir / "CromiteWebView.apk") if extra_apps_dir else Path("")
    base_wv_pkg = ""
    if base_wv:
        apks = list(base_wv.rglob("*.apk"))
        if apks:
            base_wv_pkg = query_apk_package(apks[0], aapt2_bin)
        log.append(f"base OSS WebView found: {base_wv.name} (package={base_wv_pkg or 'unknown'})")

    if base_wv and (not wv_xml_dump or not base_wv_pkg or base_wv_pkg in wv_xml_dump):
        dst_wv = out_prod / "app" / base_wv.name
        if dst_wv.exists():
            shutil.rmtree(dst_wv)
        cp_preserve(base_wv, dst_wv)
        log.append(f"WebView installed from base OSS ({base_wv.name}, multi-ABI safe)")
    elif cromite_apk.is_file():
        install_apk_dir(cromite_apk, out_prod / "app" / "CromiteWebView", log)
        if wv_xml_dump and "org.cromite.webview" not in wv_xml_dump:
            log.append("WARNING: org.cromite.webview nie jest wymieniony w donor config_webview_packages.xml (brak zgodnego podpisu systemowego)")
    else:
        log.append("WARNING: brak otwartozrodlowego WebView (ani base webview, ani CromiteWebView.apk)")

    # 2. Install FOSS replacement suite (Fossify + HeliBoard + Droid-ify) and optional microG
    if extra_apps_dir and extra_apps_dir.is_dir():
        foss_priv = [
            ("FossifyPhone.apk", "FossifyPhone"),
            ("FossifyMessages.apk", "FossifyMessages"),
        ]
        foss_apps = [
            ("FossifyContacts.apk", "FossifyContacts"),
            ("FossifyGallery.apk", "FossifyGallery"),
            ("FossifyFileManager.apk", "FossifyFileManager"),
            ("FossifyCamera.apk", "FossifyCamera"),
            ("FossifyClock.apk", "FossifyClock"),
            ("FossifyCalculator.apk", "FossifyCalculator"),
            ("HeliBoard.apk", "HeliBoard"),
            ("Droid-ify.apk", "Droid-ify"),
        ]
        for fname, dname in foss_priv:
            ap = extra_apps_dir / fname
            if ap.is_file():
                install_apk_dir(ap, out_prod / "priv-app" / dname, log)
        for fname, dname in foss_apps:
            ap = extra_apps_dir / fname
            if ap.is_file():
                install_apk_dir(ap, out_prod / "app" / dname, log)

        # Grant priv-app permissions for FossifyPhone / FossifyMessages if installed
        foss_priv_lines = ['<?xml version="1.0" encoding="utf-8"?>', "<permissions>"]
        has_foss_priv = False
        for fname in ("FossifyPhone.apk", "FossifyMessages.apk"):
            ap = extra_apps_dir / fname
            if not ap.is_file():
                continue
            pkg_id = query_apk_package(ap, aapt2_bin)
            if not pkg_id:
                continue
            p_list = sorted(
                {
                    "android.permission.READ_PRIVILEGED_PHONE_STATE",
                    "android.permission.MODIFY_PHONE_STATE",
                    "android.permission.CALL_PRIVILEGED",
                    "android.permission.WRITE_SECURE_SETTINGS",
                    "android.permission.SEND_SMS",
                    "android.permission.RECEIVE_SMS",
                    "android.permission.READ_SMS",
                }
                if "phone" in fname.lower()
                else {
                    "android.permission.READ_PRIVILEGED_PHONE_STATE",
                    "android.permission.SEND_SMS",
                    "android.permission.RECEIVE_SMS",
                    "android.permission.READ_SMS",
                }
            )
            p_list = sorted(set(p_list) | {p for p in query_apk_permissions(ap, aapt2_bin) if p.startswith("android.permission.")})
            foss_priv_lines.append(f'    <privapp-permissions package="{pkg_id}">')
            for p in p_list:
                foss_priv_lines.append(f'        <permission name="{p}" />')
            foss_priv_lines.append("    </privapp-permissions>")
            has_foss_priv = True
        if has_foss_priv:
            foss_priv_lines.append("</permissions>")
            perm_dir = out_prod / "etc" / "permissions"
            perm_dir.mkdir(parents=True, exist_ok=True)
            fp_xml = perm_dir / "privapp-permissions-foss.xml"
            fp_xml.write_text("\n".join(foss_priv_lines) + "\n", encoding="utf-8")
            os.chmod(fp_xml, 0o644)

    if gms_mode == "microg" and extra_apps_dir and extra_apps_dir.is_dir():
        gms_apk = extra_apps_dir / "GmsCore.apk"
        vending_apk = extra_apps_dir / "FakeStore.apk"
        gsf_apk = extra_apps_dir / "GsfProxy.apk"

        install_apk_dir(gms_apk, out_prod / "priv-app" / "GmsCore", log)
        install_apk_dir(vending_apk, out_prod / "priv-app" / "FakeStore", log)
        install_apk_dir(gsf_apk, out_prod / "priv-app" / "GsfProxy", log)

        # Build comprehensive privapp-permissions-microg.xml using aapt2 + known required priv permissions
        base_gms_priv = {
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.ACCESS_CONTEXT_HUB",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.ACCESS_WIFI_STATE",
            "android.permission.ALLOCATE_AGGRESSIVE",
            "android.permission.BATTERY_STATS",
            "android.permission.CHANGE_DEVICE_IDLE_TEMP_WHITELIST",
            "android.permission.CONNECTIVITY_USE_RESTRICTED_NETWORKS",
            "android.permission.DUMP",
            "android.permission.FAKE_PACKAGE_SIGNATURE",
            "android.permission.GET_APP_OPS_STATS",
            "android.permission.INSTALL_LOCATION_PROVIDER",
            "android.permission.INTERACT_ACROSS_USERS",
            "android.permission.LOCAL_MAC_ADDRESS",
            "android.permission.LOCATION_BYPASS",
            "android.permission.LOCATION_HARDWARE",
            "android.permission.MANAGE_USB",
            "android.permission.MODIFY_PHONE_STATE",
            "android.permission.NETWORK_BYPASS_PRIVATE_DNS",
            "android.permission.NETWORK_SCAN",
            "android.permission.OBSERVE_GRANT_REVOKE_PERMISSIONS",
            "android.permission.PACKAGE_USAGE_STATS",
            "android.permission.READ_DEVICE_CONFIG",
            "android.permission.READ_LOGS",
            "android.permission.READ_PRIVILEGED_PHONE_STATE",
            "android.permission.REAL_GET_TASKS",
            "android.permission.RECEIVE_DATA_ACTIVITY_CHANGE",
            "android.permission.START_ACTIVITIES_FROM_BACKGROUND",
            "android.permission.STATUS_BAR_SERVICE",
            "android.permission.SUBSTITUTE_NOTIFICATION_APP_NAME",
            "android.permission.SYSTEM_ALERT_WINDOW",
            "android.permission.TETHER_PRIVILEGED",
            "android.permission.UPDATE_APP_OPS_STATS",
            "android.permission.UPDATE_DEVICE_STATS",
            "android.permission.USE_BIOMETRIC",
            "android.permission.WRITE_GSERVICES",
            "android.permission.WRITE_SECURE_SETTINGS",
        }
        gms_perms = sorted(base_gms_priv | {p for p in query_apk_permissions(gms_apk, aapt2_bin) if p.startswith("android.permission.")})
        vending_perms = sorted(
            {
                "android.permission.FAKE_PACKAGE_SIGNATURE",
                "android.permission.INSTALL_PACKAGES",
                "android.permission.DELETE_PACKAGES",
                "android.permission.CHECK_LICENSE",
            }
            | {p for p in query_apk_permissions(vending_apk, aapt2_bin) if p.startswith("android.permission.")}
        )
        gsf_perms = sorted({p for p in query_apk_permissions(gsf_apk, aapt2_bin) if p.startswith("android.permission.")})

        perm_dir = out_prod / "etc" / "permissions"
        perm_dir.mkdir(parents=True, exist_ok=True)
        xml_lines = ['<?xml version="1.0" encoding="utf-8"?>', "<permissions>"]
        xml_lines.append('    <privapp-permissions package="com.google.android.gms">')
        for p in gms_perms:
            xml_lines.append(f'        <permission name="{p}" />')
        xml_lines.append("    </privapp-permissions>")
        xml_lines.append('    <privapp-permissions package="com.android.vending">')
        for p in vending_perms:
            xml_lines.append(f'        <permission name="{p}" />')
        xml_lines.append("    </privapp-permissions>")
        if gsf_perms:
            xml_lines.append('    <privapp-permissions package="com.google.android.gsf">')
            for p in gsf_perms:
                xml_lines.append(f'        <permission name="{p}" />')
            xml_lines.append("    </privapp-permissions>")
        xml_lines.append("</permissions>")
        (perm_dir / "privapp-permissions-microg.xml").write_text("\n".join(xml_lines) + "\n", encoding="utf-8")
        os.chmod(perm_dir / "privapp-permissions-microg.xml", 0o644)

        sys_dir = out_prod / "etc" / "sysconfig"
        sys_dir.mkdir(parents=True, exist_ok=True)
        (sys_dir / "microg.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<config>\n"
            '    <allow-in-power-save package="com.google.android.gms" />\n'
            '    <allow-in-data-usage-save package="com.google.android.gms" />\n'
            '    <allow-in-power-save package="com.android.vending" />\n'
            "</config>\n",
            encoding="utf-8",
        )
        os.chmod(sys_dir / "microg.xml", 0o644)

        def_dir = out_prod / "etc" / "default-permissions"
        def_dir.mkdir(parents=True, exist_ok=True)
        (def_dir / "default-permissions-microg.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<exceptions>\n"
            '    <exception package="com.google.android.gms">\n'
            '        <permission name="android.permission.ACCESS_COARSE_LOCATION" fixed="false" />\n'
            '        <permission name="android.permission.ACCESS_FINE_LOCATION" fixed="false" />\n'
            '        <permission name="android.permission.ACCESS_BACKGROUND_LOCATION" fixed="false" />\n'
            '        <permission name="android.permission.POST_NOTIFICATIONS" fixed="false" />\n'
            "    </exception>\n"
            "</exceptions>\n",
            encoding="utf-8",
        )
        os.chmod(def_dir / "default-permissions-microg.xml", 0o644)
        log.append(f"microG config written: privapp({len(gms_perms)} gms, {len(vending_perms)} vending) + sysconfig + default-permissions")

    # Fallback keyboard if HeliBoard was not supplied
    if not (out_prod / "app" / "HeliBoard").is_dir():
        for bp in (base_dir / "product", base_dir / "system_ext", resolve_sys_root(base_dir / "system")):
            base_ime = find_pkg_dir(bp, ("LatinIME",))
            if base_ime:
                cp_preserve(base_ime, out_prod / "app" / base_ime.name)
                log.append(f"keyboard fallback copied from base: {base_ime.name}")
                break

    # Ensure Provision exists if Google SetupWizard was removed
    has_prov = any(
        find_pkg_dir(t, ("Provision", "SetupWizard")) is not None
        for t in (out_sys_root, out_sys_ext, out_prod)
    )
    if not has_prov:
        for bp in (base_dir / "product", base_dir / "system_ext", resolve_sys_root(base_dir / "system")):
            prov = find_pkg_dir(bp, ("Provision",))
            if prov:
                cp_preserve(prov, out_prod / "priv-app" / prov.name)
                log.append(f"copied base Provision for setup completion: {prov.name}")
                break

    # 3. Inspect / best-effort patch services.jar for microG signature spoofing
    services_jar = out_sys_root / "framework" / "services.jar"
    framework_jar = out_sys_root / "framework" / "framework.jar"
    patcher_py = Path(__file__).resolve().parent / "patch_services_spoof.py"
    if gms_mode == "microg" and apktool_jar and patcher_py.is_file() and services_jar.is_file():
        r = subprocess.run(
            [
                sys.executable,
                str(patcher_py),
                "--services-jar",
                str(services_jar),
                "--framework-jar",
                str(framework_jar),
                "--apktool-jar",
                apktool_jar,
                "--oat-dir",
                str(out_sys_root / "framework" / "oat"),
            ],
            text=True,
            capture_output=True,
        )
        for ln in (r.stdout + "\n" + r.stderr).splitlines():
            if ln.strip():
                log.append(f"services.jar spoof: {ln.strip()}")


def integrate_rust_components(
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    memd_bin: str,
    memd_rc: str,
    rust_app_apk: str,
    log: list[str],
) -> None:
    # 1. Native Rust RAM/zRAM/PSI daemon -> /system_ext/bin/r9c-memd + SELinux CIL
    if memd_bin and Path(memd_bin).is_file():
        dst_bin = out_sys_ext / "bin" / "r9c-memd"
        dst_bin.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(memd_bin, dst_bin)
        os.chmod(dst_bin, 0o755)
        log.append(f"installed Rust daemon: {dst_bin} ({dst_bin.stat().st_size // 1024} KiB)")

        if memd_rc and Path(memd_rc).is_file():
            dst_rc = out_sys_ext / "etc" / "init" / "r9c-memd.rc"
            dst_rc.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(memd_rc, dst_rc)
            os.chmod(dst_rc, 0o644)
            log.append(f"installed Rust daemon init rc: {dst_rc}")

        fc_path = out_sys_ext / "etc" / "selinux" / "system_ext_file_contexts"
        if fc_path.is_file():
            fc_txt = fc_path.read_text(encoding="utf-8", errors="replace")
            if "/system_ext/bin/r9c-memd" not in fc_txt:
                fc_path.write_text(
                    fc_txt.rstrip("\n") + "\n/system_ext/bin/r9c-memd\tu:object_r:r9c_memd_exec:s0\n",
                    encoding="utf-8",
                )
                log.append("added r9c_memd_exec context to system_ext_file_contexts")

        plat_cil = out_sys_root / "etc" / "selinux" / "plat_sepolicy.cil"
        se_cil = out_sys_ext / "etc" / "selinux" / "system_ext_sepolicy.cil"
        if plat_cil.is_file() and se_cil.is_file():
            plat_txt = plat_cil.read_text(encoding="utf-8", errors="replace")
            se_txt = se_cil.read_text(encoding="utf-8", errors="replace")
            if "(type r9c_memd)" not in se_txt:
                cil_lines = [
                    "; r9c-memd native Rust daemon domain",
                    "(type r9c_memd)",
                    "(roletype object_r r9c_memd)",
                    "(typeattributeset domain (r9c_memd))",
                    "(type r9c_memd_exec)",
                    "(roletype object_r r9c_memd_exec)",
                    "(typeattributeset file_type (r9c_memd_exec))",
                    "(typeattributeset exec_type (r9c_memd_exec))",
                ]
                for attr in ("coredomain", "mlstrustedsubject"):
                    if f"(typeattribute {attr})" in plat_txt:
                        cil_lines.append(f"(typeattributeset {attr} (r9c_memd))")
                for fattr in ("system_file_type",):
                    if f"(typeattribute {fattr})" in plat_txt:
                        cil_lines.append(f"(typeattributeset {fattr} (r9c_memd_exec))")
                cil_lines.extend([
                    "(typetransition init r9c_memd_exec process r9c_memd)",
                    "(allow init r9c_memd_exec (file (read getattr map execute open)))",
                    "(allow init r9c_memd (process (transition)))",
                    "(allow r9c_memd r9c_memd_exec (file (read getattr map execute open entrypoint)))",
                    "(allow r9c_memd init (fd (use)))",
                    "(allow r9c_memd init (fifo_file (write getattr)))",
                    "(allow r9c_memd init (process (sigchld)))",
                ])
                for ptype in ("proc_meminfo", "proc_pressure_memory", "proc_pressure"):
                    if f"(type {ptype})" in plat_txt:
                        cil_lines.append(f"(allow r9c_memd {ptype} (file (read open getattr)))")
                se_cil.write_text(se_txt.rstrip("\n") + "\n" + "\n".join(cil_lines) + "\n", encoding="utf-8")
                log.append("added r9c_memd SELinux CIL domain rules to system_ext_sepolicy.cil")

    # 2. Pure-Rust NativeActivity APK -> /product/app/Redmi9CRustApp/Redmi9CRustApp.apk
    if rust_app_apk and Path(rust_app_apk).is_file():
        install_apk_dir(Path(rust_app_apk), out_prod / "app" / "Redmi9CRustApp", log)


def integrate_mysticalos(
    out_sys_root: Path,
    out_prod: Path,
    mystical_launcher_apk: str,
    bootanimation_zip: str,
    aapt2_bin: str,
    log: list[str],
) -> None:
    # 1. Install MysticalLauncher.apk (ColorOS 17 icon resizer & Flux tiles) as priv-app HOME launcher
    if mystical_launcher_apk and Path(mystical_launcher_apk).is_file():
        launcher_src = Path(mystical_launcher_apk)
        install_apk_dir(launcher_src, out_prod / "priv-app" / "MysticalLauncher", log)
        perm_dir = out_prod / "etc" / "permissions"
        perm_dir.mkdir(parents=True, exist_ok=True)
        ml_perm = perm_dir / "privapp-permissions-mysticalos.xml"
        ml_perm.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<permissions>\n"
            '    <privapp-permissions package="org.mysticalos.launcher">\n'
            '        <permission name="android.permission.QUERY_ALL_PACKAGES" />\n'
            '        <permission name="android.permission.SET_WALLPAPER" />\n'
            '        <permission name="android.permission.REQUEST_DELETE_PACKAGES" />\n'
            '        <permission name="android.permission.EXPAND_STATUS_BAR" />\n'
            '        <permission name="android.permission.PACKAGE_USAGE_STATS" />\n'
            "    </privapp-permissions>\n"
            "</permissions>\n",
            encoding="utf-8",
        )
        os.chmod(ml_perm, 0o644)
        log.append("MysticalLauncher permissions written: privapp-permissions-mysticalos.xml")

    # 2. Install MysticalOS bootanimation.zip (720x1600, ZIP_STORED)
    boot_dst_prod = out_prod / "media" / "bootanimation.zip"
    boot_dst_prod.parent.mkdir(parents=True, exist_ok=True)
    if bootanimation_zip and Path(bootanimation_zip).is_file():
        shutil.copy2(bootanimation_zip, boot_dst_prod)
        os.chmod(boot_dst_prod, 0o644)
    else:
        mysticalos_brand.generate_bootanimation(boot_dst_prod, target_w=720, target_h=1600)
    log.append(f"MysticalOS bootanimation installed: {boot_dst_prod} ({boot_dst_prod.stat().st_size // 1024} KiB)")

    sys_boot = out_sys_root / "media" / "bootanimation.zip"
    if sys_boot.exists():
        shutil.copy2(boot_dst_prod, sys_boot)
        os.chmod(sys_boot, 0o644)
        log.append(f"MysticalOS bootanimation mirrored -> {sys_boot}")

    # 3. Compile & install MysticalOSFrameworkOverlay.apk (ColorOS 17 squircle mask + Flux accent)
    donor_fw_res = out_sys_root / "framework" / "framework-res.apk"
    mysticalos_brand.build_framework_rro_overlay(
        donor_fw_res=donor_fw_res,
        aapt2_bin=aapt2_bin,
        out_apk=out_prod / "overlay" / "MysticalOSFrameworkOverlay.apk",
        log=log,
    )


def configure_props_and_zygote(
    out_sys_root: Path,
    out_sys_ext: Path,
    out_prod: Path,
    variant: str,
    gms_mode: str,
    os_name: str,
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

    os_label = os_name.strip() or "MysticalOS"
    common_updates = {
        "ro.zygote": zygote_mode,
        "ro.sf.lcd_density": "320",
        "ro.product.os.name": os_label,
        "ro.mysticalos.version": "1.0",
        "ro.mysticalos.codename": "Flux17",
        "ro.mysticalos.icon_engine": "ColorOS17-FluxResize",
        "ro.modversion": f"{os_label}-1.0-{dev}",
        "ro.mi.os.version.name": f"{os_label} 1.0",
        "ro.build.flavor": f"mysticalos_{dev}-userdebug",
        "ro.build.display.id": f"{os_label} 1.0 (ColorOS17 Icons · {'microG+FOSS+Rust' if gms_mode == 'microg' else 'FOSS+Rust'} · {market})",
        "persist.sys.background_blur_supported": "false",
        "ro.surface_flinger.supports_background_blur": "0",
        "persist.sys.miui.blur.level": "0",
        "persist.arm64.memtag.system_server": "off",
        "dalvik.vm.heapstartsize": "8m",
        "dalvik.vm.heapgrowthlimit": "192m",
        "dalvik.vm.heapsize": "384m",
        "dalvik.vm.heaptargetutilization": "0.75",
        "dalvik.vm.heapminfree": "2m",
        "dalvik.vm.heapmaxfree": "8m",
        "dalvik.vm.dex2oat-threads": "4",
        "ro.lmk.use_psi": "true",
        "ro.lmk.kill_heaviest_task": "true",
        "ro.lmk.psi_partial_stall_ms": "70",
        "ro.lmk.psi_complete_stall_ms": "500",
        "ro.lmk.thrashing_limit": "30",
        "ro.lmk.thrashing_limit_decay": "10",
        "ro.lmk.swap_free_low_percentage": "15",
        "ro.sys.fw.bg_apps_limit": "16",
        "persist.sys.purgeable_assets": "1",
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
    if gms_mode != "keep":
        common_updates["ro.setupwizard.mode"] = "DISABLED"

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
    ap.add_argument("--gms-mode", default="microg", choices=["microg", "keep", "none"])
    ap.add_argument("--os-name", default="MysticalOS", help="OS brand name for build.prop and manifest")
    ap.add_argument("--keep-xiaomi-apps", action="store_true", help="Keep Xiaomi user-facing apps instead of replacing with FOSS")
    ap.add_argument("--extra-apps-dir", default="", help="Dir containing GmsCore.apk, FakeStore.apk, HeliBoard.apk, Droid-ify.apk, Fossify*.apk")
    ap.add_argument("--mystical-launcher-apk", default="", help="Compiled MysticalLauncher.apk (ColorOS 17 icon size/tile launcher)")
    ap.add_argument("--bootanimation-zip", default="", help="Optional prebuilt MysticalOS bootanimation.zip")
    ap.add_argument("--r9c-memd-bin", default="", help="Compiled aarch64 r9c-memd binary")
    ap.add_argument("--r9c-memd-rc", default="", help="r9c-memd.rc init script")
    ap.add_argument("--rust-app-apk", default="", help="Compiled pure-Rust NativeActivity APK")
    ap.add_argument("--apktool-jar", default="", help="apktool jar for services.jar inspection/patching")
    ap.add_argument("--aapt2-bin", default="", help="aapt2 binary for APK manifest/webview inspection")
    ap.add_argument("--target-os-mib", type=int, default=4700, help="Target max uncompressed MiB for system+system_ext+product (0=disabled)")
    ap.add_argument("--manifest-out", default="", help="Optional JSON manifest path for MysticalOS Windows Emulator")
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

    remove_xiaomi_apps = not args.keep_xiaomi_apps
    merge_mi_ext(donor / "mi_ext", out_sys_root, out_sys_ext, out_prod, log)
    removed_items, freed_bytes = debloat_trees(
        out_sys_root, out_sys_ext, out_prod, args.debloat_level, args.gms_mode, log, remove_xiaomi_apps=remove_xiaomi_apps
    )
    extra_dir = Path(args.extra_apps_dir) if args.extra_apps_dir else None
    integrate_microg_and_foss(
        base,
        out_sys_root,
        out_sys_ext,
        out_prod,
        extra_dir,
        args.apktool_jar,
        args.aapt2_bin,
        args.gms_mode,
        log,
    )
    integrate_rust_components(
        out_sys_root,
        out_sys_ext,
        out_prod,
        args.r9c_memd_bin,
        args.r9c_memd_rc,
        args.rust_app_apk,
        log,
    )
    integrate_mysticalos(
        out_sys_root,
        out_prod,
        args.mystical_launcher_apk,
        args.bootanimation_zip,
        args.aapt2_bin,
        log,
    )
    trim_to_budget(base, out, out_sys_root, out_sys_ext, out_prod, args.target_os_mib, log)
    adapt_blossom_hardware(base, out, out_sys_root, out_sys_ext, out_prod, log)
    configure_props_and_zygote(out_sys_root, out_sys_ext, out_prod, args.variant, args.gms_mode, args.os_name, log)

    sizes = {p: dir_size_bytes(out / p) for p in ("system", "system_ext", "product", "vendor", "odm")}
    total_mb = sum(sizes.values()) // (1024 * 1024)
    log.append("FINAL TREE SIZES (uncompressed):")
    for p, sz in sizes.items():
        log.append(f"  {p}: {sz // (1024 * 1024)} MiB ({sz} B)")
    log.append(f"  TOTAL: {total_mb} MiB")

    scanned_apps = mysticalos_brand.scan_launcher_apps(
        [("system", out_sys_root), ("system_ext", out_sys_ext), ("product", out_prod)],
        args.aapt2_bin,
    )
    launchable_apps = [a for a in scanned_apps if a.get("launchable")]
    if launchable_apps:
        log.append(f"LAUNCHABLE APPS AUDIT ({len(launchable_apps)} apps visible in launcher):")
        for a in launchable_apps:
            log.append(f"  - {a['label']} ({a['package']}) [{a['partition']}, {a['size_kib']} KiB]")

    if args.manifest_out:
        spoof_line = next((ln for ln in log if ln.startswith("services.jar spoof: STATUS:")), "services.jar spoof: unknown")
        manifest = {
            "os_name": args.os_name,
            "os_version": "1.0",
            "codename": "Flux17",
            "variant": args.variant,
            "market_name": "Redmi 9C NFC" if args.variant == "angelican" else "Redmi 9C",
            "android_version": "17",
            "kernel_version": "4.19 OSS (blossom)",
            "base_rom": "EvolutionX 17.0 blossom",
            "donor_rom": "HyperOS 4.0.8.0.XBNMIXM (dew) debloated",
            "gms_mode": args.gms_mode,
            "icon_engine": "ColorOS 17 Flux Icon Resizer (60%-150% + 1x1/2x1/1x2/2x2)",
            "removed_count": len(removed_items),
            "freed_mib": freed_bytes // (1024 * 1024),
            "removed_items": removed_items,
            "partition_uncompressed_mib": {k: v // (1024 * 1024) for k, v in sizes.items()},
            "services_spoof": spoof_line,
            "launchable_apps": launchable_apps,
            "total_apks_audited": len(scanned_apps),
        }
        mp = Path(args.manifest_out)
        mp.parent.mkdir(parents=True, exist_ok=True)
        mp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        log.append(f"MysticalOS manifest written: {mp} ({len(launchable_apps)} launchable apps)")

    hogs = top_space_hogs([("system", out_sys_root), ("system_ext", out_sys_ext), ("product", out_prod)], top_n=45)
    if hogs:
        log.append("TOP REMAINING OS ENTRIES (>=5 MiB):")
        log.extend(hogs)

    Path(args.report).write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
