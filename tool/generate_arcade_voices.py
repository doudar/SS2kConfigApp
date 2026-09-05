"""Original formant-synthesized arcade vocals, with no recordings or speech API.

Regenerate: python tool/generate_arcade_voices.py
Only writes the six voice WAV assets; never builds or launches the app.
These are expressive nonsense syllables, with dialogue supplied by the UI.
"""
from array import array
import math
from pathlib import Path
import random
import sys
import wave

RATE = 22050
TAU = math.tau
OUT = Path(__file__).resolve().parents[1] / "assets" / "sounds"
VOWELS = {
    "ah": (730, 1090, 2440),
    "oh": (400, 850, 2400),
    "oo": (300, 750, 2200),
    "ee": (310, 2200, 3000),
    "uh": (520, 1190, 2390),
}


def voice(samples, start, duration, pitch, end_pitch, vowel, end_vowel,
          gain=1.0, breath=.09, robot=False, seed=0):
    """Glottal harmonic source shaped by three moving vocal resonances."""
    rng = random.Random(seed)
    first, last = VOWELS[vowel], VOWELS[end_vowel]
    middle_pitch = (pitch + end_pitch) / 2
    harmonics = min(48, int(7800 / max(pitch, end_pitch)))

    def spectrum(formants):
        values = []
        for k in range(1, harmonics + 1):
            frequency = k * middle_pitch
            resonance = sum(weight * math.exp(-.5 * ((frequency - center) / width) ** 2)
                            for center, width, weight in zip(formants, (105, 155, 220), (1, .7, .35)))
            values.append((.035 + resonance) / k ** .65)
        total = sum(values)
        return [x / total for x in values]

    a, b = spectrum(first), spectrum(last)
    phase = 0.0
    offset = round(start * RATE)
    count = min(round(duration * RATE), len(samples) - offset)
    for i in range(count):
        t = i / RATE
        u = t / duration
        frequency = (pitch + (end_pitch - pitch) * u) * (1 + .012 * math.sin(t * 32))
        phase += TAU * frequency / RATE
        voiced = sum((x + (y - x) * u) * math.sin(phase * k)
                     for k, (x, y) in enumerate(zip(a, b), 1))
        # Aspirated onset makes each laugh pulse a "ha", rather than a note.
        aspiration = (rng.random() * 2 - 1) * breath * math.exp(-t * 28)
        env = min(1, t / .014) * min(1, (duration - t) / .055)
        env *= (.75 + .25 * math.sin(math.pi * u))
        if robot:
            voiced = voiced * (.82 + .18 * math.sin(phase * .5)) + .09 * math.sin(phase * .5)
        samples[offset + i] += (voiced + aspiration) * env * gain


def write(name, seconds, parts, echo=0):
    samples = [0.0] * round(seconds * RATE)
    for index, part in enumerate(parts):
        voice(samples, **part, seed=index + 17)
    if echo:
        delay = round(echo * RATE)
        dry = samples[:]
        for i in range(delay, len(samples)):
            samples[i] += dry[i - delay] * .16
    peak = max(abs(x) for x in samples)
    pcm = array('h')
    for i, x in enumerate(samples):
        taper = min(1, i / (RATE * .006), (len(samples) - 1 - i) / (RATE * .012))
        pcm.append(round(x / max(peak, .001) * .78 * taper * 32767))
    if sys.byteorder != 'little':
        pcm.byteswap()
    path = OUT / f"arcade_fx_{name}.wav"
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(pcm.tobytes())
    rms = math.sqrt(sum((x / 32768) ** 2 for x in pcm) / len(pcm))
    print(f"{path.name}: {seconds:.2f}s, peak=0.78, RMS={rms:.3f}")


def syllable(start, duration, pitch, end_pitch, vowel, end_vowel, **kwargs):
    return dict(start=start, duration=duration, pitch=pitch, end_pitch=end_pitch,
                vowel=vowel, end_vowel=end_vowel, **kwargs)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write('golemLaugh', 2.1, [
        syllable(start, duration, pitch, pitch * .77, 'ah', 'oh', robot=True, breath=.3)
        for start, duration, pitch in [(0, .29, 124), (.34, .3, 116),
                                      (.69, .32, 108), (1.06, .35, 102), (1.46, .43, 92)]
    ], echo=.13)
    write('crewHello', .95, [
        syllable(0, .3, 280, 390, 'oo', 'ah', gain=.8),
        syllable(.34, .45, 360, 320, 'ah', 'ee', gain=.7),
        syllable(.12, .57, 440, 390, 'oo', 'ee', gain=.28),
    ])
    write('crewAlarm', 1.1, [
        syllable(.02, .28, 340, 510, 'uh', 'ah', breath=.45),
        syllable(.4, .48, 460, 370, 'ah', 'ee', breath=.25),
        syllable(.18, .5, 255, 320, 'oh', 'ah', gain=.35),
    ])
    write('heroReady', 1.1, [
        syllable(.02, .27, 170, 205, 'uh', 'ah', breath=.2),
        syllable(.35, .54, 200, 250, 'ee', 'oh', breath=.12),
    ])
    write('heroRelief', 1.25, [
        syllable(.02, .57, 235, 155, 'oo', 'uh', breath=.35),
        syllable(.7, .32, 175, 190, 'ah', 'ee', gain=.65),
    ])
    cheers = []
    for i, pitch in enumerate([280, 365, 450]):
        cheers += [
            syllable(i * .13, .47, pitch, pitch * 1.27, 'oo', 'oo', gain=.6),
            syllable(.55 + i * .12, .68, pitch * 1.2, pitch * .96, 'ah', 'ee', gain=.55),
        ]
    write('crewCheer', 1.8, cheers, echo=.16)


if __name__ == '__main__':
    main()
