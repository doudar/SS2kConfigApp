"""Original, deterministic chiptune enemy attacks; no recordings or packages.

Regenerate with: python tool/generate_arcade_enemy_sounds.py
Writes only the eleven short attack WAVs. Each has a different sonic gesture,
leaving space for the zone soundtrack and the rider's own weapon sound.
"""
from array import array
import hashlib
import math
from pathlib import Path
import random
import sys
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sounds"


class Sound:
    def __init__(self, seconds):
        self.samples = [0.0] * round(seconds * RATE)
        self.random = random.Random(1701)

    def tone(self, start, duration, first, last=None, gain=.4, shape="sine",
             mod=0, decay=2):
        """Pitch slide with a short attack and decay; all partials below Nyquist."""
        last = first if last is None else last
        phase = 0.0
        offset = round(start * RATE)
        count = min(round(duration * RATE), len(self.samples) - offset)
        for i in range(count):
            t = i / RATE
            u = t / duration
            hz = first * (last / first) ** u
            phase += math.tau * hz / RATE
            if shape == "pulse":
                value = sum(math.sin(phase * k) / k
                            for k in (1, 3, 5, 7) if hz * k < 8500) / 1.2
            elif shape == "metal":
                value = (math.sin(phase) + .45 * math.sin(phase * 1.414)
                         + .22 * math.sin(phase * 2.717)) / 1.67
            elif shape == "fm":
                value = math.sin(phase + 2.2 * math.sin(phase * 1.5))
            else:
                value = math.sin(phase)
            envelope = min(1, t / .008) * min(1, (duration - t) / .025)
            envelope *= math.exp(-decay * u)
            if mod:
                envelope *= .6 + .4 * math.sin(math.tau * mod * t)
            self.samples[offset + i] += value * envelope * gain

    def noise(self, start, duration, gain=.3, brightness=.15, decay=4):
        """Filtered noise: low rumbles, sandy scrapes and crisp electrical snaps."""
        offset = round(start * RATE)
        count = min(round(duration * RATE), len(self.samples) - offset)
        filtered = 0.0
        for i in range(count):
            t = i / RATE
            filtered += brightness * (self.random.uniform(-1, 1) - filtered)
            env = min(1, t / .004) * min(1, (duration - t) / .025)
            self.samples[offset + i] += filtered * env * math.exp(-decay * t / duration) * gain

    def echo(self, delay, gain=.2):
        dry = self.samples[:]
        offset = round(delay * RATE)
        for i in range(offset, len(dry)):
            self.samples[i] += dry[i - offset] * gain

    def write(self, name):
        peak = max(abs(x) for x in self.samples)
        pcm = array("h")
        for i, value in enumerate(self.samples):
            taper = min(1, i / (RATE * .006),
                        (len(self.samples) - 1 - i) / (RATE * .012))
            pcm.append(round(value / max(peak, .001) * .78 * taper * 32767))
        # Keep these checks here as well as in Flutter's bundled-audio test.
        assert pcm[0] == pcm[-1] == 0
        assert 20000 <= max(abs(x) for x in pcm) <= 26000
        rms = math.sqrt(sum((x / 32768) ** 2 for x in pcm) / len(pcm))
        assert .025 < rms < .4, (name, rms)
        if sys.byteorder != "little":
            pcm.byteswap()
        path = OUT / f"arcade_fx_{name}Attack.wav"
        with wave.open(str(path), "wb") as wav:
            wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            wav.writeframes(pcm.tobytes())
        print(f"{path.name}: {len(pcm) / RATE:.2f}s, RMS={rms:.3f}")
        return hashlib.sha256(pcm.tobytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sounds = {}

    # Wheel: a revving ratchet releases a spinning saw.
    s = sounds["wheel"] = Sound(.70)
    s.tone(0, .35, 95, 370, .35, "pulse", mod=28)
    for i in range(5):
        s.noise(.08 + i * .055, .045, .35, brightness=.5)
    s.tone(.3, .38, 1100, 180, .4, "metal")

    # Sentinel: three clipped laser pulses with an electronic aiming chirp.
    s = sounds["sentinel"] = Sound(.72)
    s.tone(0, .09, 740, 1480, .18, "sine")
    for i in range(3):
        s.tone(.12 + i * .16, .23, 1800, 240, .5, "pulse", decay=3)

    # Beetle: shell latch clicks and a heavy spring-loaded ram.
    s = sounds["beetle"] = Sound(.80)
    for i in range(3):
        s.tone(i * .075, .09, 650 - i * 90, 180, .25, "metal", decay=5)
    s.tone(.24, .52, 190, 48, .7, "fm", decay=4)
    s.noise(.24, .3, .65, brightness=.2)

    # Wasp: accelerating wing buzz ending in a needle-like stinger zip.
    s = sounds["wasp"] = Sound(.62)
    s.tone(0, .38, 170, 300, .32, "pulse", mod=47, decay=.5)
    s.tone(.22, .28, 600, 2700, .2, "sine", decay=.6)
    s.tone(.39, .20, 2400, 750, .32, "metal", decay=4)

    # Orb: a glassy oscillator charges, then expands into a sub-bass pulse.
    s = sounds["orb"] = Sound(.90)
    s.tone(0, .36, 250, 1050, .24, "sine", mod=12, decay=.2)
    s.tone(.32, .53, 420, 60, .65, "sine", decay=2.5)
    s.tone(.33, .4, 900, 190, .20, "fm", decay=3)
    s.echo(.11, .18)

    # Golem: two industrial hammer impacts and a low gear-shaft groan.
    s = sounds["golem"] = Sound(1.10)
    for start, pitch in [(0, 185), (.3, 120)]:
        s.tone(start, .62, pitch, 32, .75, "metal", decay=4)
        s.noise(start, .45, .85, brightness=.13)
    s.tone(.24, .8, 68, 39, .38, "pulse", mod=17, decay=2)

    # Bramble: dry branch cracks, vine-whip hiss and a hollow wooden knock.
    s = sounds["bramble"] = Sound(1.00)
    for i in range(4):
        s.noise(i * .095, .075, .48, brightness=.65, decay=6)
        s.tone(i * .095, .1, 370 - i * 32, 160, .22, "sine", decay=5)
    s.noise(.31, .55, .38, brightness=.12, decay=1)
    s.tone(.46, .45, 280, 95, .55, "fm", decay=4)

    # Scorpion: pincer snaps followed by a sandy tail-lash rattle.
    s = sounds["duneScorpion"] = Sound(.85)
    for start in (0, .16):
        s.tone(start, .16, 1250, 300, .36, "metal", decay=6)
        s.noise(start, .06, .48, brightness=.7)
    for i in range(6):
        s.noise(.3 + i * .065, .13, .48 - i * .045, brightness=.3)
    s.tone(.35, .4, 420, 110, .34, "pulse", decay=3)

    # Warden: descending ice chimes break into a crisp frost fracture.
    s = sounds["frostWarden"] = Sound(1.10)
    for i, hz in enumerate((1760, 1320, 1046, 880)):
        s.tone(i * .11, .6, hz, gain=.34, shape="metal", decay=4)
    s.noise(.4, .30, .38, brightness=.9, decay=6)
    s.tone(.42, .62, 440, 200, .20, "sine", decay=3)
    s.echo(.13, .25)

    # Ray: an arcing electrical zap with staggered crackles and thunder.
    s = sounds["stormRay"] = Sound(.95)
    s.tone(0, .23, 150, 1500, .35, "fm", mod=35, decay=.3)
    for i in range(4):
        s.noise(.2 + i * .07, .12, .48, brightness=.8)
        s.tone(.2 + i * .07, .17, 1900 - i * 320, 220, .28, "pulse", decay=4)
    s.noise(.4, .53, .65, brightness=.035, decay=3)
    s.tone(.4, .52, 92, 38, .37, "sine", decay=3)

    # Regent: an unsettling rising portal chord folds into a hollow implosion.
    s = sounds["voidRegent"] = Sound(1.20)
    for hz in (110, 155.56, 207.65):
        s.tone(0, .62, hz, hz * 2.5, .20, "fm", mod=7, decay=.2)
    s.tone(.52, .62, 620, 32, .65, "sine", decay=2)
    s.tone(.58, .48, 930, 115, .2, "metal", decay=3)
    s.echo(.17, .23)

    fingerprints = [sound.write(name) for name, sound in sounds.items()]
    assert len(set(fingerprints)) == 11, "Every enemy must have its own sound"


if __name__ == "__main__":
    main()
