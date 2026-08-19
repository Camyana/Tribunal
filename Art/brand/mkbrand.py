"""Build the CurseForge project avatar from the addon's own assets, so the
store page and the in-game UI are demonstrably the same mark and palette."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, os

TEX = "Media/Textures"
OUT = "Art/brand"
os.makedirs(OUT, exist_ok=True)

VOID   = (0x0B, 0x0D, 0x12)
PANEL  = (0x12, 0x15, 0x1D)
GOLD   = (0xE8, 0xB2, 0x3A)
GOLDLT = (0xFF, 0xD9, 0x8A)


def tint(img, rgb):
    """These assets are white + alpha; colour comes from the code in game and
    from here on the store page."""
    r, g, b, a = img.split()
    return Image.merge("RGBA", (r.point(lambda v: v * rgb[0] // 255),
                                g.point(lambda v: v * rgb[1] // 255),
                                b.point(lambda v: v * rgb[2] // 255), a))


def avatar(size=400):
    canvas = Image.new("RGBA", (size, size), PANEL + (255,))

    # The same seamless grain the panels use, at the same 0.85 blend.
    tile = Image.open(f"{TEX}/PanelTile.tga").convert("RGBA")
    grain = Image.new("RGBA", (size, size))
    for y in range(0, size, tile.height):
        for x in range(0, size, tile.width):
            grain.paste(tile, (x, y))
    canvas = Image.blend(canvas, grain, 0.85)

    # A vignette toward void at the edges, so the mark sits in a pool of light.
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    c = (size - 1) / 2
    r = np.hypot(xx - c, yy - c) / (size * 0.72)
    v = np.clip(r ** 1.8, 0, 1)
    base = np.asarray(canvas).astype(float)
    void = np.array(VOID, float)
    base[..., :3] = base[..., :3] * (1 - v[..., None]) + void * v[..., None]
    canvas = Image.fromarray(base.astype(np.uint8), "RGBA")

    bloom = tint(Image.open(f"{TEX}/Bloom.tga").convert("RGBA")
                 .resize((int(size * 0.85),) * 2, Image.LANCZOS), GOLDLT)
    bloom.putalpha(bloom.getchannel("A").point(lambda a: int(a * 0.42)))
    canvas.alpha_composite(bloom, ((size - bloom.width) // 2,) * 2)

    emblem = tint(Image.open(f"{TEX}/Emblem.tga").convert("RGBA")
                  .resize((int(size * 0.52),) * 2, Image.LANCZOS), GOLD)
    ex = (size - emblem.width) // 2
    canvas.alpha_composite(emblem, (ex, ex))

    # A hairline frame, inset on the 8px rhythm the UI uses.
    d = ImageDraw.Draw(canvas)
    inset = size // 25
    d.rectangle([inset, inset, size - inset - 1, size - inset - 1],
                outline=GOLD + (70,), width=max(1, size // 400))
    return canvas


for s in (400, 800):
    a = avatar(s)
    p = f"{OUT}/avatar-{s}.png"
    a.convert("RGB").save(p, "PNG", optimize=True)
    print(f"  {p}  {s}x{s}  {os.path.getsize(p)/1024:.0f} KB")
