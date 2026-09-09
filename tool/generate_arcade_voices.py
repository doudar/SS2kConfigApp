"""Regenerate the six refined retro reaction WAVs; no speech model or API."""
import json

from arcade_retro_voice import ROOT, RATE, np, retro_voice
from generate_arcade_story_audio import wav
DURATIONS_MS = {"crewHello": 950, "crewAlarm": 1100, "golemLaugh": 2100,
                "heroReady": 1100, "heroRelief": 1250, "crewCheer": 1800}

REACTIONS = {
    "crewHello": ("Hey!", "crew"),
    "crewAlarm": ("Help!", "crew"),
    "golemLaugh": ("Ha ha ha ha ha!", "golem"),
    "heroReady": ("All right!", "hero"),
    "heroRelief": ("Whew!", "hero"),
    "crewCheer": ("Woo-hoo! Yeah!", "crew"),
}


def main():
    destination = ROOT / "assets/sounds"
    provenance = destination / "voice_provenance"
    provenance.mkdir(parents=True, exist_ok=True)
    reel = []
    for name, (text, speaker) in REACTIONS.items():
        seconds = DURATIONS_MS[name] / 1000
        audio, sources = retro_voice(text, speaker, max_seconds=seconds - .02)
        audio = np.pad(audio, (0, round(seconds * RATE) - len(audio)))
        path = destination / f"arcade_fx_{name}.wav"
        frames, sha = wav(path, audio)
        info = {"source": "Procedural retro vocal effect; no speech model or recording",
                "engine": "procedural-retro-v1", "voices": sources,
                "milliseconds": DURATIONS_MS[name], "sample_rate": 22050,
                "wav_sha256": sha}
        (provenance / f"arcade_fx_{name}.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
        reel.extend([audio, np.zeros(RATE // 2)])
        print(f"{name}: {frames} PCM16 frames", flush=True)
    preview = ROOT / "build/arcade-story-audio/retro_voice_preview.wav"
    preview.parent.mkdir(parents=True, exist_ok=True)
    wav(preview, np.concatenate(reel))


if __name__ == "__main__":
    main()
