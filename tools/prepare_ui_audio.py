"""Builds the UI sound effects in assets/sfx/ui/.

Usage: python tools/prepare_ui_audio.py <kenney_ui_sfx_dir>

Hover / click / back / slider are Kenney's "51 UI sound effects" (CC0), pitched
down and layered with a low thump so they sound heavy and metallic. The start
sting and the pause whooshes are synthesized (no third-party audio).
"""
import math
import os
import random
import struct
import sys
import wave

OUT = os.path.join("assets", "sfx", "ui")
RATE = 44100


def read_mono(path):
    with wave.open(path) as w:
        n, ch, rate, width = w.getnframes(), w.getnchannels(), w.getframerate(), w.getsampwidth()
        assert width == 2, path
        raw = w.readframes(n)
    data = struct.unpack("<%dh" % (n * ch), raw)
    if ch > 1:
        data = [sum(data[i:i + ch]) / ch for i in range(0, len(data), ch)]
    return [float(x) / 32768 for x in data], rate


def resample(samples, factor):
    """Pitch by `factor` (0.8 = lower and longer) with linear interpolation."""
    out = []
    pos = 0.0
    while pos < len(samples) - 1:
        i = int(pos)
        frac = pos - i
        out.append(samples[i] * (1 - frac) + samples[i + 1] * frac)
        pos += factor
    return out


def lowpass(samples, cutoff, rate=RATE):
    a = 1 - math.exp(-2 * math.pi * cutoff / rate)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def thump(freq, seconds, rate=RATE, decay=22.0):
    n = int(rate * seconds)
    return [math.sin(2 * math.pi * freq * (i / rate) * (1 - 0.3 * i / n)) * math.exp(-decay * i / rate) for i in range(n)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0.0 for t in tracks) for i in range(n)]


def gain(samples, g):
    return [s * g for s in samples]


def fade(samples, seconds_in=0.003, seconds_out=0.04):
    n_in, n_out = int(RATE * seconds_in), int(RATE * seconds_out)
    for i in range(min(n_in, len(samples))):
        samples[i] *= i / n_in
    for i in range(min(n_out, len(samples))):
        samples[-1 - i] *= i / n_out
    return samples


def delay(samples, seconds):
    return [0.0] * int(RATE * seconds) + samples


def save(name, samples, peak=0.85):
    top = max(1e-9, max(abs(s) for s in samples))
    scale = peak * 32767 / top
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale)) for s in samples))


def kenney(src, name):
    data, rate = read_mono(os.path.join(src, name))
    if rate != RATE:
        data = resample(data, rate / RATE)
    return data


def main():
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    random.seed(3)

    hover = fade(gain(resample(kenney(src, "rollover1.wav"), 0.72), 0.5))
    save("hover.wav", hover, 0.45)

    click = resample(kenney(src, "switch23.wav"), 0.82)
    save("click.wav", fade(mix(click, gain(thump(70, 0.18), 0.9))), 0.9)

    back = resample(kenney(src, "switch23.wav"), 0.62)
    save("back.wav", fade(mix(back, gain(thump(55, 0.22), 0.8))), 0.85)

    tick = resample(kenney(src, "click5.wav"), 1.15)
    save("slider.wav", fade(gain(tick, 0.5)), 0.4)

    # Start: two heartbeat thumps over a rising low drone.
    beat = mix(thump(48, 0.35, decay=9.0), delay(gain(thump(42, 0.4, decay=8.0), 0.8), 0.28))
    n = int(RATE * 1.1)
    drone = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        freq = 55 + 40 * (t / 1.1) ** 2
        phase += 2 * math.pi * freq / RATE
        drone.append(math.sin(phase) * 0.35 * min(1.0, t / 0.4) * max(0.0, 1.0 - max(0.0, t - 0.8) / 0.3))
    noise = lowpass([random.uniform(-1, 1) for _ in range(n)], 400)
    noise = [s * 0.6 * (i / n) for i, s in enumerate(noise)]
    save("start.wav", fade(mix(beat, drone, noise), 0.005, 0.2), 0.9)

    # Pause: a falling breath going in, the same thing reversed coming out.
    n = int(RATE * 0.45)
    breath = []
    state = 0.0
    for i in range(n):
        t = i / n
        cutoff = 3200 * (1 - t) + 220
        a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        state += a * (random.uniform(-1, 1) - state)
        breath.append(state * math.sin(math.pi * t) * 1.6)
    open_sound = fade(mix(breath, gain(thump(60, 0.3, decay=12.0), 0.7)), 0.01, 0.1)
    save("pause_open.wav", open_sound, 0.7)
    save("pause_close.wav", fade(list(reversed(open_sound)), 0.02, 0.03), 0.6)

    with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8") as f:
        f.write(
            "UI sound effects\n\n"
            "hover.wav, click.wav, back.wav, slider.wav - Kenney '51 UI sound effects (buttons, switches and clicks)', CC0,\n"
            "  pitched down and layered with synthesized thumps by tools/prepare_ui_audio.py\n"
            "  https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks\n"
            "start.wav, pause_open.wav, pause_close.wav - synthesized by tools/prepare_ui_audio.py (no third-party audio)\n"
        )
    print("wrote", sorted(os.listdir(OUT)))


main()
