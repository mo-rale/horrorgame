"""Builds the fuse / fuse box sound effects in assets/sfx/fuse/.

Usage: python tools/prepare_fuse_audio.py <electricity_pack_dir> <ui_sfx_dir>

- spark.wav       : "Electricity Game Sound Pack" crackleelectricityloop.wav (CC0), faded
- power_up.wav    : "Electricity Game Sound Pack" powerup.wav (CC0)
- insert_click.wav: Kenney "51 UI sound effects" switch sound (CC0)
- transformer_hum.wav : synthesized mains hum loop (no third-party audio)
"""
import math
import os
import random
import struct
import sys
import wave

OUT = os.path.join("assets", "sfx", "fuse")


def read_mono(path):
    with wave.open(path) as w:
        n, ch, rate, width = w.getnframes(), w.getnchannels(), w.getframerate(), w.getsampwidth()
        assert width == 2, path
        raw = w.readframes(n)
    data = struct.unpack("<%dh" % (n * ch), raw)
    if ch > 1:
        data = [sum(data[i:i + ch]) / ch for i in range(0, len(data), ch)]
    return [float(x) for x in data], rate


def downsample_half(samples):
    return [(samples[i] + samples[i + 1]) * 0.5 for i in range(0, len(samples) - 1, 2)]


def write_wav(name, samples, rate, peak=0.89):
    top = max(1e-9, max(abs(s) for s in samples))
    scale = peak * 32767 / top
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(s * scale)) for s in samples))


def fade(samples, rate, seconds_in=0.005, seconds_out=0.08):
    n_in, n_out = int(rate * seconds_in), int(rate * seconds_out)
    for i in range(min(n_in, len(samples))):
        samples[i] *= i / n_in
    for i in range(min(n_out, len(samples))):
        samples[-1 - i] *= i / n_out
    return samples


def hum_loop():
    rate = 22050
    seconds = 2.0
    n = int(rate * seconds)
    random.seed(5)
    out = []
    for i in range(n):
        t = i / rate
        s = 0.0
        for k, amp in ((100, 1.0), (200, 0.45), (300, 0.3), (500, 0.12)):
            s += amp * math.sin(2 * math.pi * k * t)       # whole cycles in 2 s: seamless
        s += random.uniform(-0.04, 0.04)
        out.append(s)
    return out, rate


def main():
    elec_dir, ui_dir = sys.argv[1], sys.argv[2]
    os.makedirs(OUT, exist_ok=True)

    spark, rate = read_mono(os.path.join(elec_dir, "crackleelectricityloop.wav"))
    write_wav("spark.wav", fade(downsample_half(spark), rate // 2), rate // 2)

    power, rate = read_mono(os.path.join(elec_dir, "powerup.wav"))
    write_wav("power_up.wav", fade(downsample_half(power), rate // 2, 0.01, 0.3), rate // 2)

    click, rate = read_mono(os.path.join(ui_dir, "switch23.wav"))
    write_wav("insert_click.wav", fade(click, rate, 0.002, 0.05), rate)

    hum, hum_rate = hum_loop()
    write_wav("transformer_hum.wav", hum, hum_rate, peak=0.5)

    with open(os.path.join(OUT, "CREDITS.txt"), "w", encoding="utf-8") as f:
        f.write(
            "Fuse and fuse box sound effects\n\n"
            "spark.wav, power_up.wav - from 'Electricity Game Sound Pack', CC0\n"
            "  https://opengameart.org/content/electricity-game-sound-pack\n"
            "insert_click.wav - from Kenney '51 UI sound effects (buttons, switches and clicks)', CC0\n"
            "  https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks\n"
            "transformer_hum.wav - synthesized by tools/prepare_fuse_audio.py (no third-party audio)\n"
        )
    print("wrote", sorted(os.listdir(OUT)))


main()
