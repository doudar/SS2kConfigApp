// Original Crank Quest score and effects. No samples or borrowed melodies.
// Regenerate everything: dart run tool/generate_arcade_music.dart
import 'arcade_synth.dart';

void main() {
  _grove();
  _coast();
  _neon();
  _volcano();
  _effects();
}

void _phrase(
  ArcadeSynth s,
  double start,
  double beat,
  List<int> notes,
  Voice voice,
  double gain, {
  double step = .5,
  double gate = .8,
  double echo = 0,
}) {
  for (var i = 0; i < notes.length; i++) {
    if (notes[i] < 0) continue;
    s.note(
      start + i * step * beat,
      step * beat * gate,
      notes[i],
      voice,
      gain,
      echo: echo * beat,
    );
  }
}

// D major, lilting 3/4: bell conversations over warm, spacious sixth chords.
// Four eight-bar sections introduce flute, open into a quiet bridge, then return.
void _grove() {
  const beat = 60 / 84;
  final s = ArcadeSynth(32 * 3 * beat);
  const chords = [
    [50, 57, 61, 66],
    [47, 54, 57, 62],
    [43, 50, 57, 59],
    [45, 52, 59, 64],
  ];
  const phrases = [
    [78, -1, 81, 78, 76, -1, 74, 73, 74, -1, 69, -1],
    [74, -1, 78, 81, 83, 81, 78, -1, 76, -1, 74, -1],
    [71, -1, 74, 78, 76, -1, 73, 74, 69, -1, -1, -1],
    [76, 78, 81, -1, 78, 76, 74, -1, 73, 69, 74, -1],
  ];
  for (var bar = 0; bar < 32; bar++) {
    final t = bar * 3 * beat;
    final chord = chords[(bar ~/ 2 + (bar >= 16 ? 1 : 0)) % 4];
    for (final note in chord) s.note(t, 3.4 * beat, note, Voice.choir, .052);
    s.note(t, 2.6 * beat, chord.first - 12, Voice.bass, .16);
    final bridge = bar >= 16 && bar < 24;
    if (bar.isEven)
      _phrase(
        s,
        t,
        beat,
        phrases[(bar ~/ 2 + bar ~/ 8) % 4],
        bridge ? Voice.flute : Voice.bell,
        bridge ? .13 : .22,
        gate: bridge ? 1.4 : 1.8,
        echo: .75,
      );
    if (bar >= 8 && !bridge) {
      s.note(t + beat, beat * .7, chord[2] + 12, Voice.pluck, .065);
      s.note(t + beat * 2.5, beat * .4, chord[1] + 24, Voice.bell, .08);
      s.drum(t + beat * 2, Drum.hat, .065);
    }
    if (bar >= 24)
      s.note(t + beat * 1.5, beat, chord.last + 12, Voice.flute, .08);
  }
  s.write('assets/sounds/arcade_grove.wav');
}

// C major pentatonic: buoyant offbeats, bouncy bass, a whistled call-and-response.
void _coast() {
  const beat = 60 / 112;
  final s = ArcadeSynth(32 * 4 * beat);
  const roots = [48, 45, 41, 43, 48, 41, 50, 43];
  const phrases = [
    [76, 79, -1, 81, 79, -1, 76, 72, -1, 74, 76, -1, 79, 76, 74, -1],
    [72, -1, 76, 79, 81, -1, 84, 81, 79, 76, -1, 74, 72, -1, -1, -1],
    [77, 76, 74, -1, 72, 74, 76, 79, -1, 81, 79, 76, 74, -1, 72, -1],
    [79, -1, 81, 84, 86, 84, 81, -1, 79, 76, 74, -1, 72, -1, 76, 79],
  ];
  for (var bar = 0; bar < 32; bar++) {
    final t = bar * 4 * beat;
    final root = roots[bar % 8];
    final third = bar % 8 == 1 || bar % 8 == 6 ? 3 : 4;
    final breakdown = bar >= 16 && bar < 20;
    _phrase(
      s,
      t,
      beat,
      [root - 12, -1, root, root + 7, -1, root - 12, root + 7, root],
      Voice.bass,
      .26,
      gate: .9,
    );
    for (var b = 0; b < 4; b++) {
      for (final note in [root, root + third, root + 7]) {
        s.note(t + (b + .5) * beat, beat * .26, note + 12, Voice.pluck, .085);
      }
      if (!breakdown) {
        s.drum(
          t + b * beat,
          b.isEven ? Drum.kick : Drum.snare,
          b.isEven ? .36 : .20,
        );
        s.drum(t + (b + .5) * beat, Drum.hat, .12);
      }
    }
    if (bar.isEven)
      _phrase(
        s,
        t,
        beat,
        phrases[(bar ~/ 2 + bar ~/ 8) % 4],
        bar >= 24 ? Voice.pulse : Voice.flute,
        breakdown ? .10 : .18,
        gate: 1.0,
        echo: .5,
      );
    if (bar % 8 == 7) {
      for (var k = 0; k < 4; k++)
        s.drum(t + (3 + k / 4) * beat, Drum.tom, .15, pitch: 1.5 - k * .2);
    }
  }
  s.write('assets/sounds/arcade_coast.wav');
}

