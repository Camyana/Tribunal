"""Procedural Tribunal art assets — the ones that are pure geometry/math.

A generative model cannot make a genuinely seamless tile, a band-free gaussian,
or a pixel-exact 1px hairline. These are authored to spec instead.
"""
import numpy as np
from PIL import Image, ImageDraw
import os

OUT = r"D:/Games/Blizzard/World of Warcraft/_retail_/Interface/AddOns/Tribunal/Art/source"
os.makedirs(OUT, exist_ok=True)

GOLD = (232, 178, 58)        # #E8B23A
GOLD_LIGHT = (255, 217, 138)  # #FFD98A
VOID = np.array([0x0B, 0x0D, 0x12], float)   # #0B0D12
PANEL = np.array([0x12, 0x15, 0x1D], float)  # #12151D


def save(arr, path):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(path)
    print("wrote", path)


# ---------------------------------------------------------------- PanelTile
def panel_tile(N=512):
    rng = np.random.default_rng(7)
    y, x = np.mgrid[0:N, 0:N].astype(float)

    # Low-frequency mottle: white noise low-passed in the Fourier domain, which
    # is periodic by construction -> tiles seamlessly.
    def periodic_noise(sigma_px):
        f = np.fft.fft2(rng.standard_normal((N, N)))
        fy = np.fft.fftfreq(N)[:, None]
        fx = np.fft.fftfreq(N)[None, :]
        g = np.exp(-2 * (np.pi * sigma_px) ** 2 * (fx ** 2 + fy ** 2))
        n = np.real(np.fft.ifft2(f * g))
        return n / (np.abs(n).max() + 1e-9)

    mottle = periodic_noise(9.0) * 0.55 + periodic_noise(28.0) * 0.45
    mottle /= np.abs(mottle).max()

    # Diagonal striation. Integer cycle count over the tile -> wraps in x and y.
    stri = np.sin(2 * np.pi * 23 * (x + y) / N)
    stri = stri * 0.55 + np.sin(2 * np.pi * 61 * (x + y) / N) * 0.45

    # Per-pixel grain is inherently seamless.
    grain = rng.standard_normal((N, N))

    # Weights are tiny on purpose: this must read as surface, not as pattern.
    L = 0.5 + 0.30 * mottle + 0.055 * stri + 0.075 * grain
    L = np.clip(L, 0.0, 1.0)

    rgb = VOID[None, None, :] + (PANEL - VOID)[None, None, :] * L[:, :, None]
    # Dither below the quantisation step so the ramp cannot band.
    rgb = rgb + rng.uniform(-0.5, 0.5, rgb.shape)
    out = np.zeros((N, N, 4))
    out[..., :3] = rgb
    out[..., 3] = 255
    save(out, f"{OUT}/paneltile.png")


# -------------------------------------------------------------------- Bloom
def bloom(N=512):
    rng = np.random.default_rng(3)
    c = (N - 1) / 2.0
    y, x = np.mgrid[0:N, 0:N].astype(float)
    r = np.hypot(x - c, y - c) / (N / 2.0)

    k = 5.0
    a = np.exp(-k * r ** 2)
    a = (a - np.exp(-k)) / (1.0 - np.exp(-k))   # exactly 0 at r == 1
    a = np.where(r >= 1.0, 0.0, a)
    # soften the very last stretch so the disc edge is invisible
    a *= np.clip((1.0 - r) / 0.18, 0, 1) ** 2

    out = np.zeros((N, N, 4))
    out[..., 0], out[..., 1], out[..., 2] = GOLD_LIGHT
    out[..., 3] = a * 255 + rng.uniform(-0.5, 0.5, a.shape)
    save(out, f"{OUT}/bloom.png")


# ------------------------------------------------------------------ Divider
def divider(W=256, H=32):
    out = np.zeros((H, W, 4))
    out[..., 0], out[..., 1], out[..., 2] = GOLD

    t = np.linspace(0.0, 1.0, W)
    prof = np.sin(np.pi * t) ** 0.75          # fades to nothing at both ends
    prof *= np.clip((0.5 - np.abs(t - 0.5)) / 0.06, 0, 1)  # hard zero at tips
    out[H // 2, :, 3] = prof * 205

    # Solid diamond, centre. Supersampled for clean diagonals.
    S = 8
    R = 6                                     # half-diagonal, final pixels
    d = Image.new("L", (W * S, H * S), 0)
    dd = ImageDraw.Draw(d)
    cx, cy = (W / 2.0) * S, (H / 2.0) * S
    dd.polygon([(cx, cy - R * S), (cx + R * S, cy), (cx, cy + R * S), (cx - R * S, cy)], fill=255)
    dia = np.asarray(d.resize((W, H), Image.LANCZOS), float)
    out[..., 3] = np.maximum(out[..., 3], dia)
    save(out, f"{OUT}/divider.png")


# ------------------------------------------------------------------- Corner
def corner(N=64):
    out = np.zeros((N, N, 4))
    out[..., 0], out[..., 1], out[..., 2] = GOLD

    INSET, END = 5, 56
    t = np.arange(N, dtype=float)
    # 1.0 at the vertex, tapering away to nothing at the far end
    fade = np.clip(1.0 - (t - INSET) / (END - INSET), 0, 1) ** 1.7
    fade[:INSET] = 0.0
    fade[END:] = 0.0
    a = fade * 230

    out[INSET, :, 3] = np.maximum(out[INSET, :, 3], a)   # horizontal arm
    out[:, INSET, 3] = np.maximum(out[:, INSET, 3], a)   # vertical arm

    # Tiny solid square notch at the vertex.
    out[INSET - 1:INSET + 2, INSET - 1:INSET + 2, 3] = 255
    save(out, f"{OUT}/corner.png")


# --------------------------------------------------------- Rays (fallback)
def rays(N=1024, spokes=16):
    S = 4
    M = N * S
    img = Image.new("L", (M, M), 0)
    dr = ImageDraw.Draw(img)
    c = M / 2.0
    r0 = M * 0.115                     # hollow centre
    for i in range(spokes):
        ang = 2 * np.pi * i / spokes - np.pi / 2
        long = (i % 2 == 0)
        r1 = M * (0.482 if long else 0.290)
        half = np.deg2rad(3.8 if long else 2.4)
        p = [(c + r0 * np.cos(ang - half), c + r0 * np.sin(ang - half)),
             (c + r1 * np.cos(ang), c + r1 * np.sin(ang)),
             (c + r0 * np.cos(ang + half), c + r0 * np.sin(ang + half))]
        dr.polygon(p, fill=255)
    mask = np.asarray(img.resize((N, N), Image.LANCZOS), float)

    y, x = np.mgrid[0:N, 0:N].astype(float)
    r = np.hypot(x - (N - 1) / 2, y - (N - 1) / 2) / (N / 2.0)
    falloff = np.clip((1.0 - r / 0.98), 0, 1) ** 1.25
    inner = np.clip((r - 0.115) / 0.075, 0, 1)      # transparent hollow core
    a = mask * falloff * inner * 0.88

    out = np.zeros((N, N, 4))
    out[..., 0], out[..., 1], out[..., 2] = GOLD_LIGHT
    out[..., 3] = a
    save(out, f"{OUT}/rays_proc.png")


rays()
