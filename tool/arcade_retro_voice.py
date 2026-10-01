"""Deterministic 16-bit-era character chatter; no speech model or recordings."""
import hashlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
if (ROOT / "build/voice-tools").exists():
    sys.path.insert(0, str(ROOT / "build/voice-tools"))
import numpy as np

RATE = 24000
FORMANTS = {"a": (730, 1090, 2440), "e": (530, 1840, 2480),
            "i": (310, 2200, 3000), "o": (400, 850, 2400),
            "u": (300, 750, 2200), "y": (520, 1190, 2390)}


def syllable(seconds, pitch, end_pitch, vowel, timbre, seed, boss=False):
    rng = np.random.default_rng(seed)
    count = round(seconds * RATE)
    t = np.arange(count) / RATE
    u = np.arange(count) / max(1, count - 1)
    # Brief portamento, followed by a stable note and very slight vibrato.
    hz = pitch + (end_pitch - pitch) * np.minimum(1, u / .5)
    hz *= 1 + .007 * np.sin(2 * np.pi * 5.5 * t)
    phase = 2 * np.pi * np.cumsum(hz) / RATE
    centers = np.array(FORMANTS[vowel]) * timbre
    audio = np.zeros(count)
    for k in range(1, min(36, int(7200 / max(pitch, end_pitch))) + 1):
        frequency = k * (pitch + end_pitch) / 2
        resonance = np.sum(np.exp(-.5 * ((frequency - centers) / [150, 200, 280]) ** 2)
                           * [1., .55, .22])
        # A soft square/triangle core keeps this musical and deliberately unreal.
        weight = (.10 + resonance) / k ** .85
        if k % 2 == 0:
            weight *= .55
        audio += weight * np.sin(phase * k)
    audio /= max(.01, np.max(np.abs(audio)))
    if boss:
        audio = .84 * audio + .16 * np.sin(phase / 2)
    noise = rng.uniform(-1, 1, count)
    audio += noise * np.exp(-t * 65) * (.10 if boss else .035)
    envelope = np.minimum(1, t / .008) * np.minimum(1, (seconds - t) / .027)
    envelope *= .7 + .3 * np.sin(np.pi * u)
    # Gentle quantization adds sampler grain, while output remains PCM16.
    return np.round(audio * 2048) / 2048 * envelope


def retro_voice(text, speaker, variant=0, max_seconds=None):
    seed = int.from_bytes(hashlib.sha256(text.encode()).digest()[:4], "little")
    tokens = re.findall(r"[aeiouy]+|[.!?,…]", text.lower())
    cast = [("chip_soprano", 330., 1.07, 1., 0),
            ("chip_alto", 258., .97, .50, .035),
            ("chip_tenor", 204., .90, .38, .07)] if speaker == "crew" else (
        [("chip_hero", 190., .98, 1., 0)] if speaker == "hero" else
        [("chip_boss", 108. + variant * 3, .86, 1., 0)])
    notes = [0, 3, 2, 7, 5, 3, 0, 2]
    schedule = []
    cursor = 0.
    vowel_index = 0
    for token in tokens:
        if token[0] not in FORMANTS:
            cursor += .15 if token in ".!?…" else .09
            continue
        seconds = (.14 if speaker == "golem" else .092) + ((seed + vowel_index * 7) % 4) * .012
        schedule.append((cursor, seconds, token[0], vowel_index))
        cursor += seconds + (.047 if speaker == "golem" else .034)
        vowel_index += 1
    if not schedule:
        raise ValueError("Dialogue needs at least one vowel")
    extent = schedule[-1][0] + schedule[-1][1] + .09
    scale = min(1., (max_seconds - .09) / extent) if max_seconds else 1.
    output = np.zeros(round((extent * scale + .09) * RATE))
    for name, base, timbre, gain, delay in cast:
        for start, seconds, vowel, i in schedule:
            note = notes[(i + seed % 8) % len(notes)]
            pitch = base * 2 ** (note / 12)
            finish = pitch * (1.06 if text.endswith("?") else .97)
            if speaker == "golem":
                pitch = base * (1.12 - .035 * (i % 5))
                finish = pitch * .80
            sound = syllable(seconds * scale, pitch, finish, vowel, timbre,
                             seed + i, boss=speaker == "golem") * gain
            first = round((start * scale + delay) * RATE)
            output[first:first + len(sound)] += sound
    peak = np.max(np.abs(output))
    output *= .67 / max(.001, peak)
    sources = [{"text": text, "voice": name, "pitch_hz": base, "gain": gain,
                "delay": delay, "engine": "procedural-retro-v1", "seed": seed}
               for name, base, timbre, gain, delay in cast]
    return output, sources
