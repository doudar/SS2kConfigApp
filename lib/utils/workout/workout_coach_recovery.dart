import 'dart:math' as math;

/// Only fields used by the coach are retained from Intervals' wellness response.
/// Subjective fatigue/soreness: 1 low, 2 average, 3 high, 4 extreme; 0 is unset.
class CoachWellness {
  const CoachWellness({
    required this.day,
    this.sleepSecs,
    this.restingHR,
    this.hrv,
    this.fatigue,
    this.soreness,
    this.fitness,
    this.fatigueLoad,
  });
  final DateTime day;
  final double? sleepSecs, restingHR, hrv;
  final int? fatigue, soreness;
  // CTL/ATL are modeled training load, separate from self-reported fatigue.
  final double? fitness, fatigueLoad;
  double? get form =>
      fitness == null || fatigueLoad == null ? null : fitness! - fatigueLoad!;
  bool get hasFitness => form != null;

  bool get hasRecovery =>
      sleepSecs != null ||
      restingHR != null ||
      hrv != null ||
      fatigue != null ||
      soreness != null;

  static CoachWellness? fromJson(Map row) {
    final date = '${row['id']}';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;
    final day = DateTime.tryParse(date);
    if (day == null) return null;
    double? number(String key, double low, double high) {
      final value = row[key];
      if (value is! num || !value.isFinite || value < low || value > high)
        return null;
      return value.toDouble();
    }

    int? rating(String key) {
      final value = number(key, 1, 4);
      return value != null && value == value.roundToDouble()
          ? value.toInt()
          : null;
    }

    return CoachWellness(
      day: day,
      sleepSecs: number('sleepSecs', 1, 86400),
      // Intervals may carry resting HR forward. That is not a new measurement.
      restingHR: row['tempRestingHR'] == true
          ? null
          : number('restingHR', 20, 250),
      hrv: number('hrv', 1, 500),
      fatigue: rating('fatigue'),
      soreness: rating('soreness'),
      fitness: number('ctl', 0, 1000),
      fatigueLoad: number('atl', 0, 1000),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'sleepSecs': sleepSecs,
    'restingHR': restingHR,
    'hrv': hrv,
    'fatigue': fatigue,
    'soreness': soreness,
    'ctl': fitness,
    'atl': fatigueLoad,
  };
}

class CoachRecovery {
  const CoachRecovery({
    this.rest = false,
    this.reason,
    this.note = 'No recovery check-in for today; using ride history.',
    this.fitness,
  });
  final bool rest;
  final String? reason;
  final String note;

  /// Today's established load baseline, only when both CTL and ATL are present.
  final double? fitness;
  bool get easeOff => reason != null;

  static CoachRecovery assess(
    List<CoachWellness> history,
    DateTime now, {
    double formEaseThreshold = -.2,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final days = {for (final row in history) row.day: row};
    final current = days[today];
    if (current == null || (!current.hasRecovery && !current.hasFitness))
      return const CoachRecovery();
    final form = current.form;
    final relativeForm =
        current.fitness != null && current.fitness! > 0 && form != null
        ? form / current.fitness!
        : null;
    // Use relative form so the same absolute value is not treated equally for
    // riders with very different baselines. Do not equate negative form with
    // needing rest: some accumulated fatigue is expected during training.
    final loadRest =
        form != null &&
        (form <= -30 ||
            (form <= -10 && relativeForm != null && relativeForm <= -.4));
    final loadEasy =
        loadRest ||
        (form != null &&
            form <= -5 &&
            relativeForm != null &&
            relativeForm <= formEaseThreshold);
    final prior = days.values.where(
      (r) =>
          r.day.isBefore(today) &&
          !r.day.isBefore(today.subtract(const Duration(days: 28))),
    );
    double? medianFor(double? Function(CoachWellness) field) {
      final values = prior.map(field).whereType<double>().toList()..sort();
      if (values.length < 7) return null;
      final middle = values.length ~/ 2;
      return values.length.isOdd
          ? values[middle]
          : (values[middle - 1] + values[middle]) / 2;
    }

    final sleep = medianFor((r) => r.sleepSecs);
    final hr = medianFor((r) => r.restingHR);
    final hrv = medianFor((r) => r.hrv);
    final signals = <String>[];
    if ((current.fatigue ?? 0) >= 3) signals.add('high reported fatigue');
    if ((current.soreness ?? 0) >= 3) signals.add('high reported soreness');
    if (sleep != null &&
        current.sleepSecs != null &&
        current.sleepSecs! < math.min(sleep * .75, sleep - 3600)) {
      signals.add('less sleep than usual');
    }
    if (hr != null &&
        current.restingHR != null &&
        current.restingHR! >= math.max(hr * 1.1, hr + 5)) {
      signals.add('a higher resting heart rate than usual');
    }
    if (hrv != null && current.hrv != null && current.hrv! < hrv * .8) {
      signals.add('lower HRV than usual');
    }
    // These are conservative coaching heuristics, not a readiness diagnosis.
    // A favorable reading never overrides recent load or authorizes extra work.
    final rest =
        loadRest ||
        current.fatigue == 4 ||
        current.soreness == 4 ||
        signals.length >= 2 ||
        (loadEasy && signals.isNotEmpty);
    final compared =
        (sleep != null && current.sleepSecs != null) ||
        (hr != null && current.restingHR != null) ||
        (hrv != null && current.hrv != null) ||
        current.fatigue != null ||
        current.soreness != null;
    return CoachRecovery(
      rest: rest,
      fitness: current.hasFitness && current.fitness! > 0
          ? current.fitness
          : null,
      reason: loadRest
          ? 'Intervals.icu shows substantial fatigue compared with your fitness. Take today to recover.'
          : signals.isNotEmpty
          ? 'Today’s recovery check-in shows ${signals.join(' and ')}. ${rest ? 'Give yourself a rest day.' : 'Keep today’s effort easy.'}'
          : loadEasy
          ? 'Intervals.icu shows fatigue building relative to your fitness. An easy session leaves room to recover.'
          : null,
      note: [
        if (current.hasFitness)
          'Intervals.icu fitness, fatigue and form considered.',
        if (compared)
          'Today’s recovery check-in considered.'
        else if (current.hasRecovery)
          'Learning your recovery baseline.',
      ].join(' '),
    );
  }
}
