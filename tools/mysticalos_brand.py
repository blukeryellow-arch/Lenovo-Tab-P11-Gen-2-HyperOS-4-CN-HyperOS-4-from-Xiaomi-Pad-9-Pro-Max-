#!/usr/bin/env python3
"""Generacja brandingu MysticalOS: bootanimation.zip (720x1600), RRO overlay oraz manifest JSON."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile
import zlib
from pathlib import Path


FONT_5X7: dict[str, tuple[str, ...]] = {
    "M": ("#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"),
    "Y": ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
    "S": (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
    "T": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
    "I": (".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."),
    "C": (".####", "#....", "#....", "#....", "#....", "#....", ".####"),
    "A": ("..#..", ".#.#.", "#...#", "#####", "#...#", "#...#", "#...#"),
    "L": ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
    "O": (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    " ": (".....", ".....", ".....", ".....", ".....", ".....", "....."),
    "1": ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
    "0": (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
    "7": ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
    ".": (".....", ".....", ".....", ".....", ".....", ".##..", ".##.."),
    "B": ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
    "F": ("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
    "U": ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "X": ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
}


def encode_png_rgb(width: int, height: int, rgb: bytearray) -> bytes:
    """Minimal deterministic RGB PNG encoder using only stdlib zlib/struct."""
    stride = width * 3
    raw = bytearray((stride + 1) * height)
    for y in range(height):
        src_off = y * stride
        dst_off = y * (stride + 1)
        raw[dst_off] = 0  # filter None
        raw[dst_off + 1 : dst_off + 1 + stride] = rgb[src_off : src_off + stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), level=6)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def draw_text(rgb: bytearray, width: int, height: int, text: str, cy: int, scale: int, color: tuple[int, int, int], alpha: float) -> None:
    if alpha <= 0.01:
        return
    glyph_w = 5 * scale
    gap = scale
    total_w = len(text) * glyph_w + max(0, len(text) - 1) * gap
    x0 = (width - total_w) // 2
    y0 = cy - (7 * scale) // 2

    cr, cg, cb = color
    for idx, ch in enumerate(text.upper()):
        pat = FONT_5X7.get(ch)
        if not pat:
            continue
        gx = x0 + idx * (glyph_w + gap)
        for ry, row in enumerate(pat):
            for rx, bit in enumerate(row):
                if bit != "#":
                    continue
                px0 = gx + rx * scale
                py0 = y0 + ry * scale
                for dy in range(scale):
                    yy = py0 + dy
                    if not (0 <= yy < height):
                        continue
                    row_off = yy * width * 3
                    for dx in range(scale):
                        xx = px0 + dx
                        if not (0 <= xx < width):
                            continue
                        p = row_off + xx * 3
                        rgb[p] = min(255, int(rgb[p] * (1.0 - alpha) + cr * alpha))
                        rgb[p + 1] = min(255, int(rgb[p + 1] * (1.0 - alpha) + cg * alpha))
                        rgb[p + 2] = min(255, int(rgb[p + 2] * (1.0 - alpha) + cb * alpha))


def render_boot_frame(w: int, h: int, phase: float, intro: bool) -> bytes:
    """Render one frame of the MysticalOS Flux boot animation."""
    rgb = bytearray(w * h * 3)
    cx = w * 0.5
    cy = h * 0.44
    fade = min(1.0, phase * 1.4) if intro else 1.0
    pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 2.0)

    # Background deep space gradient + radial aura + Flux diamond emblem
    for y in range(h):
        yf = y / max(1, h - 1)
        base_r = int((6 + 10 * yf) * fade)
        base_g = int((8 + 12 * yf) * fade)
        base_b = int((20 + 28 * yf) * fade)
        row_off = y * w * 3
        dy = y - cy
        for x in range(w):
            dx = x - cx
            dist = math.hypot(dx, dy)
            r, g, b = base_r, base_g, base_b

            # Soft glowing ring
            ring_d = abs(dist - (w * (0.23 + 0.015 * pulse)))
            if ring_d < 14.0:
                ang = math.atan2(dy, dx) + phase * math.pi * 2.0
                glow = ((1.0 - ring_d / 14.0) ** 2) * (0.55 + 0.45 * math.cos(ang)) * fade
                r += int(75 * glow)
                g += int(145 * glow)
                b += int(255 * glow)

            # Central Flux diamond
            man = abs(dx) + abs(dy)
            if man < w * 0.145:
                inner = 1.0 - man / (w * 0.145)
                if man < w * 0.075:
                    # Cyan core
                    k = fade * (0.75 + 0.25 * inner)
                    r = int(r * (1 - k) + 18 * k)
                    g = int(g * (1 - k) + 225 * k)
                    b = int(b * (1 - k) + 255 * k)
                else:
                    # Indigo prism shell
                    k = fade * (0.85)
                    r = int(r * (1 - k) + 102 * k)
                    g = int(g * (1 - k) + 64 * k)
                    b = int(b * (1 - k) + 245 * k)

            p = row_off + x * 3
            rgb[p] = min(255, r)
            rgb[p + 1] = min(255, g)
            rgb[p + 2] = min(255, b)

    draw_text(rgb, w, h, "MYSTICAL OS", int(h * 0.62), max(2, w // 90), (244, 248, 255), fade)
    draw_text(rgb, w, h, "FLUX 17", int(h * 0.67), max(1, w // 140), (0, 224, 255), fade * 0.9)
    return encode_png_rgb(w, h, rgb)


def generate_bootanimation(out_zip: Path, target_w: int = 720, target_h: int = 1600) -> Path:
    """Create Android-compatible bootanimation.zip using ZIP_STORED (required by Android bootanimation)."""
    out_zip.parent.mkdir(parents=True, exist_ok=True)
    # Render crisp 360x800 frames; desc.txt upscales cleanly to 720x1600 @ 24 fps
    rw, rh = max(180, target_w // 2), max(400, target_h // 2)
    desc = f"{target_w} {target_h} 24\np 1 0 part0\np 0 0 part1\n".encode("ascii")

    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_STORED) as zf:
        zf.writestr("desc.txt", desc)
        for i in range(10):
            png = render_boot_frame(rw, rh, i / 9.0, intro=True)
            zf.writestr(f"part0/{i:03d}.png", png)
        for i in range(12):
            png = render_boot_frame(rw, rh, i / 12.0, intro=False)
            zf.writestr(f"part1/{i:03d}.png", png)
    os.chmod(out_zip, 0o644)
    return out_zip


def build_framework_rro_overlay(
    donor_fw_res: Path,
    aapt2_bin: str,
    out_apk: Path,
    log: list[str],
) -> bool:
    """Compile MysticalOSFrameworkOverlay.apk overriding verified resources in donor framework-res.apk."""
    if not aapt2_bin or not donor_fw_res.is_file():
        return False

    res_dump = subprocess.run(
        [aapt2_bin, "dump", "resources", str(donor_fw_res)],
        text=True,
        capture_output=True,
    )
    if res_dump.returncode != 0:
        log.append("MysticalOS RRO: aapt2 dump resources nie powiodl sie")
        return False

    dump_txt = res_dump.stdout
    values_items: list[str] = []

    # Check if standard icon mask exists in donor framework-res -> apply ColorOS 17 squircle mask!
    if "string/config_icon_mask" in dump_txt:
        squircle_mask = "M50,0 C88,0 100,12 100,50 C100,88 88,100 50,100 C12,100 0,88 0,50 C0,12 12,0 50,0 Z"
        values_items.append(f'    <string name="config_icon_mask" translatable="false">{squircle_mask}</string>')

    if "bool/config_useRoundIcon" in dump_txt:
        values_items.append('    <bool name="config_useRoundIcon">true</bool>')

    if "color/accent_device_default_dark" in dump_txt:
        values_items.append('    <color name="accent_device_default_dark">#FF6C5CE7</color>')
    if "color/accent_device_default_light" in dump_txt:
        values_items.append('    <color name="accent_device_default_light">#FF5B3CF5</color>')

    if not values_items:
        log.append("MysticalOS RRO: brak pasujacych zasobow w framework-res.apk (pomijam overlay)")
        return False

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        res_dir = tmp / "res" / "values"
        res_dir.mkdir(parents=True, exist_ok=True)
        (res_dir / "values.xml").write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            + "\n".join(values_items)
            + "\n</resources>\n",
            encoding="utf-8",
        )
        manifest = tmp / "AndroidManifest.xml"
        manifest.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    package="org.mysticalos.overlay.framework">\n'
            '    <application android:hasCode="false" />\n'
            '    <overlay android:targetPackage="android"\n'
            '        android:isStatic="true"\n'
            '        android:priority="950" />\n'
            "</manifest>\n",
            encoding="utf-8",
        )
        compiled = tmp / "compiled.zip"
        r1 = subprocess.run([aapt2_bin, "compile", "--dir", str(tmp / "res"), "-o", str(compiled)], text=True, capture_output=True)
        if r1.returncode != 0:
            log.append(f"MysticalOS RRO compile error: {r1.stderr[:240]}")
            return False

        out_apk.parent.mkdir(parents=True, exist_ok=True)
        r2 = subprocess.run(
            [aapt2_bin, "link", "-I", str(donor_fw_res), "--manifest", str(manifest), "-o", str(out_apk), str(compiled)],
            text=True,
            capture_output=True,
        )
        if r2.returncode != 0 or not out_apk.is_file():
            log.append(f"MysticalOS RRO link error: {r2.stderr[:240]}")
            return False

    os.chmod(out_apk, 0o644)
    log.append(f"MysticalOS RRO installed: {out_apk.name} ({len(values_items)} resources: Squircle mask + Flux accent)")
    return True


def scan_launcher_apps(roots: list[tuple[str, Path]], aapt2_bin: str) -> list[dict[str, object]]:
    """Audit all launchable APKs remaining across system/system_ext/product using aapt2."""
    apps: list[dict[str, object]] = []
    if not aapt2_bin:
        return apps

    seen_pkgs: set[str] = set()
    for part_name, root in roots:
        for sub in ("priv-app", "app"):
            base = root / sub
            if not base.is_dir():
                continue
            for pkg_dir in sorted(base.iterdir()):
                if not pkg_dir.is_dir():
                    continue
                apks = sorted(pkg_dir.glob("*.apk"))
                if not apks:
                    continue
                apk = apks[0]
                r = subprocess.run([aapt2_bin, "dump", "badging", str(apk)], text=True, capture_output=True)
                if r.returncode != 0:
                    continue
                txt = r.stdout
                m_pkg = re.search(r"package:\s*name='([^']+)'", txt)
                pkg_id = m_pkg.group(1) if m_pkg else pkg_dir.name
                if pkg_id in seen_pkgs:
                    continue
                has_launcher = ("launchable-activity:" in txt) or ("android.intent.category.HOME" in txt)
                m_lbl = re.search(r"application-label:'([^']*)'", txt)
                label = m_lbl.group(1) if m_lbl else pkg_dir.name
                sz_kib = sum(f.stat().st_size for f in pkg_dir.rglob("*") if f.is_file()) // 1024
                seen_pkgs.add(pkg_id)
                apps.append({
                    "dir": pkg_dir.name,
                    "package": pkg_id,
                    "label": label,
                    "partition": f"{part_name}/{sub}",
                    "size_kib": sz_kib,
                    "launchable": has_launcher,
                })
    return apps


def selftest() -> int:
    with tempfile.TemporaryDirectory() as td:
        zpath = Path(td) / "bootanimation.zip"
        generate_bootanimation(zpath, target_w=360, target_h=800)
        with zipfile.ZipFile(zpath, "r") as zf:
            infos = zf.infolist()
            assert "desc.txt" in zf.namelist()
            assert any(n.startswith("part0/") and n.endswith(".png") for n in zf.namelist())
            assert any(n.startswith("part1/") and n.endswith(".png") for n in zf.namelist())
            assert all(i.compress_type == zipfile.ZIP_STORED for i in infos), "bootanimation must use ZIP_STORED"
            png0 = zf.read("part0/000.png")
            assert png0[:8] == b"\x89PNG\r\n\x1a\n"
    print("mysticalos_brand selftest OK!")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bootanim-out", default="")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.bootanim_out:
        p = generate_bootanimation(Path(args.bootanim_out))
        print(f"Generated {p} ({p.stat().st_size} B)")
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
