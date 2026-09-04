// Offline, deterministic synthesis. Assets need no runtime synth or soundfont.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

enum Voice { bell, flute, pluck, pulse, bass, saw, choir, metal }

enum Drum { kick, snare, hat, tom, crash }

const audioSampleRate = 22050;
const _tau = math.pi * 2;
final _tables = {
  for (final voice in Voice.values)
    voice: Float64List.fromList(
      List.generate(2048, (i) {
        final p = i / 2048 * _tau;
        return switch (voice) {
          Voice.bell =>
            math.sin(p) * .65 + math.sin(p * 3) * .22 + math.sin(p * 7) * .1,
          Voice.flute => math.sin(p) * .85 + math.sin(p * 2) * .1,
          Voice.pluck =>
            math.sin(p) * .7 + math.sin(p * 2) * .15 + math.sin(p * 3) * .08,
          Voice.pulse =>
            math.sin(p) * .72 + math.sin(p * 3) * .20 + math.sin(p * 5) * .08,
          Voice.bass => math.sin(p) * .82 + math.sin(p * 2) * .12,
          Voice.saw =>
            math.sin(p) * .48 +
                math.sin(p * 2) * .24 +
                math.sin(p * 3) * .16 +
                math.sin(p * 4) * .1,
          Voice.choir =>
            math.sin(p) * .65 + math.sin(p * 3) * .12 + math.sin(p * 4) * .13,
          Voice.metal =>
            math.sin(p) * .5 +
                math.sin(p * 2) * .22 +
                math.sin(p * 7) * .16 +
                math.sin(p * 11) * .06,
        };
      }),
    ),
};

class ArcadeSynth {
  ArcadeSynth(this.seconds, {this.wrapTails = true})
    : samples = Float64List((seconds * audioSampleRate).round());
  final double seconds;
  final bool wrapTails;
  final Float64List samples;

  void _add(int index, double value) {
    if (index < samples.length) {
      samples[index] += value;
    } else if (wrapTails) {
      samples[index % samples.length] += value;
    }
  }

  void note(
    double start,
    double duration,
    num midi,
    Voice voice,
    double gain, {
    double slide = 0,
    double echo = 0,
  }) {
    final offset = (start * audioSampleRate).round();
    final count = (duration * audioSampleRate).round();
    final frequency = 440 * math.pow(2, (midi - 69) / 12);
    final table = _tables[voice]!;
    final slow = voice == Voice.choir;
    final plucked = voice == Voice.pluck || voice == Voice.bell;
    final attack = math.min(duration * .18, slow ? .18 : .008);
    final release = math.min(duration * .30, slow ? .25 : .06);
    var phase = 0.0;
    for (var i = 0; i < count; i++) {
      final t = i / audioSampleRate;
      var env =
          math.min(1.0, t / attack) * math.min(1.0, (duration - t) / release);
      if (plucked) env *= math.exp(-t / duration * 4);
      if (voice == Voice.metal) env *= .55 + .45 * math.exp(-t * 9);
      phase +=
          frequency / audioSampleRate * math.pow(2, slide * t / duration / 12);
      final position = (phase % 1) * 2048;
      final index = position.floor();
      final value =
          table[index] +
          (table[(index + 1) % 2048] - table[index]) * (position - index);
      final tremolo = slow ? .88 + .12 * math.sin(t * 3.1) : 1.0;
      _add(offset + i, value * env * gain * tremolo);
      if (echo > 0)
        _add(
          offset + i + (echo * audioSampleRate).round(),
          value * env * gain * .23,
        );
    }
  }

  void drum(double start, Drum drum, double gain, {double pitch = 1}) {
    final duration = switch (drum) {
      Drum.kick => .35,
      Drum.snare => .22,
      Drum.hat => .075,
      Drum.tom => .32,
      Drum.crash => .7,
    };
    final count = (duration * audioSampleRate).round();
    final offset = (start * audioSampleRate).round();
    final random = math.Random(offset + drum.index * 71);
    var lastNoise = 0.0;
    for (var i = 0; i < count; i++) {
      final t = i / audioSampleRate;
      final noise = random.nextDouble() * 2 - 1;
      final highNoise = (noise - lastNoise) * .5;
      lastNoise = noise;
      final value = switch (drum) {
        Drum.kick =>
          math.sin(_tau * (44 * pitch * t + 3 * (1 - math.exp(-t * 35)))) *
              math.exp(-t * 15),
        Drum.snare =>
          (highNoise * .8 + math.sin(_tau * 180 * t) * .2) * math.exp(-t * 22),
        Drum.hat => highNoise * math.exp(-t * 65),
        Drum.tom =>
          math.sin(_tau * (85 * pitch * t + 1.6 * (1 - math.exp(-t * 18)))) *
              math.exp(-t * 12),
        Drum.crash => highNoise * math.exp(-t * 6),
      };
      _add(offset + i, value * gain * math.min(1.0, t / .002));
    }
  }

  void write(String path) {
    final peak = samples.fold(0.0, (a, b) => math.max(a, b.abs()));
    final gain = peak == 0 ? 0.0 : .78 / peak;
    final wav = ByteData(44 + samples.length * 2);
    void ascii(int at, String value) {
      for (var i = 0; i < value.length; i++)
        wav.setUint8(at + i, value.codeUnitAt(i));
    }

    ascii(0, 'RIFF');
    wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, audioSampleRate, Endian.little);
    wav.setUint32(28, audioSampleRate * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    wav.setUint32(40, samples.length * 2, Endian.little);
    var squareSum = 0.0;
    for (var i = 0; i < samples.length; i++) {
      // A 3 ms splice taper prevents clicks; wrapped tails keep ambience intact.
      final edge = math.min(
        1.0,
        math.min(i, samples.length - 1 - i) / (audioSampleRate * .003),
      );
      final value = samples[i] * gain * edge;
      squareSum += value * value;
      wav.setInt16(
        44 + i * 2,
        (value * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(wav.buffer.asUint8List());
    stdout.writeln(
      '$path: ${seconds.toStringAsFixed(1)}s, RMS ${math.sqrt(squareSum / samples.length).toStringAsFixed(3)}',
    );
  }
}
