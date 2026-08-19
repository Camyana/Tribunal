"""Palette-snap, trim, downscale and alpha-restore the generated art.

The image model returns off-spec colors (#F0B329 instead of #E8B23A) and its
1024px linework dissolves under an 8x downscale, so both are corrected here
rather than accepted.
"""
import sys, os
import numpy as np
from PIL import Image

SRC = r"D:/Games/Blizzard/World of Warcraft/_retail_/Interface/AddOns/Tribunal/Art/source"
DST = os.path.join(SRC, "final")
os.makedirs(DST, exist_ok=True)

GOLD = (0xE8, 0xB2, 0x3A)
GOLD_LIGHT = (0xFF, 0xD9, 0x8A)
CRIMSON = (0xC4, 0x38, 0x3A)
CRIMSON_DEEP = (0x8A, 0x24, 0x28)


def load(name):
    return np.asarray(Image.open(os.path.join(SRC, name)).convert("RGBA"), float)


def trim(a, thresh=6):
    m = a[..., 3] > thresh
    if not m.any():
        return a
    ys, xs = np.where(m)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def fit(a, inner, canvas):
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    s = min(inner / im.width, inner / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(im, ((canvas - im.width) // 2, (canvas - im.height) // 2))
    return np.asarray(out, float)


def gain(a, k, floor=0.0):
    """Restore linework eaten by the downscale, then clean up the dust."""
    al = a[..., 3] / 255.0
    al = np.clip(al * k, 0, 1)
    al[al < floor] = 0.0
    a[..., 3] = al * 255
    return a


def flat(a, rgb):
    """Force a single exact palette color; keeps alpha, kills color fringing."""
    a[..., 0], a[..., 1], a[..., 2] = rgb
    return a


def save(a, name):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(DST, name))
    print("  ->", name, a.shape[1], "x", a.shape[0])


def do_gold(src, out, canvas, inner, k=1.0, floor=0.0):
    a = trim(load(src))
    a = fit(a, inner, canvas)
    a = gain(a, k, floor)
    save(flat(a, GOLD), out)


def do_seal(src, out, canvas=256, inner=252):
    a = trim(load(src))
    a = fit(a, inner, canvas)
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(2), rgb.min(2)
    lum = rgb @ [0.299, 0.587, 0.114]
    # gold ring: yellow-ish (green channel high relative to blue) and bright
    ring = (rgb[..., 1] > rgb[..., 2] + 55) & (lum > 120)
    solid = (al > 200) & (~ring)
    # The wax body is by far the most common value; the pressed glyph is
    # whatever sits meaningfully below it. Absolute thresholds fail here
    # because the whole seal is dark.
    base = np.median(lum[solid]) if solid.any() else 85.0
    dark = (~ring) & (lum < base - 6)
    body = (~ring) & (~dark)
    print("     wax luma base %.1f, glyph px %.1f%%" % (base, 100 * dark[al > 200].mean()))
    out_rgb = np.zeros_like(rgb)
    out_rgb[body] = CRIMSON
    out_rgb[dark] = CRIMSON_DEEP
    out_rgb[ring] = GOLD
    a[..., :3] = out_rgb
    a[..., 3] = al
    save(a, out)


def do_rays(src, out, canvas=256):
    a = load(src)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize((canvas, canvas), Image.LANCZOS)
    a = np.asarray(im, float).copy()
    a = gain(a, 1.25, 0.012)
    # guarantee a truly hollow centre
    y, x = np.mgrid[0:canvas, 0:canvas].astype(float)
    r = np.hypot(x - (canvas - 1) / 2, y - (canvas - 1) / 2) / (canvas / 2)
    a[..., 3] *= np.clip((r - 0.10) / 0.06, 0, 1)
    save(flat(a, GOLD_LIGHT), out)


if __name__ == "__main__":
    for job in sys.argv[1:]:
        print(job)
        if job == "emblem":
            do_gold("emblem_v2.png", "Emblem.png", 256, 238, k=1.05)
        elif job == "minimap":
            do_gold("minimap.png", "MinimapIcon.png", 64, 60, k=1.30, floor=0.02)
        elif job == "laurel":
            do_gold("laurel.png", "Laurel.png", 128, 124, k=2.30, floor=0.02)
        elif job == "seal":
            do_seal("seal.png", "Seal.png")
        elif job == "rays_gen":
            do_rays("rays_gen.png", "Rays.png")
        elif job == "rays_proc":
            do_rays("rays_proc.png", "Rays.png")
