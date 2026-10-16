"""Builds the pressure-valve sound effects in assets/sfx/valve/.

Usage: python tools/prepare_valve_audio.py <steam_hisses_dir> <metal_sfx_dir>

- steam_release.wav   : trimmed + normalised from "Steam release sounds" (CC0)
- steam_leak_loop.wav : seamless synthesized hiss for a leaking pipe
- valve_turn.wav      : synthesized rusty hand-wheel groan
- metal_clank.ogg / metal_slam.ogg : copied from "100 CC0 metal and wood SFX" (CC0)
"""
import math
import os
import random
import shutil
import struct
import sys
import wave

OUT = os.path.join("assets", "sfx", "valve")
RATE = 22050


def write_wav(path, samples, rate=RATE):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.89 * 32767 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale)) for s in samples))


def steam_release(src_dir):
    path = os.path.join(src_dir, "steam hisses - Marker #5.wav")
    with wave.open(path) as w:
        n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
        raw = w.readframes(n)
    data = struct.unpack("<%dh" % (n * ch), raw)[::ch]
    keep = int(rate * 1.1)
    data = [float(x) for x in data[:keep]]
    fade = int(rate * 0.25)
    for i in range(fade):
        data[-1 - i] *= i / fade
    # Resample to 22.05 kHz by dropping every other sample (hiss has no low content).
    data = data[::2]
    write_wav(os.path.join(OUT, "steam_release.wav"), data)


def one_pole_lowpass(samples, cutoff, rate=RATE):
    a = 1 - math.exp(-2 * math.pi * cutoff / rate)
    out, y = [], 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def steam_leak_loop():
    random.seed(7)
    n = int(RATE * 2.4)
    noise = [random.uniform(-1, 1) for _ in range(n)]
    low = one_pole_lowpass(noise, 1500)
    high = [a - b for a, b in zip(noise, low)]              # high-pass ~1.5 kHz
    band = one_pole_lowpass(high, 7000)                     # tame the top
    # Slow breathing modulation, then crossfade the ends so the loop is seamless.
    band = [s * (0.8 + 0.2 * math.sin(2 * math.pi * 0.9 * i / RATE)) for i, s in enumerate(band)]
    xf = int(RATE * 0.3)
    loop = band[: n - xf]
    for i in range(xf):
        t = i / xf
        loop[i] = loop[i] * t + band[n - xf + i] * (1 - t)
    write_wav(os.path.join(OUT, "steam_leak_loop.wav"), loop)


def valve_turn():
    random.seed(11)
    dur = 1.3
    n = int(RATE * dur)
    out = []
    phase = 0.0
    noise_lp = 0.0
    for i in range(n):
        t = i / RATE
        # stick-slip: friction pulses that speed up slightly as the wheel gets going
        pulse_rate = 7.0 + 3.0 * (t / dur)
        slip = (t * pulse_rate) % 1.0
        stick = (1.0 - slip) ** 2
        freq = 170 + 90 * stick + 25 * math.sin(2 * math.pi * 3.1 * t)
        phase += 2 * math.pi * freq / RATE
        saw = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        tone = saw * stick * 0.55
        noise_lp += 0.08 * (random.uniform(-1, 1) - noise_lp)
        scrape = noise_lp * 2.2 * (0.4 + stick)
        rumble = math.sin(2 * math.pi * 55 * t) * 0.18
        env = min(1.0, t / 0.08) * min(1.0, (dur - t) / 0.25)
        out.append((tone + scrape + rumble) * env)
    write_wav(os.path.join(OUT, "valve_turn.wav"), out)


def main():
    steam_dir, metal_dir = sys.argv[1], sys.argv[2]
    os.makedirs(OUT, exist_ok=True)
    steam_release(steam_dir)
    steam_leak_loop()
    valve_turn()
    shutil.copy(os.path.join(metal_dir, "metal_hit_02.ogg"), os.path.join(OUT, "metal_clank.ogg"))
    shutil.copy(os.path.join(metal_dir, "metal_slam_01.ogg"), os.path.join(OUT, "metal_slam.ogg"))
    with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8") as f:
        f.write(
            "Valve sound effects\n\n"
            "steam_release.wav - derived from 'Steam release sounds' (steam_hisses.zip), CC0\n"
            "  https://opengameart.org/content/steam-release-sounds\n"
            "metal_clank.ogg, metal_slam.ogg - from '100 CC0 metal and wood SFX' by rubberduck, CC0\n"
            "  https://opengameart.org/content/100-cc0-metal-and-wood-sfx\n"
            "steam_leak_loop.wav, valve_turn.wav - synthesized by tools/prepare_valve_audio.py (no third-party audio)\n"
        )
    print("wrote", sorted(os.listdir(OUT)))


main()
