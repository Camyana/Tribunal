"""Rework the texture set after the design review.

Three jobs:
  1. Strip baked-in colour from every vertex-coloured asset. They were authored
     already gold, and the Lua multiplies by gold again, which lands on a burnt
     #D37C0D instead of the palette's #E8B23A.
  2. Redraw Rays with real variation instead of 24 identical spokes.
  3. Re-author PanelTile with grain that is actually visible, at half the size.
"""
import numpy as np
from PIL import Image
import os

TEX = "Media/Textures"

# --- 1. luminance-only re-export -------------------------------------------
# Alpha already carries every edge and gradient in these, so the RGB plane is
# pure redundancy. White RGB makes SetVertexColor exact.
for name in ("Emblem", "MinimapIcon", "Divider", "Bloom"):
    p = os.path.join(TEX, name + ".tga")
    if not os.path.exists(p):
        continue
    im = np.asarray(Image.open(p).convert("RGBA")).copy()
    im[..., :3] = 255
    Image.fromarray(im, "RGBA").save(p, format="TGA")
    print(f"  {name:<12} -> white RGB, alpha preserved")


# --- 2. Rays ----------------------------------------------------------------
def rays(size=256, spokes=15, tiers=(1.0, 0.66, 0.42), core=0.17):
    y, x = np.mgrid[0:size, 0:size].astype(float)
    cx = cy = (size - 1) / 2
    dx, dy = x - cx, y - cy
    r = np.hypot(dx, dy) / (size / 2)
    th = np.arctan2(dy, dx) % (2 * np.pi)

    step = 2 * np.pi / spokes
    idx = np.floor(th / step).astype(int)
    length = np.take(np.array(tiers), idx % len(tiers))

    # Angular distance to this spoke's centreline.
    d = np.abs(((th - (idx + 0.5) * step + np.pi) % (2 * np.pi)) - np.pi)

    # The spoke narrows toward its tip, so it tapers instead of ending square.
    t = np.clip((r - core) / np.maximum(length - core, 1e-6), 0, 1)
    width = step * 0.30 * (1.0 - t) ** 0.85

    a = np.clip(1.0 - d / np.maximum(width, 1e-6), 0, 1) ** 1.4
    a *= 1.0 - t ** 1.6                      # fade along the ray
    a *= np.clip((r - core) / 0.10, 0, 1)    # hollow, softly entered
    a *= np.clip((1.0 - r) / 0.14, 0, 1)     # never touch the canvas edge
    a[r > 1.0] = 0

    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = np.clip(a * 235, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


rays().save(os.path.join(TEX, "Rays.tga"), format="TGA")
print("  Rays         -> 15 spokes, 3 length tiers, tapered, white RGB")


# --- 3. PanelTile -----------------------------------------------------------
def panel_tile(size=256, lo=(0x08, 0x0A, 0x0F), hi=(0x1C, 0x21, 0x2D)):
    """Seamless by construction: filtering in the Fourier domain keeps the
    result periodic, so the tile wraps with no seam at any size."""
    rng = np.random.default_rng(7)
    noise = rng.standard_normal((size, size))

    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    f = np.hypot(fy, fx)
    f[0, 0] = 1e-6

    # Band-limited: coarse enough to read as a surface, fine enough not to
    # become a pattern.
    band = np.exp(-((np.log(f / 0.115) ** 2) / 0.7))
    field = np.real(np.fft.ifft2(np.fft.fft2(noise) * band))
    field /= np.abs(field).max()

    # Integer-cycle striation so it also wraps.
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    striation = np.sin(2 * np.pi * (3 * xx + 3 * yy) / size) * 0.16

    v = np.clip(0.5 + 0.5 * (field * 1.15 + striation), 0, 1)

    lo_a, hi_a = np.array(lo, float), np.array(hi, float)
    rgb = lo_a + (hi_a - lo_a) * v[..., None]
    rgb += rng.uniform(-0.5, 0.5, rgb.shape)          # dither the quantisation

    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    return Image.fromarray(out, "RGBA")


tile = panel_tile()
tile.save(os.path.join(TEX, "PanelTile.tga"), format="TGA")

a = np.asarray(tile).astype(float)[..., :3]
luma = a @ [0.299, 0.587, 0.114]
GRAIN_ALPHA = 0.85   # must match Theme.lua
print(f"  PanelTile    -> 256px, luma sd {luma.std():.2f} levels; "
      f"{luma.std()*GRAIN_ALPHA:.2f} after the {GRAIN_ALPHA} blend in Theme.lua")
print(f"  tile mean    -> {tuple(round(v) for v in a.reshape(-1,3).mean(0))} "
      f"(panel token is (18,21,29), rows are (26,30,40))")

# Seam check: the wrap must not be more of a jump than the tile's own texture.
inner = np.abs(np.diff(luma, axis=1)).mean()
wrap = np.abs(luma[:, 0] - luma[:, -1]).mean()
print(f"  seam         -> wrap delta {wrap:.2f} vs interior {inner:.2f} "
      f"({'seamless' if wrap < inner * 2.5 else 'SEAM VISIBLE'})")

# --- 4. retire the two assets the review rejected ---------------------------
for name in ("Laurel", "Seal", "Corner"):
    p = os.path.join(TEX, name + ".tga")
    if os.path.exists(p):
        os.remove(p)
        print(f"  {name:<12} -> removed (review: drop / redraw in code)")


# --- 4. circle mask ---------------------------------------------------------
# Blizzard's Interface\CharacterFrame\TempPortraitAlphaMask is gone in 12.1,
# and every masked disc in the addon depended on it. Shipping our own removes
# the dependency on a file path that can vanish in any patch.
def circle_mask(size=256):
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    c = (size - 1) / 2.0
    r = np.hypot(xx - c, yy - c)
    edge = c - 0.5
    # One pixel of antialiasing at the rim, opaque everywhere inside.
    a = np.clip(edge - r + 0.5, 0.0, 1.0)
    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = np.clip(a * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


m = circle_mask()
m.save(os.path.join(TEX, "CircleMask.tga"), format="TGA")
a = np.asarray(m)
mid = a[a.shape[0] // 2, :, 3]
print(f"  CircleMask   -> 256px, alpha {a[...,3].min()}..{a[...,3].max()}, "
      f"corners {a[0,0,3]}, centre {a[128,128,3]}, "
      f"opaque span {int((mid > 127).sum())}/256 across the middle")
