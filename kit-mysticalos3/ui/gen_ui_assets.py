#!/usr/bin/env python3
# =============================================================================
# MysticalOS 0.5 Full UI - generator assetow wizualnych (TB350FU 2000x1200)
#   wallpaper.png      - HyperOS-style tapeta systemowa (gradient + glow)
#   bootanimation.zip  - animacja startowa (desc.txt + part0 intro + part1 loop,
#                        PNG RGB, ZIP STORED - wymog BootAnimation)
# Uzycie: gen_ui_assets.py <outdir> <font.ttf>
# Czcionka wordmarku = MiSans (HyperOS Typography) jesli dostepna.
# =============================================================================
import math
import os
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2000, 1200
FPS = 24
INTRO_FRAMES = 36   # 1.5 s intro
LOOP_FRAMES = 36    # 1.5 s petla (nieskonczona az do boot_completed)

TOP_C = (10, 14, 40)      # gleboki granat
BOT_C = (44, 24, 92)      # fiolet HyperOS
ACCENT = (110, 170, 255)  # chlodny blekit


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))


def base_bg(bright=1.0):
    """Diagonalny gradient granat->fiolet (maly obraz + upscale = szybkie)."""
    small = Image.new("RGB", (W // 8, H // 8))
    sp = small.load()
    for y in range(small.height):
        for x in range(small.width):
            t = (x / small.width) * 0.62 + (y / small.height) * 0.38
            r, g, b = mix(TOP_C, BOT_C, t)
            sp[x, y] = (min(255, int(r * bright)),
                        min(255, int(g * bright)),
                        min(255, int(b * bright)))
    return small.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(3))


def glow_layer(strength=0.55):
    """Miekkie rozmyte plamy swiatla (HyperOS wallpaper vibe)."""
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(layer)
    blobs = [
        (380, 260, 340, (70, 40, 160)),
        (1660, 330, 280, (30, 90, 200)),
        (1140, 1010, 320, (90, 30, 140)),
        (1760, 950, 210, (20, 120, 180)),
        (640, 880, 170, (60, 60, 170)),
    ]
    for x, y, r, c in blobs:
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    return layer.filter(ImageFilter.GaussianBlur(140))


def make_wallpaper(out):
    img = Image.blend(base_bg(), glow_layer(), 0.55)
    # subtelna winieta
    vign = Image.new("L", (W // 8, H // 8), 0)
    dv = ImageDraw.Draw(vign)
    dv.rectangle([0, 0, W // 8, H // 8], fill=90)
    dv.ellipse([-W // 16, -H // 16, W // 8 + W // 16, H // 8 + H // 16], fill=200)
    vign = vign.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(60))
    black = Image.new("RGB", (W, H), (0, 0, 0))
    img = Image.composite(img, black, vign.point(lambda v: 40 + v * 215 // 255))
    img.save(out, "PNG", optimize=True)
    return out


def _ring(layer, r, alpha255, width=7):
    d = ImageDraw.Draw(layer, "RGBA")
    cx, cy = W // 2, int(H * 0.42)
    col = ACCENT + (alpha255,)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=width)
    # glow pod spodem
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dg = ImageDraw.Draw(gl)
    dg.ellipse([cx - r - 30, cy - r - 30, cx + r + 30, cy + r + 30],
               fill=ACCENT + (int(alpha255 * 0.35),))
    gl = gl.filter(ImageFilter.GaussianBlur(40))
    layer.alpha_composite(gl)
    d = ImageDraw.Draw(layer, "RGBA")
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ACCENT + (alpha255,), width=width)
    # kropka w srodku
    dot = 14
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(235, 245, 255, alpha255))


def boot_frame(font, phase, t):
    """phase: 'intro' (t: 0..1) albo 'loop' (t: 0..1). Zwraca RGB Image."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    if phase == "intro":
        ease = t * t * (3 - 2 * t)  # smoothstep
        ring_r = int(lerp(60, 260, ease))
        ring_a = int(lerp(40, 220, ease))
        text_a = int(lerp(0, 235, max(0.0, (t - 0.25) / 0.75)))
        bg_b = lerp(0.35, 1.0, ease)
    else:
        pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi)
        ring_r = int(260 + 22 * pulse)
        ring_a = int(200 - 45 * pulse)
        text_a = 235
        bg_b = 0.92 + 0.08 * pulse
    # tlo: gradient przyciemniony + slaby glow
    bg = base_bg(bg_b)
    img = Image.alpha_composite(bg.convert("RGBA"), Image.new("RGBA", (W, H), (0, 0, 0, 0)))
    _ring(img, ring_r, ring_a)
    # wordmark
    d = ImageDraw.Draw(img, "RGBA")
    txt = "MysticalOS"
    bbox = d.textbbox((0, 0), txt, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (W - tw) // 2 - bbox[0]
    ty = int(H * 0.42) + 300
    d.text((tx, ty), txt, font=font, fill=(240, 246, 255, text_a))
    sub = "0.5  ·  HyperOS 4 x A17"
    f2 = font.font_variant(size=font.size // 3) if hasattr(font, "font_variant") else font
    b2 = d.textbbox((0, 0), sub, font=f2)
    d.text(((W - (b2[2] - b2[0])) // 2 - b2[0], ty + th + 46), sub,
           font=f2, fill=(150, 175, 215, int(text_a * 0.85)))
    return img.convert("RGB")


def make_bootanimation(out, fontpath):
    font = ImageFont.truetype(fontpath, 150)
    desc = f"{W} {H} {FPS}\np 1 0 part0\np 0 0 part1\n"
    frames = {"part0": [], "part1": []}
    for i in range(INTRO_FRAMES):
        frames["part0"].append(boot_frame(font, "intro", i / (INTRO_FRAMES - 1)))
    for i in range(LOOP_FRAMES):
        frames["part1"].append(boot_frame(font, "loop", i / LOOP_FRAMES))
    # ZIP MUSI byc STORED (bez kompresji) - wymog android bootanimation
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        zi = zipfile.ZipInfo("desc.txt")
        z.writestr(zi, desc)
        for part in ("part0", "part1"):
            for i, fr in enumerate(frames[part]):
                z.writestr(f"{part}/{i:04d}.png",
                           _png_bytes(fr))
    return out, desc, INTRO_FRAMES + LOOP_FRAMES


def _png_bytes(img):
    import io
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def main():
    outdir, fontpath = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    wp = make_wallpaper(os.path.join(outdir, "wallpaper.png"))
    ba, desc, n = make_bootanimation(os.path.join(outdir, "bootanimation.zip"), fontpath)
    print("wallpaper:", wp, os.path.getsize(wp), "B")
    print("bootanimation:", ba, os.path.getsize(ba), "B,", n, "klatek")
    print("desc.txt:\n" + desc)


if __name__ == "__main__":
    main()