// F# Dorian: precise sixteenth-note arpeggios and syncopated electro bass.
void _neon() {
  const beat = 60 / 128;
  final s = ArcadeSynth(32 * 4 * beat);
  const roots = [42, 42, 45, 47, 42, 49, 47, 40];
  const melody = [
    [78, -1, 81, 85, -1, 83, 81, -1, 78, 76, -1, 73, 76, -1, 78, -1],
    [85, -1, 88, 85, 83, -1, 81, 78, -1, 81, 83, 85, 90, -1, 88, 85],
    [73, 76, -1, 78, 81, -1, 78, 76, 73, -1, 71, 73, 76, 78, -1, -1],
    [78, 81, 85, -1, 88, 85, 83, 81, 78, -1, 76, 73, 76, -1, 78, -1],
  ];
  for (var bar = 0; bar < 32; bar++) {
    final t = bar * 4 * beat;
    final root = roots[bar % 8];
    final breakdown = bar >= 16 && bar < 20;
    _phrase(
      s,
      t,
      beat,
      [root, -1, root, root + 12, -1, root + 7, root, -1],
      Voice.saw,
      .21,
      gate: .65,
    );
    final arp = [root + 24, root + 31, root + 34, root + 36];
    if (!breakdown)
      _phrase(
        s,
        t,
        beat,
        List.generate(16, (i) => arp[(i + bar ~/ 4) % 4]),
        Voice.pluck,
        .09,
        step: .25,
        gate: .85,
        echo: .75,
      );
    if (bar >= 8 && bar.isEven)
      _phrase(s, t, beat, melody[(bar ~/ 2) % 4], Voice.pulse, .14, gate: .7);
    for (var b = 0; b < 4; b++) {
      if (!breakdown) s.drum(t + b * beat, Drum.kick, .32);
      if (b.isOdd && bar >= 4)
        s.drum(t + b * beat, Drum.snare, breakdown ? .08 : .2);
      s.drum(t + (b + .5) * beat, Drum.hat, .09);
    }
    if (bar % 8 == 0) s.drum(t, Drum.crash, .14);
    if (bar >= 20 && bar < 24) {
      for (var k = 0; k < (bar - 19) * 2; k++)
        s.drum(t + k * beat / 2, Drum.snare, .06 + k * .009);
    }
  }
  s.write('assets/sounds/arcade_neon.wav');
}

