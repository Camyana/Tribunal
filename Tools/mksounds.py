"""Tribunal - procedural sound design.
Low, ceremonial, sparse. Struck metal and deep wood.
"""
import os
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
OUT = r"D:\Games\Blizzard\World of Warcraft\_retail_\Interface\AddOns\Tribunal\Media\Sounds"
os.makedirs(OUT, exist_ok=True)

rng = np.random.default_rng(20260819)


# ---------------------------------------------------------------- helpers
def ns(sec):
    return int(round(sec * SR))


def tt(n):
    return np.arange(n) / SR


def strike_env(n, tau, attack=0.0015, start=0.0):
    """Percussive envelope: fast raised-cosine attack, exponential decay."""
    x = tt(n)
    e = np.exp(-np.maximum(x - start, 0.0) / tau)
    e[x < start] = 0.0
    a = ns(attack)
    i0 = ns(start)
    if a > 1:
        ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
        end = min(i0 + a, n)
        e[i0:end] *= ramp[: end - i0]
    return e


def mode(n, f, tau, amp=1.0, phase=0.0, start=0.0, detune=0.0, attack=0.0015):
    """A single damped sinusoidal mode, optionally with a beating twin."""
    x = tt(n) - start
    e = strike_env(n, tau, attack, start)
    y = np.sin(2 * np.pi * f * np.maximum(x, 0) + phase)
    if detune:
        y = 0.62 * y + 0.38 * np.sin(2 * np.pi * (f + detune) * np.maximum(x, 0) + phase + 1.07)
    return amp * y * e


def bp(x, lo, hi, order=2):
    lo = max(lo, 20.0)
    hi = min(hi, SR / 2 - 200.0)
    sos = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    sos = signal.butter(order, min(f, SR / 2 - 200) / (SR / 2), btype="low", output="sos")
    return signal.sosfilt(sos, x)


def hp(x, f, order=2):
    sos = signal.butter(order, max(f, 15) / (SR / 2), btype="high", output="sos")
    return signal.sosfilt(sos, x)


def clp(x, f, order=2):
    """Circular lowpass: a causal IIR run over a finite buffer leaves a
    start-up transient that would break the Chamber loop, so filter three
    tiled copies and keep the middle one - that copy is in steady state and
    is exactly periodic."""
    sos = signal.butter(order, min(f, SR / 2 - 200) / (SR / 2), btype="low", output="sos")
    n = len(x)
    y = signal.sosfilt(sos, np.tile(x, 3))
    return y[n:2 * n]


def comb(x, delay_s, fb=0.85):
    """Feedback comb -> metallic resonance at 1/delay Hz."""
    d = max(2, ns(delay_s))
    a = np.zeros(d + 1)
    a[0] = 1.0
    a[d] = -fb
    return signal.lfilter([1.0], a, x)


def stone_ir(dur, decay, lo=140, hi=5200, predelay=0.010, seed=1, refl=True):
    """Synthetic impulse response for a hard stone room."""
    r = np.random.default_rng(seed)
    n = ns(dur)
    x = tt(n)
    ir = r.standard_normal(n) * np.exp(-x / decay)
    ir *= (0.35 + 0.65 * np.minimum(x / 0.06, 1.0))  # build-up, not an instant wall
    ir = bp(ir, lo, hi)
    if refl:
        for d, g in ((0.017, 0.55), (0.029, -0.42), (0.041, 0.33), (0.063, -0.24)):
            i = ns(d)
            if i < n:
                ir[i] += g
    ir[: ns(predelay)] = 0.0
    ir /= np.max(np.abs(ir)) + 1e-12
    return ir


def reverb(dry, dur, decay, wet=0.3, lo=140, hi=5200, predelay=0.010, seeds=(11, 12)):
    """Returns stereo (n,2) of dry + decorrelated stone reverb."""
    n = len(dry)
    out = np.zeros((n, 2))
    for c, s in enumerate(seeds):
        ir = stone_ir(dur, decay, lo, hi, predelay + c * 0.003, seed=s)
        w = signal.fftconvolve(dry, ir)[:n]
        w /= np.max(np.abs(w)) + 1e-12
        out[:, c] = dry + wet * w
    return out


