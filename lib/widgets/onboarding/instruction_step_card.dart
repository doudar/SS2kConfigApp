import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'onboarding_panel.dart';

Future<Uint8List?> _loadSvgBytes(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

double? _svgAspectRatio(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  final viewBoxMatch = RegExp(
    r'viewBox="[^"]*?([0-9.]+)[,\s]+([0-9.]+)"',
    caseSensitive: false,
  ).firstMatch(text);

  if (viewBoxMatch != null) {
    final width = double.tryParse(viewBoxMatch.group(1)!);
    final height = double.tryParse(viewBoxMatch.group(2)!);
    if (width != null && height != null && height > 0) {
      return width / height;
    }
  }

  final sizeMatch = RegExp(
    r'<svg[^>]*\swidth="([0-9.]+)[^"]*"[^>]*\sheight="([0-9.]+)',
    caseSensitive: false,
  ).firstMatch(text);

  if (sizeMatch != null) {
    final width = double.tryParse(sizeMatch.group(1)!);
    final height = double.tryParse(sizeMatch.group(2)!);
    if (width != null && height != null && height > 0) {
      return width / height;
    }
  }

  return null;
}

class InstructionStepCard extends StatelessWidget {
  final int? stepNumber;
  final String title;
  final String body;
  final String? imageAsset;
  final String? imagePlaceholderLabel;
  final Widget? trailing;

  const InstructionStepCard({
    Key? key,
    this.stepNumber,
    required this.title,
    required this.body,
    this.imageAsset,
    this.imagePlaceholderLabel,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 760;
    final imageTopGap = compact ? 10.0 : 16.0;
    final bodyTopGap = compact ? 8.0 : 12.0;
    final bodyStyle = TextStyle(
      fontSize: compact ? 14.5 : 16,
      height: compact ? 1.35 : 1.5,
      color: style.body,
    );

    return OnboardingPanel(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (stepNumber != null) ...[
                OnboardingBadge.number(stepNumber!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: style.foreground,
                    height: 1.18,
                  ),
                ),
              ),
            ],
          ),
          if (imageAsset != null) ...[
            SizedBox(height: imageTopGap),
            Align(
              alignment: Alignment.center,
              child: _buildImage(context, imageAsset!),
            ),
          ],
          SizedBox(height: bodyTopGap),
          Align(
            alignment: Alignment.center,
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(height: 8),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context, String assetPath) {
    final isSvg = assetPath.toLowerCase().endsWith('.svg');
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeightByWidth = screenSize.width * 0.72;
    final maxHeightByViewport = screenSize.height < 760
        ? screenSize.height * 0.36
        : screenSize.height * 0.46;
    final maxHeight = maxHeightByWidth
        .clamp(0.0, maxHeightByViewport)
        .toDouble();
    final style = OnboardingStyle.of(context);
    final imageBackground = style.imageBackground;

    if (isSvg) {
      return FutureBuilder<Uint8List?>(
        future: _loadSvgBytes(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _imageShell(
              maxHeight: maxHeight,
              aspectRatio: 16 / 9,
              backgroundColor: imageBackground,
              borderColor: style.imageBorder,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) return _placeholder(maxHeight);
          final aspectRatio = _svgAspectRatio(bytes) ?? 16 / 9;
          return _imageShell(
            maxHeight: maxHeight,
            aspectRatio: aspectRatio,
            backgroundColor: imageBackground,
            borderColor: style.imageBorder,
            child: InkWell(
              onTap: () => _openFullScreen(context, assetPath),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SvgPicture.memory(
                      bytes,
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  const _ZoomHintBadge(),
                ],
              ),
            ),
          );
        },
      );
    }

    return _imageShell(
      maxHeight: maxHeight,
      aspectRatio: 16 / 9,
      backgroundColor: imageBackground,
      borderColor: style.imageBorder,
      child: InkWell(
        onTap: () => _openFullScreen(context, assetPath),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                assetPath,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholder(maxHeight),
              ),
            ),
            const _ZoomHintBadge(),
          ],
        ),
      ),
    );
  }

  Widget _imageShell({
    required double maxHeight,
    required double aspectRatio,
    required Color backgroundColor,
    required Color borderColor,
    required Widget child,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(OnboardingPanel.radius),
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(OnboardingPanel.radius),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _placeholder([double? height]) {
    return Builder(
      builder: (context) {
        return Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: OnboardingStyle.of(context).placeholderBackground,
            borderRadius: BorderRadius.circular(OnboardingPanel.radius),
          ),
          child: Center(
            child: Text(
              imagePlaceholderLabel ?? 'Image unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: OnboardingStyle.of(context).muted,
                fontSize: 14,
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFullScreen(BuildContext context, String assetPath) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullScreenImage(assetPath: assetPath),
      ),
    );
  }
}

class _ZoomHintBadge extends StatelessWidget {
  const _ZoomHintBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      bottom: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.zoom_in, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Tap',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatefulWidget {
  final String assetPath;

  const _FullScreenImage({required this.assetPath});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hintController;
  late final Animation<double> _hintOpacity;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
    _hintOpacity =
        CurvedAnimation(parent: _hintController, curve: Curves.easeOut);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _hintController.reverse();
    });
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: SizedBox.expand(
                child: widget.assetPath.toLowerCase().endsWith('.svg')
                    ? SvgPicture.asset(
                        widget.assetPath,
                        fit: BoxFit.contain,
                      )
                    : Image.asset(widget.assetPath, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: padding.bottom + 24,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _hintOpacity,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.zoom_in, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Pinch to zoom',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
