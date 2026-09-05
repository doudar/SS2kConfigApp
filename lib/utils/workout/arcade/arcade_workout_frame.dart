import 'package:flutter/material.dart';

/// Expands Arcade over the app bar without unmounting either the device header
/// (which owns connection monitoring) or the running Arcade view.
class ArcadeWorkoutFrame extends StatelessWidget {
  const ArcadeWorkoutFrame({
    super.key,
    required this.header,
    required this.body,
    required this.overlay,
    required this.expanded,
    this.arcade,
  });

  final PreferredSizeWidget header;
  final Widget body, overlay;
  final Widget? arcade;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final full = arcade != null && expanded;
    final headerHeight = header.preferredSize.height + media.padding.top;
    final duration = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return Scaffold(
      // A stable body origin lets only Arcade animate into the header space.
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: header.preferredSize,
        child: ExcludeSemantics(
          excluding: full,
          child: ExcludeFocus(
            excluding: full,
            child: IgnorePointer(
              ignoring: full,
              child: AnimatedOpacity(
                opacity: full ? 0 : 1,
                duration: duration,
                child: header,
              ),
            ),
          ),
        ),
      ),
      // extendBodyBehindAppBar supplies app-bar-sized top padding. Restore the
      // real device insets so the expanded controls only avoid the status bar.
      body: MediaQuery(
        data: media,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              top: headerHeight,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: body,
              ),
            ),
            if (arcade != null)
              AnimatedPositioned(
                key: const ValueKey('arcade-viewport'),
                duration: duration,
                curve: Curves.easeInOutCubic,
                top: full ? 0 : headerHeight,
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: const Color(0xff080f21),
                  child: SafeArea(
                    top: full,
                    bottom: false,
                    left: false,
                    right: false,
                    child: arcade!,
                  ),
                ),
              ),
            AnimatedPositioned(
              key: const ValueKey('workout-text-viewport'),
              duration: arcade == null ? Duration.zero : duration,
              curve: Curves.easeInOutCubic,
              top: full ? media.padding.top : headerHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: overlay,
            ),
          ],
        ),
      ),
    );
  }
}
