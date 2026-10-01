import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fit_tool/fit_tool.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/intervals_service.dart';
import '../../services/intervals_workout_converter.dart';
import '../../widgets/workout_library.dart';
import 'workout_coach.dart';
import 'workout_coach_recovery.dart';
import 'workout_lobby_choice.dart';
import 'workout_storage.dart';

class CoachData {
  const CoachData({
    required this.history,
    required this.candidates,
    this.account = 'local',
    this.goal = CoachGoal.consistent,
    this.incomplete = false,
    this.needsReconnect = false,
    this.note = 'Saved rides on this device',
    this.wellness,
  });
  final List<CoachRide> history;
  final List<CoachCandidate> candidates;
  final List<CoachWellness>? wellness;
  final String account, note;
  final CoachGoal goal;
  final bool incomplete, needsReconnect;
}

class WorkoutCoachRepository {
  @visibleForTesting
  static http.Client Function() createClient = http.Client.new;
  static final changes = ValueNotifier<int>(0);
  static Future<List<CoachRide>>? _local;
  static DateTime? _localAt;
  static double? _localFtp;
  static Future<List<CoachCandidate>>? _candidates;
  static DateTime? _candidatesAt;
  static final _pendingRemote = <String, Future<void>>{};

  static void invalidateLocal() {
    _local = null;
    _localAt = null;
    changes.value++;
  }

  /// An explicit login change should retry immediately with the new grant,
  /// even when the normal background retry cooldown has not elapsed.
  static Future<void> invalidateRemoteAttempt() async {
    final tokens = await IntervalsService.getStoredTokens();
    if (!(tokens['accessToken']?.isNotEmpty ?? false)) return;
    final prefs = await SharedPreferences.getInstance();
    final account = tokens['athleteId'] ?? '0';
    final cache = _cache(prefs, account)..remove('attemptAt');
    await prefs.setString('workout_coach_remote_$account', jsonEncode(cache));
  }

