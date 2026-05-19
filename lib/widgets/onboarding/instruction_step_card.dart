import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

Future<Uint8List?> _loadSvgBytes(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
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
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (stepNumber != null) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      '$stepNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (imageAsset != null) ...[
              const SizedBox(height: 16),
              _buildImage(context, imageAsset!),
            ],
            const SizedBox(height: 12),
            Text(
              body,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            if (trailing != null) ...[
              const SizedBox(height: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, String assetPath) {
    final isSvg = assetPath.toLowerCase().endsWith('.svg');
    final maxHeight = MediaQuery.of(context).size.width * 0.75;

    if (isSvg) {
      return FutureBuilder<Uint8List?>(
        future: _loadSvgBytes(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SizedBox(height: maxHeight);
          }
          final bytes = snapshot.data;
          if (bytes == null) return _placeholder(maxHeight);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _openFullScreen(context, assetPath),
                child: SvgPicture.memory(
                  bytes,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _openFullScreen(context, assetPath),
          child: Image.asset(
            assetPath,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) => _placeholder(maxHeight),
          ),
        ),
      ),
    );
  }

  Widget _placeholder([double? height]) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          imagePlaceholderLabel ?? 'Image unavailable',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ),
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
