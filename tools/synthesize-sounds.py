import numpy as np, wave, sys, os

# Usage:  python3 tools/synthesize-sounds.py <outdir>
# The looping beds ship as AAC, encoded exactly as the originals were:
#   afconvert -f m4af -d aac -b 128000 <name>.wav <name>.m4a
# rain.wav is generated but not shipped (cut in review).

SR = 44100
OUT = sys.argv[1]

def highpass(x, cutoff=45.0, order=4):
    # Remove sub-audible content before normalizing.
    #
    # The beds are 1/f^k spectra built over a 302-second window, so rfftfreq's
    # lowest bins sit at ~0.003 Hz and the 1/f gain there runs into the
    # hundreds. None of that is audible, and a phone speaker cannot move air
    # below ~40 Hz at all — but peak normalization still scaled the whole file
    # by those peaks, leaving the audible band 45 dB down. brown noise, fan and
    # wind shipped effectively silent on a phone: measured energy above 500 Hz
    # was -61, -60 and -65 dB against white noise's -19.
    #
    # The FFT treats the signal as periodic, which is exactly how it is played,
    # so this filter wraps around the loop seam instead of disturbing it.
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    gain = 1.0 / np.sqrt(1.0 + (cutoff / np.maximum(f, 1e-9)) ** (2 * order))
    return np.fft.irfft(spec * gain, n)

def write_wav(name, data):
    # normalize to -3 dBFS, 16-bit stereo
    data = highpass(data)
    data = data / np.max(np.abs(data)) * 0.7
    pcm = (data * 32767).astype(np.int16)
    stereo = np.column_stack([pcm, pcm]).ravel()
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(stereo.tobytes())
    print("wrote", name, len(data)/SR, "s")

def loopable(x, fade=2.0):
    # Crossfade tail into head so the file loops seamlessly.
    #
    # Equal-power (sin/cos), not linear: head and tail are independent noise, so
    # they sum as power rather than amplitude. A linear ramp puts both at 0.5 in
    # the middle, which lands at sqrt(0.5^2 + 0.5^2) = 0.707 — a 3 dB hole burned
    # into the first `fade` seconds of every file, audible as a dip on each loop.
    # sin^2 + cos^2 = 1 holds the power flat across the blend instead.
    #
    # Both curves start at (0, 1) and end at (1, 0), so x[0] still equals the
    # original x[-n] and the trimmed file remains sample-continuous end-to-start:
    # it butt-joins on repeat with no runtime crossfade needed.
    n = int(fade * SR)
    t = np.linspace(0, 1, n)
    x[:n] = x[:n] * np.sin(t * np.pi / 2) + x[-n:] * np.cos(t * np.pi / 2)
    return x[:-n]

rng = np.random.default_rng(20260730)
DUR = 302  # a shade over 5 min; loopable() trims the crossfade

# white: flat spectrum
white = rng.standard_normal(DUR * SR)
write_wav("white_noise.wav", loopable(white))

# pink: -3 dB/octave via FFT shaping (1/sqrt(f))
n = DUR * SR
spec = np.fft.rfft(rng.standard_normal(n))
f = np.fft.rfftfreq(n, 1/SR); f[0] = f[1]
pink = np.fft.irfft(spec / np.sqrt(f), n)
write_wav("pink_noise.wav", loopable(pink))

# brown: -6 dB/octave (1/f)
spec = np.fft.rfft(rng.standard_normal(n))
brown = np.fft.irfft(spec / f, n)
write_wav("brown_noise.wav", loopable(brown))

# ocean surf: band-limited noise with overlapping slow swells + gentle wash
t = np.arange(n) / SR
spec = np.fft.rfft(rng.standard_normal(n))
surf_base = np.fft.irfft(spec / (f ** 0.8), n)     # deep-ish noise bed
swell = np.zeros(n)
for period, phase, amp in [(11.3, 0.0, 1.0), (17.7, 2.1, 0.7), (7.9, 4.0, 0.45)]:
    s = np.sin(2 * np.pi * t / period + phase)
    swell += amp * np.clip(s, 0, None) ** 1.6        # waves break, then recede
ocean = surf_base * (0.25 + swell / swell.max() * 0.75)
write_wav("ocean_waves.wav", loopable(ocean))

