"""Hand-authored 64px minimap glyph: the emblem reduced to four shapes.

Every feature is >= 6px in the 64 canvas so it survives the 3.2x squeeze down
to a 20px minimap button without any two elements merging.
"""
from PIL import Image, ImageDraw
import numpy as np

N, S = 64, 8
GOLD = (0xE8, 0xB2, 0x3A)

img = Image.new("L", (N * S, N * S), 0)
d = ImageDraw.Draw(img)
r = lambda box: d.rectangle([v * S for v in box], fill=255)
t = lambda pts: d.polygon([(x * S, y * S) for x, y in pts], fill=255)

r([12, 13, 52, 19])      # beam
r([29, 13, 35, 51])      # column
r([17, 45, 47, 51])      # base
t([(5, 25), (25, 25), (15, 36)])    # left pan
t([(39, 25), (59, 25), (49, 36)])   # right pan

a = np.asarray(img.resize((N, N), Image.LANCZOS), float)
out = np.zeros((N, N, 4))
out[..., 0], out[..., 1], out[..., 2] = GOLD
out[..., 3] = a
p = r"D:/Games/Blizzard/World of Warcraft/_retail_/Interface/AddOns/Tribunal/Art/source/final/MinimapIcon_geo.png"
Image.fromarray(out.astype(np.uint8)).save(p)
print(p)
