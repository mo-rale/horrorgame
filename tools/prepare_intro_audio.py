"""Synthesizes the intro radio sounds in assets/sfx/intro/ (no third-party audio):
  radio_static.wav - a short squelch burst of band-limited noise
  radio_open.wav   - the click + hiss when the dispatcher keys the radio
  radio_lost.wav   - a long fading static for the signal dropping out
Run from the project root: python tools/prepare_intro_audio.py"""
import math, random, struct, wave

RATE = 22050
random.seed(21)


def bandpass(samples, low, high):
    a_hi = 1 - math.exp(-2 * math.pi * high / RATE)
    a_lo = 1 - math.exp(-2 * math.pi * low / RATE)
    y1 = y2 = 0.0
    out = []
    for s in samples:
        y1 += a_hi * (s - y1)
        y2 += a_lo * (y1 - y2)
        out.append(y1 - y2)
    return out


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def write(name, samples, peak=0.8):
    top = max(abs(s) for s in samples) or 1.0
    with wave.open("assets/sfx/intro/" + name, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / top * peak * 32767)) for s in samples))


# static burst with crackle
n = int(RATE * 1.3)
base = bandpass(noise(n), 400, 3200)
out = []
for i, s in enumerate(base):
    t = i / n
    env = (min(t / 0.03, 1.0)) * (1.0 - t) ** 0.6
    crackle = 1.0 if random.random() > 0.02 else 3.0
    out.append(s * env * crackle * (0.6 + 0.4 * math.sin(i * 0.004)))
write("radio_static.wav", out)

# keying the radio: sharp click then short hiss
n = int(RATE * 0.35)
hiss = bandpass(noise(n), 800, 4000)
out = []
for i, s in enumerate(hiss):
    t = i / RATE
    click = math.exp(-t * 260) * 2.0 * random.uniform(-1, 1) if t < 0.03 else 0.0
    out.append(click + s * 0.35 * math.exp(-t * 9))
write("radio_open.wav", out, 0.7)

# signal lost: static that stutters and dies
n = int(RATE * 2.6)
base = bandpass(noise(n), 300, 3600)
out = []
for i, s in enumerate(base):
    t = i / n
    gate = 1.0 if (int(i / (RATE * 0.11)) % 3 != 2 or t < 0.3) else 0.2
    out.append(s * gate * (1.0 - t) ** 1.4)
write("radio_lost.wav", out)
print("wrote assets/sfx/intro/")