# --- extended set (2026-07-30): more sleep sounds + alarm tones ---

# rain: dense random droplet impulses over a hiss bed (not shipped — cut in review)
drops = np.zeros(n)
idx = rng.integers(0, n - 40, size=int(DUR * 900))
for i in idx:
    drops[i:i+40] += rng.standard_normal(40) * np.exp(-np.arange(40) / 8) * rng.uniform(0.2, 1.0)
spec = np.fft.rfft(rng.standard_normal(n))
hiss = np.fft.irfft(spec / (f ** 0.35), n)
write_wav("rain.wav", loopable(hiss * 0.4 + drops))

# wind: deep noise with slow gusts (band-limited amplitude wander)
spec = np.fft.rfft(rng.standard_normal(n))
bed = np.fft.irfft(spec / (f ** 1.1), n)
gust_spec = np.fft.rfft(rng.standard_normal(n))
mask = f < 0.35
gust = np.fft.irfft(np.where(mask, gust_spec, 0), n)
gust = (gust - gust.min()) / (gust.max() - gust.min())
write_wav("wind.wav", loopable(bed * (0.3 + 0.7 * gust)))

# fan: brown bed + faint 58 Hz motor hum + slight rotational wobble
spec = np.fft.rfft(rng.standard_normal(n))
bed = np.fft.irfft(spec / f, n)
bed = bed / np.max(np.abs(bed))
# Motor hum sits under the air, not over it: at 0.06 these two tones became
# the file's peak once the sub-bass was filtered out, so normalization scaled
# everything by a 58 Hz tone no phone can reproduce and the fan went silent.
hum = 0.012 * np.sin(2 * np.pi * 58 * t) + 0.006 * np.sin(2 * np.pi * 116 * t)
wobble = 1 + 0.05 * np.sin(2 * np.pi * 4.7 * t)
write_wav("fan.wav", loopable(bed * wobble + hum))

def tone(freqs_amps_decays, dur):
    m = int(dur * SR)
    tt = np.arange(m) / SR
    out = np.zeros(m)
    for fr, amp, dec in freqs_amps_decays:
        out += amp * np.sin(2 * np.pi * fr * tt) * np.exp(-tt / dec)
    return out * np.minimum(tt / 0.02, 1)   # click-free attack

# singing bowl: inharmonic partials, long decay
bowl = tone([(220, 1.0, 3.5), (516, 0.55, 2.6), (933, 0.30, 1.8), (1466, 0.15, 1.2)], 8)
write_wav("singing_bowl.wav", bowl)

# dawn: two soft rising notes, warm partials
d1 = tone([(392, 1.0, 1.6), (784, 0.35, 1.1)], 2.2)         # G4
d2 = tone([(523.25, 1.0, 2.4), (1046.5, 0.35, 1.4)], 3.4)   # C5
dawn = np.zeros(int(5.2 * SR))
dawn[:len(d1)] += d1
dawn[int(1.4 * SR):int(1.4 * SR) + len(d2)] += d2
write_wav("dawn.wav", dawn)

# --- wake tones (16 september 2026) ---
#
# gentle chime and soft bells shipped from the first commit of the app stir grew
# out of, downloaded from somewhere nobody wrote down (stir.md decision 22).
# These replace them, so every sound stir ships has a recipe here and no licence
# to keep track of. The rest are candidates for the ear test.
#
# What makes a struck sound read as metal, glass or wood is the ratio of its
# partials to the fundamental, and how fast each one dies. Harmonic ratios
# (1, 2, 3) sound like a string or a voice; the inharmonic ratios below are
# what a bar, a bell or a bowl actually does.