def to_stereo(x, width=0.0):
    if x.ndim == 2:
        return x
    if width <= 0:
        return np.stack([x, x], axis=1)
    d = ns(width)
    l = x.copy()
    r = np.concatenate([np.zeros(d), x[:-d]]) if d else x.copy()
    return np.stack([l, r], axis=1)


def trim_head(x, thresh_db=-70.0, guard_ms=0.5):
    """Strip any leading silence, leaving a sub-millisecond guard."""
    m = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    peak = m.max()
    if peak <= 0:
        return x
    idx = np.argmax(m > peak * (10 ** (thresh_db / 20)))
    idx = max(0, idx - ns(guard_ms / 1000.0))
    return x[idx:]


def fade_out(x, ms):
    k = ns(ms / 1000.0)
    if k < 2 or k > len(x):
        return x
    r = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    if x.ndim == 2:
        x[-k:] *= r[:, None]
    else:
        x[-k:] *= r
    return x


def fade_in(x, ms):
    k = ns(ms / 1000.0)
    if k < 2 or k > len(x):
        return x
    r = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, k))
    if x.ndim == 2:
        x[:k] *= r[:, None]
    else:
        x[:k] *= r
    return x


def norm(x, peak_db):
    p = np.max(np.abs(x))
    if p <= 0:
        return x
    return x * (10 ** (peak_db / 20.0)) / p


def fit(x, dur):
    n = ns(dur)
    if len(x) > n:
        x = x[:n]
    elif len(x) < n:
        pad = n - len(x)
        z = np.zeros((pad, x.shape[1])) if x.ndim == 2 else np.zeros(pad)
        x = np.concatenate([x, z])
    return x


def write_ogg(path, x, sr=SR):
    """libsndfile's vorbis encoder crashes on a single very large write
    (>~10s), so stream the data in chunks."""
    x = np.ascontiguousarray(x.astype(np.float32))
    ch = 1 if x.ndim == 1 else x.shape[1]
    chunk = SR * 2
    with sf.SoundFile(path, "w", samplerate=sr, channels=ch,
                      format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), chunk):
            f.write(x[i:i + chunk])


def encode_to_peak(path, x, peak_db, passes=5, tol=0.15):
    """Vorbis is lossy, so the decoded peak drifts off the target.
    Encode, measure what actually comes back, correct the gain, repeat."""
    g = 1.0
    for _ in range(passes):
        y = np.clip(norm(x, peak_db) * g, -0.999, 0.999)
        write_ogg(path, y)
        d, _ = sf.read(path, always_2d=True)
        got = 20 * np.log10(max(np.max(np.abs(d)), 1e-12))
        err = peak_db - got
        if abs(err) <= tol:
            return got
        g *= 10 ** (err / 20.0)
    return got


def save(name, x, peak_db, dur, tail_ms=25):
    x = trim_head(x)
    x = fit(x, dur)
    x = fade_out(x, tail_ms)
    got = encode_to_peak(os.path.join(OUT, name), x, peak_db)
    print(f"  wrote {name}  (decoded peak {got:.2f} dBFS)")