// D minor / Phrygian tension. Low pedal tones, flat-second chords, metallic
// ostinati and heavy half-time drums. The final eight bars answer the threat
// with an ascending harmonic-minor lead: ominous, but moving toward victory.
void _volcano() {
  const beat = 60 / 138;
  final s = ArcadeSynth(32 * 4 * beat);
  const roots = [38, 38, 39, 38, 34, 34, 33, 37];
  const calls = [
    [62, -1, 65, -1, 69, 68, 65, -1, 62, -1, 61, 62, 65, -1, 69, -1],
    [62, 65, 69, -1, 73, -1, 74, -1, 73, 69, -1, 65, 64, 61, 62, -1],
    [69, -1, 70, 69, 65, -1, 63, -1, 62, -1, 65, 69, 73, -1, 74, -1],
    [74, -1, 77, 81, -1, 79, 77, -1, 76, 73, 74, -1, 69, 73, 74, -1],
  ];
  for (var bar = 0; bar < 32; bar++) {
    final t = bar * 4 * beat;
    final root = roots[bar % 8];
    final breakdown = bar >= 16 && bar < 20;
    for (final interval in [0, 7, bar % 8 == 2 ? 4 : 3]) {
      s.note(t, beat * 4.2, root + interval + 12, Voice.choir, .065);
    }
    s.note(t, beat * 3.9, root - 12, Voice.bass, .17);
    if (!breakdown) {
      for (var b = 0; b < 4; b++) {
        s.note(t + b * beat, beat * .42, root, Voice.metal, .20);
        s.note(
          t + (b + .5) * beat,
          beat * .19,
          root + (b == 3 ? 1 : 12),
          Voice.saw,
          .105,
        );
        s.note(t + (b + .75) * beat, beat * .19, root + 7, Voice.metal, .10);
        s.drum(t + (b + .5) * beat, Drum.hat, bar >= 24 ? .11 : .055);
      }
    }
    s.drum(t, Drum.kick, .50, pitch: .85);
    s.drum(t + beat * 2, Drum.snare, .26);
    if (bar >= 8 && !breakdown)
      s.drum(t + beat * 1.5, Drum.kick, .36, pitch: .85);
    if (bar >= 24) s.drum(t + beat * 3, Drum.kick, .34, pitch: .85);
    if (bar.isEven && !breakdown) {
      final phrase = bar >= 24
          ? calls[bar % 4 == 0 ? 1 : 3]
          : calls[(bar ~/ 2) % 3];
      _phrase(
        s,
        t,
        beat,
        phrase,
        bar >= 24 ? Voice.pulse : Voice.metal,
        bar >= 24 ? .22 : .14,
        gate: 1.3,
        echo: .75,
      );
    }
    if (breakdown) {
      s.note(
        t + beat,
        beat * 2,
        62 + (bar % 2),
        Voice.bell,
        .16,
        echo: 1.5 * beat,
      );
      s.drum(t + beat * 3, Drum.tom, .2, pitch: .65);
    }
    if ((bar >= 20 && bar < 24) || bar % 8 == 7) {
      for (var k = 0; k < 4; k++)
        s.drum(
          t + (3 + k / 4) * beat,
          Drum.tom,
          .18 + k * .025,
          pitch: 1.4 - k * .2,
        );
    }
    if (bar % 8 == 0) s.drum(t, Drum.crash, .2);
  }
  s.write('assets/sounds/arcade_volcano.wav');
}

void _effects() {
  var s = ArcadeSynth(.18, wrapTails: false);
  s.note(0, .10, 86, Voice.bell, .5);
  s.note(.06, .12, 93, Voice.bell, .4);
  s.write('assets/sounds/arcade_fx_pickup.wav');
  s = ArcadeSynth(.24, wrapTails: false);
  s.note(0, .21, 83, Voice.pulse, .4, slide: -26);
  s.drum(0, Drum.hat, .12);
  s.write('assets/sounds/arcade_fx_bolt.wav');
  s = ArcadeSynth(.60, wrapTails: false);
  _phrase(s, 0, .16, [74, 78, 81, 86], Voice.pulse, .35, step: 1, gate: .75);
  s.write('assets/sounds/arcade_fx_combo.wav');
  s = ArcadeSynth(1.10, wrapTails: false);
  s.note(0, 1.05, 26, Voice.bass, .4);
  s.note(0, .8, 50, Voice.metal, .24);
  s.note(.25, .8, 51, Voice.metal, .25, slide: -1);
  s.drum(0, Drum.tom, .35, pitch: .7);
  s.drum(.45, Drum.tom, .30, pitch: .6);
  s.write('assets/sounds/arcade_fx_bossApproach.wav');
  s = ArcadeSynth(.85, wrapTails: false);
  _phrase(s, 0, .14, [74, 78, 81, 86], Voice.bell, .4, step: 1, gate: 2.5);
  s.note(.42, .42, 62, Voice.pluck, .25);
  s.write('assets/sounds/arcade_fx_sectorClear.wav');
  s = ArcadeSynth(1.80, wrapTails: false);
  s.drum(0, Drum.crash, .28);
  s.note(0, .35, 38, Voice.metal, .30, slide: -18);
  _phrase(
    s,
    .18,
    .20,
    [62, 65, 69, 74, 77, 81],
    Voice.pulse,
    .28,
    step: 1,
    gate: 1.3,
  );
  for (final note in [62, 65, 69, 74]) s.note(1.32, .47, note, Voice.bell, .20);
  s.write('assets/sounds/arcade_fx_bossDefeat.wav');
}
