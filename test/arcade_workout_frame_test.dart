import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/arcade/arcade_workout_frame.dart';

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount, required this.child});
  final VoidCallback onMount;
  final Widget child;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  testWidgets(
    'playing covers header; pause restores it without remounting the header or game',
    (tester) async {
      var expanded = false;
      var arcade = true;
      var headerMounts = 0, gameMounts = 0, headerTaps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: 24)),
                child: ArcadeWorkoutFrame(
                  header: PreferredSize(
                    preferredSize: const Size.fromHeight(56),
                    child: _MountProbe(
                      onMount: () => headerMounts++,
                      child: AppBar(
                        title: TextButton(
                          onPressed: () => headerTaps++,
                          child: const Text('DEVICE HEADER'),
                        ),
                      ),
                    ),
                  ),
                  body: const ColoredBox(
                    key: ValueKey('classic'),
                    color: Colors.white,
                  ),
                  expanded: expanded,
                  overlay: const SizedBox.shrink(),
                  arcade: arcade
                      ? _MountProbe(
                          onMount: () => gameMounts++,
                          child: ColoredBox(
                            key: const ValueKey('arcade-content'),
                            color: Colors.black,
                            child: Center(
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => expanded = false),
                                child: const Text('PAUSE'),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final game = find.byKey(const ValueKey('arcade-content'));
      final classic = find.byKey(const ValueKey('classic'));
      expect(tester.getTopLeft(game).dy, 80);
      expect(tester.getTopLeft(classic).dy, 80);
      await tester.tap(find.text('DEVICE HEADER'));
      expect(headerTaps, 1);
      final headerPoint = tester.getCenter(find.text('DEVICE HEADER'));

      update(() => expanded = true);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(game).dy,
        24,
        reason: 'Only the real status-bar inset remains',
      );
      expect(
        tester.getTopLeft(classic).dy,
        80,
        reason: 'Classic thumbnail layout stays stable',
      );
      await tester.tapAt(headerPoint);
      expect(
        headerTaps,
        1,
        reason: 'Covered device actions must not receive taps',
      );
      expect(headerMounts, 1, reason: 'Connection monitoring must not restart');
      expect(
        gameMounts,
        1,
        reason: 'Gameplay, music and animation state must survive expansion',
      );

      await tester.tap(find.text('PAUSE'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(game).dy, 80);
      await tester.tap(find.text('DEVICE HEADER'));
      expect(headerTaps, 2);
      expect(headerMounts, 1);
      expect(gameMounts, 1);

      update(() {
        expanded = true;
        arcade = false;
      });
      await tester.pumpAndSettle();
      expect(game, findsNothing);
      await tester.tap(find.text('DEVICE HEADER'));
      expect(headerTaps, 3, reason: 'Classic always shows the header');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion changes header coverage immediately', (
    tester,
  ) async {
    var expanded = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: true, padding: EdgeInsets.zero),
              child: ArcadeWorkoutFrame(
                header: AppBar(title: const Text('Header')),
                body: const SizedBox.expand(),
                overlay: const SizedBox.shrink(),
                expanded: expanded,
                arcade: const ColoredBox(
                  key: ValueKey('game'),
                  color: Colors.black,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => expanded = true);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('game'))).dy, 0);
    update(() => expanded = false);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('game'))).dy,
      kToolbarHeight,
    );
  });
}
