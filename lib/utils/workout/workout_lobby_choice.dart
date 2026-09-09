import 'package:flutter/services.dart';
import '../../widgets/workout_library.dart';
import 'workout_parser.dart';
import 'workout_storage.dart';
import 'workout_training_load.dart';

/// A local launch choice, independent of scoring and any future player profile.
/// Keep the original workout content: selecting a card uses the normal loader.
class WorkoutLobbyChoice {
  WorkoutLobbyChoice({required this.content, required this.source})
    : workout = WorkoutParser.parseZwoFile(content);

  final String content;
  final String source;
  final WorkoutData workout;
  late final double? estimatedTss = WorkoutTrainingLoad.estimate(
    workout.segments,
  )?.tss;

  String get name => workout.name ?? 'Untitled workout';

  /// A small, cached shelf, not a second workout library or recommendation
  /// engine. Failure of one local entry must not hide the other choices.
  static Future<List<WorkoutLobbyChoice>> loadChoices() async {
    final choices = <WorkoutLobbyChoice>[];
    void add(String content, String source) {
      try {
        final choice = WorkoutLobbyChoice(content: content, source: source);
        if (choice.workout.segments.isNotEmpty &&
            !choices.any((other) => other.name == choice.name)) {
          choices.add(choice);
        }
      } catch (_) {
        // The full library remains available for managing invalid imports.
      }
    }

    try {
      final saved = await WorkoutStorage.getSavedWorkouts();
      saved.sort(
        (a, b) => ((b['timestamp'] as num?) ?? 0).compareTo(
          (a['timestamp'] as num?) ?? 0,
        ),
      );
      for (final entry in saved.take(3)) {
        final content = entry['content'];
        if (content is String) add(content, 'YOUR LIBRARY');
      }
    } catch (_) {
      // Still offer bundled workouts if the saved library cannot be read.
    }
    final assets = await WorkoutLibrary.loadAssetWorkouts();
    // Offer different lengths/intensities without implying a training plan.
    const featured = [
      'Recovery_Spin.zwo',
      'Tempo_Tuesday.zwo',
      'VO2_Blast.zwo',
    ];
    for (final filename in featured) {
      final matches = assets.where(
        (asset) => asset.path.endsWith('/$filename'),
      );
      if (matches.isEmpty) continue;
      try {
        add(await rootBundle.loadString(matches.first.path), 'BUILT-IN');
      } catch (_) {
        // Missing assets do not prevent starting the selected workout.
      }
    }
    return choices;
  }
}