  static Future<CoachData> load(
    double ftp, {
    bool refreshRemote = false,
  }) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final tokens = await IntervalsService.getStoredTokens();
    final connected = tokens['accessToken']?.isNotEmpty ?? false;
    final account = connected ? tokens['athleteId'] ?? '0' : 'local';
    if (_local == null ||
        _localFtp != ftp ||
        now.difference(_localAt!) > const Duration(minutes: 2)) {
      _localFtp = ftp;
      _localAt = now;
      _local = _loadLocal(ftp).catchError((_) => <CoachRide>[]);
    }
    if (_candidates == null ||
        now.difference(_candidatesAt!) > const Duration(minutes: 2)) {
      _candidatesAt = now;
      _candidates = _loadCandidates().catchError((_) => <CoachCandidate>[]);
    }
    final localPending = _local!;
    final candidatesPending = _candidates!;
    if (connected && refreshRemote) {
      final key = '$account:${tokens['scope']}';
      await (_pendingRemote[key] ??= _refreshRemote(prefs, tokens, account)
          .whenComplete(() {
            _pendingRemote.remove(key);
          }));
    }
    final results = await Future.wait<Object>([
      localPending,
      candidatesPending,
    ]);
    final local = results[0] as List<CoachRide>;
    final candidates = [...results[1] as List<CoachCandidate>];
    var history = [...local];
    var note = 'Saved rides on this device';
    var incomplete = false;
    var reconnect = false;
    List<CoachWellness>? wellness;
    if (connected) {
      final cache = _cache(prefs, account);
      final historyAt = DateTime.tryParse('${cache['historyAt']}');
      final fresh =
          historyAt != null &&
          now.difference(historyAt) < const Duration(minutes: 15);
      // Use cached data while refreshing, but disclose stale/incomplete load.
      if (historyAt != null &&
          now.difference(historyAt) < const Duration(days: 2)) {
        history.addAll(
          (cache['history'] as List? ?? []).whereType<Map>().map(
            (r) => CoachRide.fromJson(Map<String, dynamic>.from(r)),
          ),
        );
      }
      candidates.addAll(
        await compute(
          parseCoachCandidates,
          (cache['choices'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        ),
      );
      reconnect =
          cache['permission'] == true || cache['wellnessPermission'] == true;
      final wellnessAt = DateTime.tryParse('${cache['wellnessAt']}');
      // Same-day measurements only, from a recently fetched account snapshot.
      wellness =
          wellnessAt != null &&
              now.difference(wellnessAt) < const Duration(minutes: 15)
          ? parseIntervalsCoachWellness(cache['wellness'] as List? ?? [])
          : [];
      incomplete = !fresh;
      note = reconnect
          ? 'Reconnect Intervals.icu to include ride history and recovery data.'
          : fresh
          ? 'Intervals.icu + saved rides · synced ${historyAt.hour.toString().padLeft(2, '0')}:${historyAt.minute.toString().padLeft(2, '0')}'
          : 'Using available history; Intervals.icu history is not up to date.';
    }
    final savedGoal = prefs.getString('workout_coach_goal');
    final goal =
        CoachGoal.values.where((g) => g.name == savedGoal).firstOrNull ??
        CoachGoal.consistent;
    // Same ZWO in multiple libraries should not dominate the shortlist.
    final seen = <String>{};
    return CoachData(
      history: history,
      candidates: candidates.where((c) => seen.add(c.choice.content)).toList(),
      account: account,
      goal: goal,
      incomplete: incomplete,
      needsReconnect: reconnect,
      note: note,
      wellness: wellness,
    );
  }

  static Future<void> saveGoal(CoachGoal goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_coach_goal', goal.name);
  }

  static Map<String, dynamic> _cache(SharedPreferences prefs, String account) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString('workout_coach_remote_$account') ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<List<CoachRide>> _loadLocal(double ftp) async {
    final dir = await getApplicationDocumentsDirectory();
    return compute(readCoachHistory, {
      'directory': dir.path,
      'ftp': ftp,
      'now': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<CoachCandidate>> _loadCandidates() async {
    final choices = <Map<String, dynamic>>[];
    try {
      for (final saved in await WorkoutStorage.getSavedWorkouts()) {
        if (saved['content'] is String)
          choices.add({'content': saved['content'], 'source': 'YOUR LIBRARY'});
      }
    } catch (_) {}
    final assets = await WorkoutLibrary.loadAssetWorkouts();
    for (final asset in assets) {
      try {
        choices.add({
          'content': await rootBundle.loadString(asset.path),
          'source': 'BUILT-IN',
        });
      } catch (_) {}
    }
    return compute(parseCoachCandidates, choices);
  }

  static Future<void> _refreshRemote(
    SharedPreferences prefs,
    Map<String, String?> tokens,
    String account,
  ) async {
    final cache = _cache(prefs, account);
    final now = DateTime.now();
    final lastAttempt = DateTime.tryParse('${cache['attemptAt']}');
    // Bound repeated visits and failed/offline calls, including across restarts.
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(minutes: 10) &&
        cache['scope'] == tokens['scope'])
      return;
    cache['attemptAt'] = now.toIso8601String();
    cache['scope'] = tokens['scope'];
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    Future<dynamic> get(String path, [Map<String, String>? query]) async {
      final client = createClient();
      try {
        final response = await client
            .get(
              Uri.https(
                'intervals.icu',
                '/api/v1/athlete/$account/$path',
                query,
              ),
              headers: {
                'Authorization': 'Bearer ${tokens['accessToken']}',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 7));
        if (response.statusCode == 401 || response.statusCode == 403)
          throw const _CoachPermission();
        if (response.statusCode != 200)
          throw const FormatException('Unavailable');
        return jsonDecode(response.body);
      } finally {
        client.close();
      }
    }

    await Future.wait([
      () async {
        try {
          final rows = await get('activities', {
            'oldest': day(now.subtract(const Duration(days: 35))),
            'newest': day(now),
          });
          if (rows is! List) throw const FormatException('Invalid history');
          cache['history'] = parseIntervalsCoachRides(
            rows,
          ).map((r) => r.toJson()).toList();
          cache['historyAt'] = now.toIso8601String();
          cache['permission'] = false;
        } on _CoachPermission {
          cache['permission'] = true;
        } catch (_) {
          /* Keep the previous successful snapshot. */
        }
      }(),
      () async {
        final at = DateTime.tryParse('${cache['libraryAt']}');
        if (at != null && now.difference(at) < const Duration(hours: 1)) return;
        try {
          final folders = await get('folders');
          if (folders is! List) throw const FormatException('Invalid library');
          cache['choices'] = await compute(parseIntervalsCoachChoices, folders);
          cache['libraryAt'] = now.toIso8601String();
        } catch (_) {}
      }(),
      () async {
        try {
          final rows = await get('wellness', {
            'oldest': day(now.subtract(const Duration(days: 28))),
            'newest': day(now),
          });
          if (rows is! List) throw const FormatException('Invalid wellness');
          cache['wellness'] = parseIntervalsCoachWellness(
            rows,
          ).map((r) => r.toJson()).toList();
          cache['wellnessAt'] = now.toIso8601String();
          cache['wellnessPermission'] = false;
        } on _CoachPermission {
          cache['wellnessPermission'] = true;
          cache.remove('wellness');
          cache.remove('wellnessAt');
        } catch (_) {
          /* Keep the previous snapshot subject to freshness checks. */
        }
      }(),
    ]);
    // Login may have changed while either request was in flight.
    final current = await IntervalsService.getStoredTokens();
    if (current['accessToken'] != tokens['accessToken']) return;
    await prefs.setString('workout_coach_remote_$account', jsonEncode(cache));
  }
}

class _CoachPermission implements Exception {
  const _CoachPermission();
}

List<CoachCandidate> parseCoachCandidates(List<Map<String, dynamic>> rows) {
  final result = <CoachCandidate>[];
  for (final row in rows) {
    try {
      final candidate = CoachCandidate.fromChoice(
        WorkoutLobbyChoice(
          content: row['content'] as String,
          source: row['source'] as String,
        ),
      );
      if (candidate != null) result.add(candidate);
    } catch (_) {}
  }
  return result;
}

List<CoachWellness> parseIntervalsCoachWellness(List<dynamic> rows) => rows
    .whereType<Map>()
    .map(CoachWellness.fromJson)
    .whereType<CoachWellness>()
    .where((r) => r.hasRecovery || r.hasFitness)
    .toList();

List<Map<String, dynamic>> parseIntervalsCoachChoices(List<dynamic> folders) {
  final result = <Map<String, dynamic>>[];
  void visit(dynamic node, int depth) {
    if (depth > 12 || result.length >= 250) return;
    if (node is List) {
      for (final child in node) {
        visit(child, depth + 1);
      }
    } else if (node is Map) {
      final event = Map<String, dynamic>.from(node);
      if (IntervalsService.isRideWorkoutEvent(event)) {
        final content = IntervalsWorkoutConverter.convertEventToZwo(event);
        if (content != null)
          result.add({'content': content, 'source': 'INTERVALS.ICU'});
      }
      visit(node['children'], depth + 1);
    }
  }

  visit(folders, 0);
  return result;
}

List<CoachRide> parseIntervalsCoachRides(List<dynamic> rows) {
  final rides = <CoachRide>[];
  for (final row in rows.whereType<Map>()) {
    final sport = '${row['type']}'.toLowerCase();
    if (!sport.contains('ride') && sport != 'cycling' && sport != 'bike')
      continue;
    final start = DateTime.tryParse(
      '${row['start_date'] ?? row['start_date_local']}',
    );
    final seconds = (row['moving_time'] as num?)?.toInt() ?? 0;
    final load = (row['icu_training_load'] as num?)?.toDouble();
    if (start == null || seconds <= 0) continue;
    rides.add(
      CoachRide(
        id: 'intervals:${row['id']}',
        start: start,
        seconds: seconds,
        tss: load != null && load.isFinite && load >= 0 ? load : null,
        remote: true,
      ),
    );
  }
  return rides;
}

/// File decoding and rolling power calculations never run on the UI isolate.
/// Sidecars are invalidated by file modification time; no thumbnails are made.
List<CoachRide> readCoachHistory(Map<String, dynamic> args) {
  final directory = Directory(
    '${args['directory']}${Platform.pathSeparator}workouts',
  );
  if (!directory.existsSync()) return [];
  final now = DateTime.fromMillisecondsSinceEpoch(args['now'] as int);
  final cutoff = now.subtract(const Duration(days: 35));
  final ftp = args['ftp'] as double;
  final rides = <CoachRide>[];
  for (final file in directory.listSync().whereType<File>().where(
    (f) => f.path.toLowerCase().endsWith('.fit'),
  )) {
    try {
      final stat = file.statSync();
      final cacheFile = File('${file.path}.coach.json');
      Map<String, dynamic>? summary;
      if (cacheFile.existsSync()) {
        final saved = jsonDecode(cacheFile.readAsStringSync());
        if (saved is Map<String, dynamic> &&
            saved['version'] == 1 &&
            saved['modified'] == stat.modified.millisecondsSinceEpoch)
          summary = saved;
      }
      // Filenames for app exports contain their date; old FITs need no decode.
      final dateMatch = RegExp(
        r'workout_(\d{4}-\d{2}-\d{2})',
      ).firstMatch(file.path);
      final fileDay = dateMatch == null
          ? null
          : DateTime.tryParse(dateMatch[1]!);
      if (summary == null &&
          fileDay != null &&
          fileDay.isBefore(cutoff.subtract(const Duration(days: 1))))
        continue;
      if (summary == null) {
        final fit = FitFile.fromBytes(file.readAsBytesSync());
        SessionMessage? session;
        final samples = <int, double>{};
        for (final record in fit.records) {
          final msg = record.message;
          if (msg is SessionMessage) session = msg;
          if (msg is RecordMessage &&
              msg.timestamp != null &&
              msg.power != null)
            samples[msg.timestamp! ~/ 1000] = msg.power!.toDouble();
        }
        if (session?.startTime == null) continue;
        final start = DateTime.fromMillisecondsSinceEpoch(session!.startTime!);
        // Older app exports have only start/end timestamps on the session.
        final seconds =
            (session.totalTimerTime ?? session.totalElapsedTime)?.round() ??
            (session.timestamp == null
                ? 0
                : (session.timestamp! - session.startTime!) ~/ 1000);
        if (seconds <= 0) continue;
        final sorted = samples.keys.toList()..sort();
        // Missing seconds remain unknown; do not turn long pauses into zeros.
        final powers = <double>[];
        for (var i = 0; i < sorted.length; i++) {
          final span = i + 1 < sorted.length
              ? (sorted[i + 1] - sorted[i]).clamp(1, 5)
              : 1;
          powers.addAll(List.filled(span, samples[sorted[i]]!));
        }
        final np =
            session.normalizedPower?.toDouble() ??
            (powers.isEmpty ? null : normalizedPower(powers));
        summary = {
          'version': 1,
          'modified': stat.modified.millisecondsSinceEpoch,
          'start': start.toIso8601String(),
          'seconds': seconds,
          'np': np,
          'ftp': session.thresholdPower,
          'tss': session.trainingStressScore,
        };
        try {
          cacheFile.writeAsStringSync(jsonEncode(summary));
        } catch (_) {
          /* A read-only folder can still supply ride history. */
        }
      }
      final start = DateTime.parse(summary['start'] as String);
      if (start.isBefore(cutoff) || start.isAfter(now)) continue;
      final seconds = (summary['seconds'] as num).toInt();
      final recordedFtp = (summary['ftp'] as num?)?.toDouble();
      final threshold = recordedFtp != null && recordedFtp > 0
          ? recordedFtp
          : ftp;
      final np = (summary['np'] as num?)?.toDouble();
      final recorded = (summary['tss'] as num?)?.toDouble();
      final tss =
          recorded ??
          (np == null || threshold <= 0
              ? null
              : seconds / 36 * math.pow(np / threshold, 2));
      rides.add(
        CoachRide(
          id: file.path,
          start: start,
          seconds: seconds,
          tss: tss?.toDouble(),
          estimated: recorded == null,
        ),
      );
    } catch (_) {
      /* A broken export must not prevent other rides from loading. */
    }
  }
  return rides;
}
