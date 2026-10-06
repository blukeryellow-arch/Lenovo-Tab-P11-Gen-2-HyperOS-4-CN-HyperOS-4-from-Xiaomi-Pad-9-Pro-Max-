#!/usr/bin/env python3
# =============================================================================
# MysticalOS 0.5 HyperOS Port - generator assetow wizualnych v2 (HyperOS 4 look)
#   wallpaper.png      - "Super Wallpaper" style: aurora orb + bloom + gwiazdy
#   bootanimation.zip  - animacja startowa (intro + loop; PNG RGB, ZIP STORED)
#   preview-*.png      - klatki podgladowe (virtual bench / dla uzytkownika)
# Uzycie: gen_ui_assets.py <outdir> <font.ttf>
# =============================================================================
import io
import math
import os
import random
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 2000, 1200
FPS = 24
INTRO_FRAMES = 40   # ~1.7 s
LOOP_FRAMES = 40    # ~1.7 s petli

C_DEEP = (8, 10, 26)
C_MID = (26, 16, 64)
C_VIOLET = (84, 36, 148)
C_CYAN = (24, 120, 190)
C_GLOW = (140, 190, 255)
STAR = (220, 235, 255)


def _mix(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def base_bg(bright=1.0):
    """Wielowarstwowy radialny gradient (HyperOS 4 super-wallpaper vibe)."""
    small = Image.new("RGB", (W // 10, H // 10))
    sp = small.load()
    cx, cy = 0.68 * small.width, 0.42 * small.height
    maxd = math.hypot(small.width, small.height)
    for y in range(small.height):
        for x in range(small.width):
            d = math.hypot(x - cx, y - cy) / maxd
            if d < 0.45:
                c = _mix(C_VIOLET, C_MID, d / 0.45)
            else:
                c = _mix(C_MID, C_DEEP, min(1.0, (d - 0.45) / 0.55))
            r, g, b = c
            # lekkie "uderzenie" cyjanu z lewego dolu (aurora)
            a = max(0.0, 1.0 - math.hypot(x - 0.15 * small.width,
                                           y - 1.05 * small.height) / (0.8 * maxd))
            r, g, b = (min(255, r + C_CYAN[0] * a * 0.35),
                       min(255, g + C_CYAN[1] * a * 0.35),
                       min(255, b + C_CYAN[2] * a * 0.35))
            sp[x, y] = (int(r * bright), int(g * bright), int(b * bright))
    return small.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(4))


def stars_layer(seed=7):
    """Pole gwiazd (2 warzty: ostre + rozmyte)."""
    rng = random.Random(seed)
    sharp = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(sharp)
    for _ in range(260):
        x, y = rng.randrange(W), rng.randrange(H)
        r = rng.choice((1, 1, 1, 2))
        a = rng.randrange(60, 220)
        d.ellipse([x - r, y - r, x + r, y + r], fill=a)
    return Image.merge("RGB", [sharp, sharp, sharp]), sharp.filter(
        ImageFilter.GaussianBlur(3)).point(lambda v: v // 2)


def orb_layer(strength=1.0, radius=330, off=(0, 0)):
    """Swiecacy orb (rdzen + halo + pierscienie) - znak rozpoznawczy HyperOS."""
    cx = int(W * 0.68) + off[0]
    cy = int(H * 0.42) + off[1]
    halo = Image.new("RGB", (W, H), (0, 0, 0))
    dh = ImageDraw.Draw(halo)
    hr = int(radius * 2.1)
    dh.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=(46, 22, 96))
    halo = halo.filter(ImageFilter.GaussianBlur(160))
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    dc.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
               fill=(150, 190, 255, 120))
    core = core.filter(ImageFilter.GaussianBlur(90))
    rings = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rings)
    for mult, alpha, wd in ((1.35, 70, 5), (1.75, 45, 4), (2.2, 26, 3)):
        rr = int(radius * mult)
        dr.ellipse([cx - rr, int(cy - rr * 0.42), cx + rr, int(cy + rr * 0.42)],
                   outline=C_GLOW + (alpha,), width=wd)
    rings = rings.filter(ImageFilter.GaussianBlur(2))
    out = Image.blend(base_bg(1.0), halo, 0.5 * strength)
    out = Image.alpha_composite(out.convert("RGBA"), core)
    out.alpha_composite(rings)
    return out.convert("RGB")


