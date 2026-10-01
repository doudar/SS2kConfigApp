import 'package:flutter/material.dart';

/// Names an in-app copy or an exported file and makes replacement explicit.
class SettingsBackupNameDialog extends StatefulWidget {
  const SettingsBackupNameDialog({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.existingNames = const [],
    this.initialName = '',
    this.isExport = false,
  });

  final String title;
  final String description;
  final String actionLabel;
  final List<String> existingNames;
  final String initialName;
  final bool isExport;

  @override
  State<SettingsBackupNameDialog> createState() =>
      _SettingsBackupNameDialogState();
}

class _SettingsBackupNameDialogState extends State<SettingsBackupNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name {
    final name = _controller.text.trim();
    return widget.isExport && name.toLowerCase().endsWith('.ss2k')
        ? name.substring(0, name.length - 5).trim()
        : name;
  }

  bool get _invalidFileName =>
      widget.isExport && RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(_name);

  void _submit() {
    if (_name.isNotEmpty && !_invalidFileName) {
      Navigator.of(context).pop(_name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final replacesCopy = widget.existingNames.contains(_name);
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.isExport ? 'File name' : 'Copy name',
                hintText: 'e.g. My bike setup',
                border: const OutlineInputBorder(),
                suffixText: widget.isExport ? '.ss2k' : null,
                errorText: _invalidFileName
                    ? 'Use a name without symbols like / or :.'
                    : null,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (replacesCopy) ...[
              const SizedBox(height: 12),
              Text(
                'The saved copy “$_name” will be replaced.',
                style: TextStyle(color: colors.error),
              ),
            ],
            if (widget.existingNames.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Or choose a saved copy to replace',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final name in widget.existingNames)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(name),
                  selected: name == _name,
                  selectedTileColor: colors.secondaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onTap: () => setState(() => _controller.text = name),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.isEmpty || _invalidFileName ? null : _submit,
          child: Text(replacesCopy ? 'Replace saved copy' : widget.actionLabel),
        ),
      ],
    );
  }
}
