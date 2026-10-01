# Retro character audio

All current game vocals are procedural, 16-bit-era-style chatter. There are no
neural speech recordings in the active cutscene tracks or short reaction assets.
`arcade_retro_voice.py` creates band-limited oscillator/formant syllables with
short pitch slides, smooth attack/release, gentle sampler grain and seeded
consonant-like transients. It does not attempt intelligible speech: the dialogue
bubbles contain the full script. Crew phrases layer soprano, alto and tenor
timbres with 35–70 ms offsets; the hero uses a warmer middle register, and the
boss has a low, descending growl/laugh.

## Regenerate

Use Python 3.12 and install NumPy/SciPy into the ignored build directory:

```sh
python -m pip install --target build/voice-tools -r tool/requirements-arcade-voices.txt
python tool/generate_arcade_story_audio.py --install
python tool/generate_arcade_voices.py
dart format lib/utils/workout/arcade/arcade_story_audio.g.dart
```

No model, network service, API key or runtime synthesis is involved. The sound
generation is deterministic. Edit `arcade_story_script.json` to change the text
and corresponding chatter rhythms; regenerate to keep text and timing in sync.
The six short reactions retain their original durations. Cutscene chapters leave
time for both the vocal phrase and reading the full written line.

`generate_arcade_story_audio.py` writes 18 complete soundtracks (six openings and
both endings for each story), nine standalone action effects, a manifest, and
generated Dart dialogue/timing constants. Install commits should include all
these outputs together. Effects include cage descent/impact, chains, villain
steps, bike departure/braking, footsteps, celebration and the cage-running loop.
`generate_arcade_voices.py` replaces the six standalone reactions and their
provenance. Assets are mono 22,050 Hz PCM16, with 78% peak level and faded edges.

Previews in `build/arcade-story-audio/`:

- `retro_voice_preview.wav`: greeting, alarm, laugh, ready, relief, cheer.
- `arcade_story_intro_0.wav`: opening chatter plus action effects.
- `road_escape_preview.wav`: 15 seconds of footsteps and rattling fading away.

## Playback and road escape

Cutscenes play a single prerecorded soundtrack, so vocals and action effects can
overlap without interrupting each other. Animation starts when audio is ready;
pause/resume seeks back to the visual clock position. Effects mute, skip/save,
background handling, and reduced-motion dialogue remain supported.

The road escape has an independent audio channel. `arcade_fx_cageRun.wav` is a
2.5-second loop of alternating heavy steps, chain/bar clatter and a rolling cage
texture. Its eight footfalls match the golem's 1.6 strides per second. Runtime
volume follows the same distance curve as the convoy, with a 120 ms onset fade
and silence as it leaves the road (up to 15 seconds, shorter for short openings).
The later distant hillside silhouette is silent. It does not play for boss-first
openings, unlimited rides, muted/hidden scenes or paused workouts. Resume seeks
to the current convoy's loop phase instead of replaying the start.

Validation:

```sh
flutter test test/arcade_escape_sound_test.dart test/arcade_cinematic_audio_test.dart test/arcade_audio_test.dart test/arcade_intro_test.dart test/arcade_finale_test.dart test/arcade_workout_view_test.dart
```