def make_wallpaper(out):
    img = orb_layer(1.0)
    stars, stars_soft = stars_layer()
    img = Image.blend(img, stars, 0.55)
    img = Image.blend(img, Image.merge("RGB", [stars_soft] * 3), 0.35)
    # winieta
    vign = Image.new("L", (W // 8, H // 8), 0)
    dv = ImageDraw.Draw(vign)
    dv.rectangle([0, 0, W // 8, H // 8], fill=70)
    dv.ellipse([-W // 16, -H // 16, W // 8 + W // 16, H // 8 + H // 16], fill=205)
    vign = vign.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(70))
    img = Image.composite(img, Image.new("RGB", (W, H), (0, 0, 0)),
                          vign.point(lambda v: 30 + v * 225 // 255))
    img.save(out, "PNG", optimize=True)
    return out


def boot_frame(font, phase, t):
    img = base_bg(0.9 if phase == "intro" else 0.86)
    if phase == "intro":
        ease = t * t * (3 - 2 * t)
        rad = int(90 + 240 * ease)
        a = int(60 + 160 * ease)
        text_a = int(max(0.0, (t - 0.3) / 0.7) * 235)
        off = (int((1 - ease) * 140), int((1 - ease) * 60))
    else:
        pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi)
        rad = int(330 + 26 * pulse)
        a = int(200 - 40 * pulse)
        text_a = 235
        off = (int(-20 * pulse), int(-8 * pulse))
    orb = orb_layer(1.0, rad, off)
    img = Image.blend(img, orb, (0.85 if phase == "intro" else 0.8))
    # gwiazdy delikatnie migaja w petli
    stars, _ = stars_layer(seed=11)
    tw = 0.35 + 0.15 * math.sin(t * 2 * math.pi) if phase == "loop" else 0.3
    img = Image.blend(img, stars, tw)
    img = img.convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    txt = "MysticalOS"
    bbox = d.textbbox((0, 0), txt, font=font)
    tw_, th_ = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (W - tw_) // 2 - bbox[0]
    ty = int(H * 0.42) + 430
    # cien + tekst
    d.text((tx + 3, ty + 4), txt, font=font, fill=(0, 0, 0, int(text_a * 0.5)))
    d.text((tx, ty), txt, font=font, fill=(242, 247, 255, text_a))
    sub = "HyperOS 4  x  Android 17"
    f2 = font.font_variant(size=font.size // 3) if hasattr(font, "font_variant") else font
    b2 = d.textbbox((0, 0), sub, font=f2)
    d.text(((W - (b2[2] - b2[0])) // 2 - b2[0], ty + th_ + 44), sub,
           font=f2, fill=(150, 178, 220, int(text_a * 0.9)))
    return img.convert("RGB")


def _png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def make_bootanimation(out, fontpath):
    font = ImageFont.truetype(fontpath, 150)
    desc = f"{W} {H} {FPS}\np 1 0 part0\np 0 0 part1\n"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        z.writestr(zipfile.ZipInfo("desc.txt"), desc)
        for i in range(INTRO_FRAMES):
            z.writestr(f"part0/{i:04d}.png",
                       _png_bytes(boot_frame(font, "intro", i / (INTRO_FRAMES - 1))))
        for i in range(LOOP_FRAMES):
            z.writestr(f"part1/{i:04d}.png",
                       _png_bytes(boot_frame(font, "loop", i / LOOP_FRAMES)))
    return out, desc, INTRO_FRAMES + LOOP_FRAMES


def main():
    outdir, fontpath = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    wp = make_wallpaper(os.path.join(outdir, "wallpaper.png"))
    ba, desc, n = make_bootanimation(os.path.join(outdir, "bootanimation.zip"), fontpath)
    # podglad dla "virtual bench" (uzytkownik widzi obraz przed flashem)
    font = ImageFont.truetype(fontpath, 150)
    boot_frame(font, "intro", 0.99).save(os.path.join(outdir, "preview-boot.jpg"), quality=90)
    Image.open(wp).resize((1000, 600)).save(os.path.join(outdir, "preview-wallpaper.jpg"), quality=90)
    print("wallpaper:", wp, os.path.getsize(wp), "B")
    print("bootanimation:", ba, os.path.getsize(ba), "B,", n, "klatek")
    print("desc.txt:\n" + desc)


if __name__ == "__main__":
    main()