# ================================================================ 1. CourtCalled
def court_called():
    """Hard gavel strike on wood + low resonant swell rising underneath."""
    dur = 1.6
    n = ns(dur + 0.35)
    x = tt(n)

    # --- the crack: broadband transient
    crack = rng.standard_normal(n) * strike_env(n, 0.0035, attack=0.0004)
    crack = bp(crack, 900, 7000) * 0.55
    crack += bp(rng.standard_normal(n) * strike_env(n, 0.0012, attack=0.0002), 3000, 11000) * 0.30

    # --- the wood body: inharmonic modes of a dense hardwood block
    body = np.zeros(n)
    wood = [
        (96.0, 0.115, 0.55), (181.0, 0.095, 0.78), (327.0, 0.072, 0.90),
        (521.0, 0.055, 0.74), (742.0, 0.040, 0.54), (1103.0, 0.030, 0.38),
        (1607.0, 0.021, 0.26), (2311.0, 0.014, 0.17), (3390.0, 0.009, 0.10),
    ]
    for f, tau, a in wood:
        body += mode(n, f, tau, a, phase=rng.uniform(0, 6.28), detune=f * 0.004, attack=0.0008)
    body = lp(body, 6500)

    # a second micro-impact 11ms later: the head settling on the block
    sec = np.zeros(n)
    for f, tau, a in wood[:5]:
        sec += mode(n, f * 1.02, tau * 0.45, a * 0.28, start=0.011, attack=0.0006)
    body += sec

    gavel = 0.9 * body + 0.95 * crack
    gavel /= np.max(np.abs(gavel))

    # --- the swell: low resonance rising under the strike, room going quiet
    swell_env = np.clip(x / 0.62, 0, 1) ** 1.6 * np.exp(-np.maximum(x - 0.62, 0) / 0.42)
    glide = 46.5 * (1.0 + 0.13 * np.clip(x / 0.9, 0, 1))
    ph = 2 * np.pi * np.cumsum(glide) / SR
    swell = (np.sin(ph) + 0.42 * np.sin(2 * ph + 0.6) + 0.20 * np.sin(3 * ph + 1.9)
             + 0.10 * np.sin(4.5 * ph + 2.7))
    swell *= swell_env
    swell = lp(swell, 420)

    # a breath of air riding the swell, so it reads as a room and not a tone
    air = bp(rng.standard_normal(n), 180, 1400) * swell_env * 0.10
    swell = swell * 0.72 + air

    dry = gavel * 1.00 + swell * 0.30
    out = reverb(dry, 1.0, 0.34, wet=0.26, lo=180, hi=4800, predelay=0.012)
    # keep the low swell centred and mono-solid
    out += to_stereo(swell * 0.11)
    return out, dur


# ================================================================ 2. BallotCast
def ballot_cast():
    """Soft muted wooden tap. Dry, close, a token set down on stone."""
    dur = 0.18
    n = ns(dur)

    tap = np.zeros(n)
    for f, tau, a in [(212.0, 0.045, 0.85), (398.0, 0.033, 1.00), (713.0, 0.022, 0.55),
                      (1094.0, 0.014, 0.28), (1580.0, 0.009, 0.14)]:
        tap += mode(n, f, tau, a, phase=rng.uniform(0, 6.28), detune=f * 0.003, attack=0.0012)

    # contact noise: felt-muted, no bright edge
    click = rng.standard_normal(n) * strike_env(n, 0.0022, attack=0.0004)
    click = bp(click, 500, 3200) * 0.28

    dry = tap * 0.9 + click
    dry = lp(dry, 3800)
    # a hair of body under it - the stone it lands on
    dry += mode(n, 84.0, 0.030, 0.30, attack=0.0015)
    return to_stereo(dry), dur


# ================================================================ 3. Tick
def tick():
    """Very quiet high metallic tick. Must survive five in a row."""
    dur = 0.09
    n = ns(dur)

    t_ = np.zeros(n)
    for f, tau, a in [(3980.0, 0.016, 0.55), (5460.0, 0.011, 1.00),
                      (7310.0, 0.007, 0.45), (9420.0, 0.004, 0.18)]:
        t_ += mode(n, f, tau, a, phase=rng.uniform(0, 6.28), detune=f * 0.002, attack=0.0006)

    n_ = rng.standard_normal(n) * strike_env(n, 0.0018, attack=0.0004)
    n_ = bp(n_, 3200, 9000) * 0.30

    dry = t_ * 0.8 + n_
    dry = lp(dry, 11000, order=3)   # take the glass off the top
    dry = hp(dry, 1400)             # nothing down low, it must not thud
    # micro tail so it reads as metal, not a plosive
    dry += mode(n, 2740.0, 0.024, 0.10, attack=0.001)
    return dry, dur


