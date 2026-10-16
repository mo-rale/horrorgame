"""Builds assets/sfx/player/breathing.wav from the CC0 clip 'Breathing Tired'
(https://opengameart.org/content/breathing-tired): mono, 22.05 kHz, normalised,
trimmed to the breaths with short fades. The game plays it as a one-shot with
gaps, not a loop.
Usage: python tools/prepare_player_audio.py <path to 'breathing tired.wav'>"""
import struct, sys, wave

src = sys.argv[1]
w = wave.open(src)
n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
data = struct.unpack("<%dh" % (n * ch), w.readframes(n))
mono = [sum(data[i:i + ch]) / ch for i in range(0, len(data), ch)]
mono = [(mono[i] + mono[i + 1]) * 0.5 for i in range(0, len(mono) - 1, 2)]   # 22.05 kHz
rate //= 2
peak = max(abs(s) for s in mono)
floor = peak * 0.05
first = next(i for i, s in enumerate(mono) if abs(s) > floor)
last = len(mono) - next(i for i, s in enumerate(reversed(mono)) if abs(s) > floor)
mono = mono[max(first - 2000, 0):min(last + 3000, len(mono))]
fade = int(rate * 0.05)
for i in range(fade):
    mono[i] *= i / fade
    mono[-1 - i] *= i / fade
top = max(abs(s) for s in mono)
with wave.open("assets/sfx/player/breathing.wav", "wb") as out:
    out.setnchannels(1); out.setsampwidth(2); out.setframerate(rate)
    out.writeframes(b"".join(struct.pack("<h", int(s / top * 0.85 * 32767)) for s in mono))
print("wrote assets/sfx/player/breathing.wav (%.2f s)" % (len(mono) / rate))
