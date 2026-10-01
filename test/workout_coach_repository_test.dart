import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach.dart';
import 'package:ss2kconfigapp/utils/workout/workout_coach_repository.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('ss2k_coach_test_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temp.path,
    );
    WorkoutCoachRepository.invalidateLocal();
  });
  tearDown(() async {
    WorkoutCoachRepository.createClient = http.Client.new;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, null);
    await temp.delete(recursive: true);
  });

  test(
    'page data loads offline, remote calls are cached and scoped to the account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intervals_access_token', 'test-token');
      await prefs.setString('intervals_athlete_id', 'athlete-one');
      var requests = 0;
      WorkoutCoachRepository.createClient = () => MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('wellness')) {
          return http.Response(
            jsonEncode([
              {
                'id': DateTime.now().toIso8601String().substring(0, 10),
                'ctl': 46,
                'atl': 56,
                'sleepSecs': 28800,
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('activities')) {
          expect(
            request.url.queryParameters.keys,
            containsAll(['oldest', 'newest']),
          );
          return http.Response(
            jsonEncode([
              {
                'id': 'ride',
                'type': 'Ride',
                'start_date_local': DateTime.now()
                    .subtract(const Duration(days: 2))
                    .toIso8601String(),
                'moving_time': 3600,
                'icu_training_load': 50,
              },
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {
              'children': [
                {
                  'name': 'Remote endurance',
                  'type': 'Ride',
                  'workout_doc': {
                    'steps': [
                      {
                        'duration': 1800,
                        'power': {'value': 70, 'units': '%ftp'},
                      },
                    ],
                  },
                },
              ],
            },
          ]),
          200,
        );
      });
      final local = await WorkoutCoachRepository.load(200);
      expect(requests, 0);
      expect(
        local.candidates.any((c) => c.choice.source == 'BUILT-IN'),
        isTrue,
      );
      final remote = await WorkoutCoachRepository.load(
        200,
        refreshRemote: true,
      );
      expect(requests, 3);
      expect(remote.wellness!.single.form, -10);
      expect(remote.history.single.tss, 50);
      expect(
        remote.candidates.any((c) => c.choice.source == 'INTERVALS.ICU'),
        isTrue,
      );
      await WorkoutCoachRepository.load(200, refreshRemote: true);
      expect(requests, 3);
      await WorkoutCoachRepository.invalidateRemoteAttempt();
      await WorkoutCoachRepository.load(200, refreshRemote: true);
      // Explicit reconnect retries activity/wellness immediately; library stays cached.
      expect(requests, 5);
      await WorkoutCoachRepository.saveGoal(CoachGoal.performance);
      expect(
        (await WorkoutCoachRepository.load(200)).goal,
        CoachGoal.performance,
      );
      await prefs.setString('intervals_athlete_id', 'athlete-two');
      expect((await WorkoutCoachRepository.load(200)).history, isEmpty);
      expect((await WorkoutCoachRepository.load(200)).wellness, isEmpty);
      await prefs.remove('intervals_access_token');
      final disconnected = await WorkoutCoachRepository.load(
        200,
        refreshRemote: true,
      );
      expect(disconnected.history, isEmpty);
      expect(disconnected.wellness, isNull);
      expect(
        disconnected.candidates.any((c) => c.choice.source == 'INTERVALS.ICU'),
        isFalse,
      );
      expect(requests, 5);
    },
  );

  test(
    'old account permissions fall back to local rides without repeated requests',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intervals_access_token', 'test-token');
      await prefs.setString('intervals_athlete_id', 'legacy-athlete');
      var requests = 0;
      WorkoutCoachRepository.createClient = () => MockClient((request) async {
        requests++;
        return http.Response(
          request.url.path.endsWith('activities') ? '{}' : '[]',
          request.url.path.endsWith('activities') ? 403 : 200,
        );
      });
      final data = await WorkoutCoachRepository.load(200, refreshRemote: true);
      expect(data.needsReconnect, isTrue);
      expect(data.incomplete, isTrue);
      expect(data.candidates, isNotEmpty);
      await WorkoutCoachRepository.load(200, refreshRemote: true);
      expect(requests, 3);
    },
  );

  test(
    'real FIT history is decoded once, excludes in-progress rides, and uses sidecars',
    () async {
      final folder = Directory('${temp.path}/workouts')..createSync();
      final file = await File(
        'test/workout_2026-09-04T16-50-06.455642.fit',
      ).copy('${folder.path}/workout_2026-09-04T16-50-06.455642.fit');
      await File(
        '${folder.path}/workout_in_progress_pending.jsonl',
      ).writeAsString('{}');
      final args = {
        'directory': temp.path,
        'ftp': 200.0,
        'now': DateTime(2026, 9, 5).millisecondsSinceEpoch,
      };
      final watch = Stopwatch()..start();
      final first = readCoachHistory(args);
      watch.stop();
      expect(first, hasLength(1));
      expect(first.single.tss, greaterThan(0));
      expect(File('${file.path}.coach.json').existsSync(), isTrue);
      final cached = readCoachHistory(args);
      expect(cached.single.tss, first.single.tss);
      expect(
        readCoachHistory({
          ...args,
          'now': DateTime(2027).millisecondsSinceEpoch,
        }),
        isEmpty,
      );
      // ignore: avoid_print
      print('Cold single-FIT history decode: ${watch.elapsedMilliseconds} ms');
    },
  );

  test(
    'wellness permission failure preserves rides, and stale recovery is ignored',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('intervals_access_token', 'test-token');
      await prefs.setString('intervals_athlete_id', 'recovery-athlete');
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await prefs.setString(
        'workout_coach_remote_recovery-athlete',
        jsonEncode({
          'wellnessAt': old.toIso8601String(),
          'wellness': [
            {
              'id': DateTime.now().toIso8601String().substring(0, 10),
              'ctl': 46,
              'atl': 100,
              'fatigue': 4,
            },
          ],
        }),
      );
      expect((await WorkoutCoachRepository.load(200)).wellness, isEmpty);
      WorkoutCoachRepository.createClient = () => MockClient(
        (request) async => http.Response(
          '[]',
          request.url.path.endsWith('wellness') ? 403 : 200,
        ),
      );
      final result = await WorkoutCoachRepository.load(
        200,
        refreshRemote: true,
      );
      expect(result.needsReconnect, isTrue);
      expect(result.incomplete, isFalse);
      expect(result.wellness, isEmpty);
      expect(result.candidates, isNotEmpty);
      final cache = jsonDecode(
        prefs.getString('workout_coach_remote_recovery-athlete')!,
      );
      expect(cache.containsKey('wellness'), isFalse);
    },
  );
}