# ================================================================ 4. Verdict
def verdict():
    """Deep struck bronze bell, shimmering decay, slow rising harmonic beneath."""
    dur = 2.5
    n = ns(dur + 0.4)
    x = tt(n)

    prime = 98.0  # G2
    # classic bell partial series (hum, prime, tierce, quint, nominal, upper)
    partials = [
        (0.500, 2.60, 0.78), (1.000, 2.20, 1.00), (1.183, 1.70, 0.72),
        (1.506, 1.45, 0.66), (2.000, 1.30, 0.86), (2.514, 1.00, 0.56),
        (3.011, 0.85, 0.62), (4.166, 0.62, 0.46), (5.433, 0.48, 0.36),
        (6.796, 0.36, 0.27), (8.210, 0.28, 0.20), (10.34, 0.21, 0.14),
        (12.87, 0.15, 0.09), (15.62, 0.11, 0.06),
    ]
    bell = np.zeros(n)
    for r, tau, a in partials:
        f = prime * r
        beat = 0.35 + 0.9 * r   # higher partials shimmer faster
        bell += mode(n, f, tau, a, phase=rng.uniform(0, 6.28), detune=beat, attack=0.002)

    # strike transient: the clapper on bronze
    strike = rng.standard_normal(n) * strike_env(n, 0.006, attack=0.0004)
    strike = bp(strike, 1200, 8000) * 0.45
    strike += bp(rng.standard_normal(n) * strike_env(n, 0.0018, attack=0.0002), 4000, 12000) * 0.22

    bell = bell / np.max(np.abs(bell))
    bell = bell * 0.88 + strike * 0.52

    # --- the rising harmonic underneath: slow, ominous, tightening
    rise = np.clip(x / 1.9, 0, 1) ** 1.35
    sub = np.zeros(n)
    for f, a, dt in [(49.0, 1.00, 0.11), (73.5, 0.52, 0.17), (98.0, 0.34, 0.23),
                     (147.0, 0.16, 0.31)]:
        sub += a * (np.sin(2 * np.pi * f * x) + 0.5 * np.sin(2 * np.pi * (f + dt) * x + 1.3))
    # the touch of ominous: a quiet tritone creeping in late
    sub += 0.14 * np.sin(2 * np.pi * 138.6 * x) * np.clip((x - 0.7) / 1.3, 0, 1)
    sub *= rise
    sub = lp(sub, 520)
    sub /= np.max(np.abs(sub)) + 1e-12

    dry = bell * 1.00 + sub * 0.26
    out = reverb(dry, 1.9, 0.62, wet=0.34, lo=160, hi=6000, predelay=0.016, seeds=(21, 22))
    out += to_stereo(sub * 0.08)
    return out, dur


