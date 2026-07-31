import numpy as np, wave, sys, os

SR = 44100
OUT = sys.argv[1]

def write_wav(name, data):
    # normalize to -3 dBFS, 16-bit stereo
    data = data / np.max(np.abs(data)) * 0.7
    pcm = (data * 32767).astype(np.int16)
    stereo = np.column_stack([pcm, pcm]).ravel()
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(stereo.tobytes())
    print("wrote", name, len(data)/SR, "s")

def loopable(x, fade=2.0):
    # crossfade tail into head so the file loops seamlessly
    n = int(fade * SR)
    ramp = np.linspace(0, 1, n)
    x[:n] = x[:n] * ramp + x[-n:] * (1 - ramp)
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
