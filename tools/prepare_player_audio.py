"""Synthesizes assets/sfx/player/breathing.wav: a seamless, ragged breath loop
(in / out with a noisy rasp) used when the player is out of stamina.
Run from the project root: python tools/prepare_player_audio.py"""
import math, random, struct, wave

RATE = 22050
random.seed(9)
seconds = 2.4
n = int(RATE * seconds)
out = []
state = 0.0
for i in range(n):
    t = i / n
    # one breath cycle: inhale (0..0.45), exhale (0.5..1.0)
    env = math.sin(math.pi * t / 0.45) if t < 0.45 else (math.sin(math.pi * (t - 0.5) / 0.5) * 0.8 if t >= 0.5 else 0.0)
    cutoff = 1800 if t < 0.5 else 900
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    state += a * (random.uniform(-1, 1) - state)
    out.append(state * env * (1.0 + 0.3 * math.sin(i * 0.03)))
peak = max(abs(s) for s in out)
with wave.open("assets/sfx/player/breathing.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.8 * 32767)) for s in out))
print("wrote assets/sfx/player/breathing.wav")