# ================================================================ 5. Guilty
def guilty():
    """Low crimson impact. Dark sub hit, short metallic scrape on top. Final."""
    dur = 1.2
    n = ns(dur + 0.2)
    x = tt(n)

    # --- sub: pitch collapsing from a punch into a floor
    fsweep = 38.0 + 62.0 * np.exp(-x / 0.055)
    ph = 2 * np.pi * np.cumsum(fsweep) / SR
    sub = np.sin(ph) * strike_env(n, 0.30, attack=0.003)
    sub = np.tanh(sub * 1.7) / np.tanh(1.7)      # weight, not distortion
    sub += 0.35 * np.sin(2 * ph) * strike_env(n, 0.11, attack=0.003)
    sub = lp(sub, 240)

    # --- impact body: dull mass landing
    body = rng.standard_normal(n) * strike_env(n, 0.045, attack=0.001)
    body = lp(bp(body, 70, 900), 1100) * 0.7
    for f, tau, a in [(112.0, 0.16, 0.5), (167.0, 0.10, 0.3), (263.0, 0.06, 0.2)]:
        body += mode(n, f, tau, a, attack=0.0012)

    # --- metallic scrape across the top
    sc_n = ns(0.20)
    scr = rng.standard_normal(n)
    scr = bp(scr, 1800, 6200)
    scr = comb(scr, 1.0 / 1290.0, fb=0.80)       # rings around 1.3k, dry metal
    scr = comb(scr, 1.0 / 2170.0, fb=0.62)
    rough = 1.0 + 0.55 * np.sin(2 * np.pi * 47.0 * x + 1.1) * np.sin(2 * np.pi * 113.0 * x)
    env = np.zeros(n)
    e = np.linspace(0, 1, sc_n)
    env[:sc_n] = np.sin(np.pi * e ** 0.55) * np.exp(-e * 2.2)
    scr = scr * env * rough
    scr = hp(scr, 1500)
    scr /= np.max(np.abs(scr)) + 1e-12

    dry = sub * 0.95 + body * 0.45 + scr * 0.44
    out = reverb(dry, 0.75, 0.24, wet=0.20, lo=200, hi=5000, predelay=0.008, seeds=(31, 32))
    out += to_stereo(sub * 0.30)   # keep the low end anchored dead centre
    return out, dur


# ================================================================ 6. Drawer
def drawer():
    """Tiny precise mechanical slide, then a latch."""
    dur = 0.16
    n = ns(dur)
    x = tt(n)

    # --- slide: fine-grained friction, quiet and short
    sl_n = ns(0.088)
    sl = rng.standard_normal(n)
    sl = bp(sl, 1600, 5200)
    sl = comb(sl, 1.0 / 3300.0, fb=0.45)
    env = np.zeros(n)
    e = np.linspace(0, 1, sl_n)
    env[:sl_n] = np.sin(np.pi * e) ** 1.3
    sl = sl * env * 0.30

    # --- latch: two small metal parts meeting, at 92ms
    latch = np.zeros(n)
    for f, tau, a in [(2380.0, 0.013, 0.85), (3610.0, 0.009, 1.00),
                      (5240.0, 0.005, 0.45), (1420.0, 0.018, 0.35)]:
        latch += mode(n, f, tau, a, start=0.092, detune=f * 0.002, attack=0.0004)
    lc = rng.standard_normal(n) * strike_env(n, 0.0016, attack=0.0003, start=0.092)
    latch += bp(lc, 2200, 8000) * 0.40
    latch /= np.max(np.abs(latch)) + 1e-12

    dry = sl * 0.55 + latch * 0.9
    dry = hp(dry, 900)
    dry = lp(dry, 9500, order=3)
    return to_stereo(dry, width=0.0009), dur


