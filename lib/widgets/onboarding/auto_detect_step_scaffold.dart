import 'package:flutter/material.dart';
import 'failure_actions.dart';

class AutoDetectStepScaffold extends StatefulWidget {
  final Widget child;
  final VoidCallback onTryAgain;
  final PageController pageController;

  const AutoDetectStepScaffold({
    Key? key,
    required this.child,
    required this.onTryAgain,
    required this.pageController,
  }) : super(key: key);

  @override
  State<AutoDetectStepScaffold> createState() => AutoDetectStepScaffoldState();
}

class AutoDetectStepScaffoldState extends State<AutoDetectStepScaffold> {
  bool _showFallback = false;

  void show() {
    if (mounted) setState(() => _showFallback = true);
  }

  void dismiss() {
    if (mounted) setState(() => _showFallback = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showFallback)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Having trouble?',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        FailureActions(
                          onTryAgain: () {
                            dismiss();
                            widget.onTryAgain();
                          },
                          pageController: widget.pageController,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
