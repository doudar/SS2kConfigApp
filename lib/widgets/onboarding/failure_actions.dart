import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/onboarding/wizard_session.dart';

class FailureActions extends StatelessWidget {
  final VoidCallback onTryAgain;
  final PageController pageController;

  const FailureActions({
    Key? key,
    required this.onTryAgain,
    required this.pageController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton(
          onPressed: onTryAgain,
          child: const Text('Try Again'),
        ),
        TextButton(
          onPressed: () async {
            final url = Uri.parse(
                'https://docs.smartspin2k.com/documentation/troubleshooting');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text("It's Not Working"),
        ),
        TextButton(
          onPressed: () {
            session.reset();
            pageController.jumpToPage(0);
          },
          child: const Text('Start Over'),
        ),
      ],
    );
  }
}