# ================================================================ 7. Chamber
def chamber():
    """24s seamless stone-room drone.

    Every component is exactly periodic over the 24s loop:
      - partials snapped to the 1/24 Hz grid
      - LFOs snapped to the same grid
      - noise beds built by inverse FFT of a 24s spectrum (inherently circular)
    So the loop point is mathematically continuous - no crossfade seam at all.
    """
    L = 24.0
    n = ns(L)
    x = tt(n)
    grid = 1.0 / L

    def snap(f):
        return max(round(f / grid), 1) * grid

    def spectral_noise(shape, seed):
        r = np.random.default_rng(seed)
        f = np.fft.rfftfreq(n, 1 / SR)
        mag = shape(f)
        spec = mag * np.exp(1j * r.uniform(0, 2 * np.pi, len(f)))
        spec[0] = 0.0
        spec[-1] = np.abs(spec[-1])
        y = np.fft.irfft(spec, n)
        return y / (np.max(np.abs(y)) + 1e-12)

    def lfo(period, phase=0.0, depth=0.5, centre=0.5):
        f = snap(1.0 / period)
        return centre + depth * np.sin(2 * np.pi * f * x + phase)

    # --- drone: a low D-ish stack, detuned into a slow beat
    drone = np.zeros(n)
    stack = [
        (36.75, 1.00, 0.09),   # fundamental
        (55.10, 0.46, 0.13),   # fifth
        (73.50, 0.30, 0.17),   # octave
        (110.2, 0.14, 0.21),   # twelfth
        (147.0, 0.07, 0.27),
    ]
    for f, a, beat in stack:
        f0, f1 = snap(f), snap(f + beat)
        drone += a * (np.sin(2 * np.pi * f0 * x + f) + 0.62 * np.sin(2 * np.pi * f1 * x + f * 1.7))

    # the tension: a quiet flattened fifth breathing in and out over 24s
    tense = (np.sin(2 * np.pi * snap(51.9) * x) + 0.5 * np.sin(2 * np.pi * snap(103.8) * x + 2.0))
    drone += 0.11 * tense * lfo(24.0, phase=-1.2, depth=0.5, centre=0.5)

    drone = clp(drone, 300, order=2)
    drone /= np.max(np.abs(drone)) + 1e-12

    # --- room tone: two static noise beds crossfaded by slow LFOs
    def stone_shape(f):
        base = 1.0 / (1.0 + (f / 240.0) ** 2.1)
        res = 1.0 + 0.9 / (1.0 + ((f - 165.0) / 55.0) ** 2)
        res += 0.5 / (1.0 + ((f - 430.0) / 130.0) ** 2)
        hpf = (f / 45.0) ** 2 / (1.0 + (f / 45.0) ** 2)
        return base * res * hpf

    def air_shape(f):
        return (1.0 / (1.0 + (f / 2600.0) ** 2.4)) * ((f / 900.0) ** 2 / (1.0 + (f / 900.0) ** 2)) * 0.28

    beds = []
    for c, (s1, s2, s3) in enumerate([(101, 103, 105), (202, 204, 206)]):
        a = spectral_noise(stone_shape, s1)
        b = spectral_noise(stone_shape, s2)
        m = lfo(12.0, phase=c * 1.9, depth=0.5, centre=0.5)
        bed = a * m + b * (1.0 - m)
        # distant swell: the room breathing, period divides the loop
        bed *= 0.62 + 0.38 * lfo(8.0, phase=c * 2.4 + 0.7, depth=1.0, centre=0.0) ** 2
        air = spectral_noise(air_shape, s3)
        air *= 0.5 + 0.5 * lfo(24.0, phase=c * 3.1, depth=1.0, centre=0.0) ** 2
        beds.append(bed * 0.88 + air * 0.20)

    # --- distant events -----------------------------------------------------
    # Everything above is periodic LFOs, which on their own read as hum plus
    # hiss rather than a room. These give the ear something to catch. Each one
    # starts and fully decays inside the 24s window, so the loop stays exactly
    # periodic - no wrapping, no crossfade.
    def settle(at, freq, tau, amp, bright, seed, pan):
        # Built at t=0 in an oversized buffer, folded back onto itself, then
        # rolled into place. Folding rather than truncating is what keeps the
        # loop exactly periodic: an event near the end wraps into the start
        # instead of being cut off at the boundary.
        tail = 3.0
        m = ns(tau * 6.0 + tail)
        k = np.arange(m) / SR

        body = np.sin(2 * np.pi * freq * k) + 0.5 * np.sin(2 * np.pi * freq * 2.01 * k + 1.1)
        body += 0.22 * np.sin(2 * np.pi * freq * 3.03 * k + 2.3)
        r = np.random.default_rng(seed)
        grit = bp(r.standard_normal(m), freq * 0.8, freq * 6.0) * np.exp(-k / 0.05)
        sig = lp((body * np.exp(-k / tau) + 0.35 * grit) * amp, bright)

        # reverb() returns dry + wet, so subtract the dry back out to get the
        # reflections on their own. Far away means mostly reflection: mixing
        # reverb()'s output directly would leave the direct sound at full
        # level and the event would land close and dry instead of distant.
        wet = reverb(sig, tail, decay=2.2, wet=1.0, lo=110, hi=3200,
                     seeds=(seed + 1, seed + 2))
        reflections = (wet[:, 0] if wet.ndim > 1 else wet) - sig[:len(wet)]
        mix = 0.12 * sig[:len(reflections)] + 0.88 * reflections

        folded = np.zeros(n)
        for i in range(0, len(mix), n):
            chunk = mix[i:i + n]
            folded[:len(chunk)] += chunk
        folded = np.roll(folded, ns(at))
        return folded * (1.0 - pan), folded * pan

    ev_l = np.zeros(n)
    ev_r = np.zeros(n)
    for at, freq, tau, amp, bright, seed, pan in (
        (5.20,  86.0, 1.45, 0.30, 900.0,  71, 0.30),   # something settles, low and left
        (11.90, 214.0, 0.85, 0.16, 1800.0, 83, 0.72),  # a far-off resonance answers
        (17.40, 61.0, 2.10, 0.24, 620.0,  97, 0.46),   # deep, almost subsonic
    ):
        l, r = settle(at, freq, tau, amp, bright, seed, pan)
        ev_l += l
        ev_r += r

    peak = max(np.max(np.abs(ev_l)), np.max(np.abs(ev_r)), 1e-12)
    ev_l /= peak
    ev_r /= peak

    out = np.zeros((n, 2))
    for c in range(2):
        # tiny inter-channel detune on the drone for width, still on the grid
        d = np.zeros(n)
        for f, a, beat in stack:
            f0 = snap(f + (grid if c else 0.0))
            d += a * np.sin(2 * np.pi * f0 * x + f + c * 0.9)
        d = clp(d, 300, order=2)
        d /= np.max(np.abs(d)) + 1e-12
        out[:, c] = (0.60 * drone + 0.22 * d + 0.42 * beds[c]
                     + 0.30 * (ev_l if c == 0 else ev_r))

    # Rotate the (exactly periodic) loop so it starts at its quietest moment.
    # Rotation preserves periodicity, and the addon re-triggers Chamber at
    # 23.5s without stopping the old handle, so the 0.5s overlap lands on the
    # softest part of the bed instead of a swell.
    env = np.sqrt(np.convolve(np.mean(out ** 2, axis=1),
                              np.ones(ns(0.5)) / ns(0.5), mode="same"))
    out = np.roll(out, -int(np.argmin(env)), axis=0)

    out /= np.max(np.abs(out)) + 1e-12
    return out, L


# ================================================================ run
if __name__ == "__main__":
    print("Tribunal sound design ->", OUT)

    x, d = court_called();  save("CourtCalled.ogg", x, -3.0, d, tail_ms=60)
    x, d = ballot_cast();   save("BallotCast.ogg", x, -12.0, d, tail_ms=18)
    x, d = tick();          save("Tick.ogg", x, -20.0, d, tail_ms=12)
    x, d = verdict();       save("Verdict.ogg", x, -3.0, d, tail_ms=90)
    x, d = guilty();        save("Guilty.ogg", x, -4.0, d, tail_ms=70)
    x, d = drawer();        save("Drawer.ogg", x, -16.0, d, tail_ms=14)

    # Chamber: no head-trim, no fades - the loop must stay mathematically closed
    x, d = chamber()
    x = norm(x, -18.0)
    write_ogg(os.path.join(OUT, "Chamber.ogg"), x)
    np.save(os.path.join(os.path.dirname(__file__), "chamber_ref.npy"), x.astype(np.float32))
    print("  wrote Chamber.ogg")
    print("done")
