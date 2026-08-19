#!/usr/bin/env python
"""Convert PNGs to WoW-compatible 32-bit uncompressed TGA textures.

WoW requires texture dimensions to be powers of two. Anything else is
silently rescaled by the client and looks soft, so we resize here where
we can control the filtering.

Usage:
    python png2tga.py <in.png> <out.tga> [WxH] [--fit contain|cover|stretch]
                                         [--trim] [--premul]
"""
import sys, os
from PIL import Image

POW2 = [8, 16, 32, 64, 128, 256, 512, 1024]


def nearest_pow2(n):
    return min(POW2, key=lambda p: abs(p - n))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) < 2:
        print(__doc__)
        return 1

    src, dst = args[0], args[1]
    im = Image.open(src).convert("RGBA")

    if "--trim" in flags:
        bbox = im.getchannel("A").getbbox()
        if bbox:
            im = im.crop(bbox)

    if len(args) >= 3:
        w, h = (int(x) for x in args[2].lower().split("x"))
    else:
        w, h = nearest_pow2(im.width), nearest_pow2(im.height)

    fit = "contain"
    for f in flags:
        if f.startswith("--fit"):
            fit = f.split("=", 1)[1] if "=" in f else fit
    if len(args) >= 4 and args[3] in ("contain", "cover", "stretch"):
        fit = args[3]

    if fit == "stretch":
        im = im.resize((w, h), Image.LANCZOS)
    else:
        scale = (max if fit == "cover" else min)(w / im.width, h / im.height)
        nw, nh = max(1, round(im.width * scale)), max(1, round(im.height * scale))
        im = im.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.paste(im, ((w - nw) // 2, (h - nh) // 2))
        im = canvas

    if "--premul" in flags:
        r, g, b, a = im.split()
        im = Image.merge("RGBA", (
            r.point(lambda v: v), g.point(lambda v: v), b.point(lambda v: v), a))

    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    # No RLE: WoW's TGA reader is happiest with plain uncompressed 32-bit.
    im.save(dst, format="TGA")
    print(f"{dst}  {w}x{h}  {os.path.getsize(dst)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
