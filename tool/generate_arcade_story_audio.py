"""Render complete offline cutscene soundtracks, dialogue and original Foley.

Uses procedural retro voices and original Foley. No speech model or service.
Run with --install to update bundled tracks and generated Dart script/timing data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import wave

from arcade_retro_voice import ROOT, RATE, np, retro_voice
from scipy.signal import butter, resample_poly, sosfilt


SCRIPT = ROOT / "tool/arcade_story_script.json"
LEAD_IN = .18
TAIL = .65


def normalize(audio, peak=.78):
    audio = np.asarray(audio, dtype=np.float64).copy()
    audio -= np.mean(audio)
    edge = np.minimum(1, np.minimum(np.arange(len(audio)) / (RATE * .006),
                                   np.arange(len(audio))[::-1] / (RATE * .015)))
    audio *= edge
    maximum = np.max(np.abs(audio))
    if maximum < .001:
        raise ValueError("Silent audio")
    return audio * peak / maximum


def wav(path, audio):
    audio = resample_poly(audio, 147, 160)
    audio[0] = audio[-1] = 0
    audio *= .78 / max(.001, np.max(np.abs(audio)))
    pcm = np.round(audio * 32767).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
        output.writeframes(pcm)
    return len(audio), hashlib.sha256(path.read_bytes()).hexdigest()


def mix(parts):
    output = np.zeros(max(offset + len(data) for offset, data in parts))
    for offset, data in parts:
        output[offset:offset + len(data)] += data
    return output


def foley():
    """Original noise, resonators and transients; no third-party recordings."""
    rng = np.random.default_rng(913)

    def noise(seconds, cutoff=6000):
        n = rng.normal(0, 1, round(seconds * RATE))
        return sosfilt(butter(2, cutoff, fs=RATE, output="sos"), n)

    def hit(seconds, frequency, metal=False):
        t = np.arange(round(seconds * RATE)) / RATE
        if metal:
            result = sum(np.sin(2 * np.pi * frequency * ratio * t) * np.exp(-t * decay)
                         for ratio, decay in [(1, 7), (1.47, 10), (2.09, 14), (3.31, 20)]) * .18
        else:
            result = .8 * np.sin(2 * np.pi * (frequency * t + 22 * .04 * (1 - np.exp(-t / .04)))) * np.exp(-t * 13)
        return result + noise(seconds, 4000) * np.exp(-t * 38) * .23

    def pulses(seconds, times, frequency, metal=False):
        output = np.zeros(round(seconds * RATE))
        for i, when in enumerate(times):
            part = hit(min(.4, seconds - when), frequency * (1 + .07 * (i % 3)), metal)
            first = round(when * RATE)
            count = min(len(part), len(output) - first)
            output[first:first + count] += part[:count]
        return output

    result = {}
    t = np.arange(round(1.25 * RATE)) / RATE
    result["cageDrop"] = noise(1.25, 4500) * (.03 + .5 * (t / 1.25) ** 3)
    result["cageDrop"] += pulses(1.25, [.12, .35, .55, .72, .86, .98, 1.08], 770, True) * .3
    result["cageImpact"] = mix([(0, hit(1.1, 64)), (round(.015 * RATE), hit(1.0, 410, True) * .8),
                                (round(.16 * RATE), hit(.55, 610, True) * .28)])
    result["chainPull"] = pulses(1.35, [0, .18, .34, .49, .62, .74, .85, .95, 1.04], 920, True)
    result["villainSteps"] = pulses(1.3, [0, .4, .8], 56)
    result["bikeStart"] = pulses(1.0, [0, .13, .25, .36, .46, .55, .63, .7, .76, .81], 1300, True) * .35
    t = np.arange(RATE) / RATE
    result["bikeStart"] += noise(1, 3400) * np.sin(np.pi * t) ** 2 * .12
    t = np.arange(round(.85 * RATE)) / RATE
    result["bikeBrake"] = noise(.85, 2400) * np.sin(np.pi * t / .85) ** 2
    result["footsteps"] = pulses(.85, [0, .28, .57], 140) * .6
    t = np.arange(round(1.15 * RATE)) / RATE
    sparkle = sum(np.sin(2 * np.pi * hz * t) * np.exp(-t * decay)
                  for hz, decay in [(1046.5, 5), (1318.5, 6), (1568, 7), (2093, 8)]) * .2
    result["celebration"] = sparkle + pulses(1.15, [0, .14, .31, .50, .73], 480) * .4
    # Eight alternating footfalls match the golem's 1.6 strides/second.
    # Wrap the decay tails around the loop to preserve the running rhythm.
    loop = np.zeros(round(2.5 * RATE))
    for i in range(8):
        for delay, data in [(0, hit(.42, 58 + (i % 2) * 9) * .8),
                            (.045, hit(.23, 650 + (i % 3) * 110, True) * .48),
                            (.17, hit(.14, 1200, True) * .15)]:
            first = round((i / 3.2 + delay) * RATE)
            np.add.at(loop, (np.arange(len(data)) + first) % len(loop), data)
    t = np.arange(len(loop)) / RATE
    loop += noise(2.5, 3200) * (.025 + .025 * np.sin(2 * np.pi * 3.2 * t) ** 2)
    result["cageRun"] = loop
    return {name: normalize(audio) for name, audio in result.items()}


def visual_time(progress, chapters, anchors):
    for i in range(4):
        if progress <= anchors[i + 1]:
            return sum(chapters[:i]) + chapters[i] * (progress - anchors[i]) / (anchors[i + 1] - anchors[i])
    return sum(chapters)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    out = ROOT / "build/arcade-story-audio"
    out.mkdir(parents=True, exist_ok=True)
    script = json.loads(SCRIPT.read_text(encoding="utf-8"))
    scenes = []
    for variant in range(6):
        scenes.append({"name": f"intro_{variant}", "kind": "intro", "variant": variant,
                       "texts": script["opening"][variant], "speakers": ["crew", "golem", "crew", "hero"]})
        for outcome in ["recovered", "together"]:
            scenes.append({"name": f"ending_{variant}_{outcome}", "kind": "ending", "variant": variant,
                           "texts": [script["endingGreeting"], script["endingRelief"][outcome],
                                     script["endingCheer"][variant] if outcome == "recovered" else script["endingTogether"],
                                     script["endingSignoff"][variant]], "speakers": ["crew", "hero", "crew", "hero"]})
    rendered = {}
    for scene in scenes:
        for text, speaker in zip(scene["texts"], scene["speakers"]):
            key = (text, speaker, scene["variant"] if speaker == "golem" else 0)
            if key not in rendered:
                print(f"{speaker}: {text}", flush=True)
                rendered[key] = retro_voice(*key)
        scene["takes"] = [rendered[(text, speaker, scene["variant"] if speaker == "golem" else 0)]
                          for text, speaker in zip(scene["texts"], scene["speakers"])]
    durations = {}
    for kind in ["intro", "ending"]:
        durations[kind] = [max(4.0 if kind == "intro" else 3.4, np.ceil(max(len(s["takes"][i][0]) / RATE for s in scenes if s["kind"] == kind)
                                            * 10 + (LEAD_IN + TAIL) * 10) / 10) for i in range(4)]
    effects = foley()
    files, manifest = [], {"source": "Procedural retro character chatter and original Foley; no speech model",
                           "engine": "procedural-retro-v1",
                           "script_sha256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(), "scenes": [], "effects": []}
    for name, data in effects.items():
        path = out / f"arcade_fx_{name}.wav"
        frames, sha = wav(path, data)
        files.append(path)
        manifest["effects"].append({"asset": "sounds/" + path.name, "frames": frames, "sha256": sha})
    # Audible demonstration of the same distance envelope used on the road.
    preview = np.tile(effects["cageRun"], 6)
    progress = np.arange(len(preview)) / len(preview)
    preview *= (1 - progress ** 2) ** 2 * np.minimum(1, progress * 15 / .12)
    wav(out / "road_escape_preview.wav", preview)
    for scene in scenes:
        kind = scene["kind"]
        chapters = durations[kind]
        anchors = [0, .25, .5, .75, 1] if kind == "intro" else [0, .32, .64, .83, 1]
        audio = np.zeros(round(sum(chapters) * RATE))
        lines, events = [], []
        for i, (data, sources) in enumerate(scene["takes"]):
            start = round((sum(chapters[:i]) + LEAD_IN) * RATE)
            audio[start:start + len(data)] += data
            lines.append({"text": scene["texts"][i], "speaker": scene["speakers"][i], "voices": sources,
                          "startMs": round(start / RATE * 1000), "durationMs": round(len(data) / RATE * 1000)})
        at = lambda p: visual_time(p, chapters, anchors)
        triggers = [("villainSteps", at(.20), .20), ("cageDrop", at(.40) - 1.25, .20),
                    ("cageImpact", at(.40), .42), ("chainPull", at(.65), .25),
                    ("bikeStart", at(.76), .24)] if kind == "intro" else [
                        ("bikeBrake", at(.25) - .65, .22), ("footsteps", at(.48), .20),
                        ("celebration", at(.64), .24)]
        for name, when, gain in triggers:
            data = effects[name]
            first = round(when * RATE)
            if first < 0 or first + len(data) > len(audio):
                raise ValueError(f"Effect outside scene: {name}")
            audio[first:first + len(data)] += data * gain
            events.append({"name": name, "startMs": round(when * 1000), "gain": gain})
        path = out / f"arcade_story_{scene['name']}.wav"
        frames, sha = wav(path, normalize(audio))
        files.append(path)
        manifest["scenes"].append({"asset": "sounds/" + path.name, "kind": kind, "variant": scene["variant"],
                                   "chapterMs": [round(d * 1000) for d in chapters], "frames": frames,
                                   "sha256": sha, "lines": lines, "effects": events})
        print(f"Mixed {scene['name']}: {sum(chapters):.1f}s", flush=True)
    metadata = out / "arcade_story_audio_manifest.json"
    metadata.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    dart = "// Generated by tool/generate_arcade_story_audio.py. Do not edit.\n"
    constants = {"arcadeOpeningLines": script["opening"], "arcadeEndingGreeting": script["endingGreeting"],
                 "arcadeEndingRelief": [script["endingRelief"][k] for k in ["recovered", "together"]],
                 "arcadeEndingCheer": script["endingCheer"], "arcadeEndingTogether": script["endingTogether"],
                 "arcadeEndingSignoff": script["endingSignoff"],
                 "arcadeOpeningChapterMs": [round(d * 1000) for d in durations["intro"]],
                 "arcadeEndingChapterMs": [round(d * 1000) for d in durations["ending"]]}
    for name, value in constants.items():
        dart += f"const {name} = {json.dumps(value, ensure_ascii=False)};\n"
    generated = out / "arcade_story_audio.g.dart"
    generated.write_text(dart, encoding="utf-8")
    if args.install:
        for path in [*files, metadata]:
            shutil.copyfile(path, ROOT / "assets/sounds" / path.name)
        shutil.copyfile(generated, ROOT / "lib/utils/workout/arcade" / generated.name)
        print(f"Installed {len(scenes)} full soundtracks and {len(effects)} Foley effects.")


if __name__ == "__main__":
    main()