def strike(f0, partials, dur, attack=0.004):
    """One strike. partials: (ratio to f0, amplitude, decay seconds)."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    out = np.zeros(m)
    for ratio, amp, dec in partials:
        out += amp * np.sin(2 * np.pi * f0 * ratio * tt) * np.exp(-tt / dec)
    return out * np.minimum(tt / attack, 1)   # click-free attack

def sequence(events, dur):
    """events: (start in seconds, samples). Later strikes ring over earlier ones."""
    out = np.zeros(int(dur * SR))
    for start, x in events:
        i = int(start * SR)
        end = min(len(out), i + len(x))
        out[i:end] += x[:end - i]
    return out

# A free-free bar rings at 1, 2.76, 5.40 — the glassy, pitched-but-not-quite
# quality of a wind chime or a struck glass.
BAR = [(1.0, 1.0, 2.4), (2.76, 0.38, 1.1), (5.40, 0.14, 0.5), (8.93, 0.05, 0.25)]

# A tuned bell rings at hum, prime, tierce (minor third), quint, nominal. The
# minor third is why a bell sounds solemn where a bar sounds bright.
BELL = [(0.5, 0.55, 4.5), (1.0, 1.0, 3.4), (1.19, 0.5, 2.4),
        (1.5, 0.28, 1.8), (2.0, 0.33, 1.5), (2.5, 0.12, 0.9)]

# A standing bowl: like a bell but lower, longer, and beating slightly as two
# nearly-identical partials drift against each other.
BOWL = [(1.0, 1.0, 7.0), (1.004, 0.9, 7.0), (2.34, 0.45, 4.2),
        (4.23, 0.22, 2.4), (6.61, 0.10, 1.4)]

# gentle chime: two glass strikes, the second softer and a fifth up
chime = sequence([(0.0, strike(523.25, BAR, 3.4)),
                  (0.85, 0.6 * strike(783.99, BAR, 3.0))], 4.6)
write_wav("gentle_chime.wav", chime)

# soft bells: a bell struck twice, left to ring
bells = sequence([(0.0, strike(392.00, BELL, 6.0)),
                  (2.1, 0.7 * strike(392.00, BELL, 5.5))], 8.0)
write_wav("soft_bells.wav", bells)

# deep bowl: one low strike, very long decay — the singing bowl an octave down
write_wav("deep_bowl.wav", strike(146.83, BOWL, 14, attack=0.01))

# temple bells: a bowl struck twice a fifth apart, slow and spacious
temple = sequence([(0.0, strike(196.00, BOWL, 10)),
                   (3.2, 0.75 * strike(293.66, BOWL, 9))], 13.0)
write_wav("temple_bells.wav", temple)

# music box: a three-note figure, bright and short — the only tone here that
# plays something rather than sounding something
BOX = [(1.0, 1.0, 0.9), (4.0, 0.22, 0.35), (10.4, 0.06, 0.15)]
box = sequence([(0.0, strike(1046.50, BOX, 1.6)),       # C6
                (0.42, strike(1318.51, BOX, 1.6)),      # E6
                (0.84, strike(1567.98, BOX, 2.2))], 3.4)  # G6
write_wav("music_box.wav", box)

# marimba: warm wooden mallet, a rising third
WOOD = [(1.0, 1.0, 0.55), (3.9, 0.20, 0.22), (9.2, 0.05, 0.10)]
marimba = sequence([(0.0, strike(349.23, WOOD, 1.2)),
                    (0.5, strike(440.00, WOOD, 1.2)),
                    (1.0, strike(523.25, WOOD, 1.8))], 3.0)
write_wav("marimba.wav", marimba)

# wind chimes: five bars struck in no particular order, as air moves them
chimes = sequence(
    [(float(start), float(amp) * strike(float(f0), BAR, 3.2))
     for start, f0, amp in zip(
         [0.0, 0.55, 0.95, 1.7, 2.4],
         [587.33, 698.46, 880.00, 1046.50, 783.99],   # D5 F5 A5 C6 G5
         [1.0, 0.7, 0.85, 0.6, 0.75])],
    5.6)
write_wav("wind_chimes.wav", chimes)

# first light: no strike at all — a chord that swells out of silence and falls
# away, for waking without an onset
swell_dur = 9.0
tt = np.arange(int(swell_dur * SR)) / SR
env = np.sin(np.pi * tt / swell_dur) ** 1.5           # slow in, slow out
first_light = np.zeros(len(tt))
for fr, amp in [(261.63, 1.0), (392.00, 0.6), (523.25, 0.45), (659.25, 0.3), (784.00, 0.18)]:
    drift = 1 + 0.0009 * np.sin(2 * np.pi * 0.11 * tt + fr)   # slight chorus
    first_light += amp * np.sin(2 * np.pi * fr * drift * tt)
write_wav("first_light.wav", first_light * env)
