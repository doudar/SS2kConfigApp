import 'package:flutter/material.dart';
import 'workout_dialog.dart';
import '../utils/workout/workout_tts_settings.dart';

class AudioCoachDialog extends StatefulWidget {
  final WorkoutTTSSettings ttsSettings;

  const AudioCoachDialog({Key? key, required this.ttsSettings}) : super(key: key);

  @override
  State<AudioCoachDialog> createState() => _AudioCoachDialogState();
}

class _AudioCoachDialogState extends State<AudioCoachDialog> {
  List<String> _voices = [];
  List<String> _engines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVoicesAndEngines();
  }

  Future<void> _loadVoicesAndEngines() async {
    if (widget.ttsSettings.isAndroid) {
      final engines = await widget.ttsSettings.getAvailableEngines();
      if (!mounted) return;
      setState(() {
        _engines = engines.toSet().toList();
      });
    }

    final voices = await widget.ttsSettings.getAvailableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices.toSet().toList();
      _loading = false;
    });
  }

  Future<void> _testVoice() async {
    await widget.ttsSettings.speakTest("This is a test of the audio coach voice.");
  }

  String? _getValidVoice() {
    final currentVoice = widget.ttsSettings.voice;
    if (currentVoice != null && _voices.contains(currentVoice)) {
      return currentVoice;
    }
    return _voices.isNotEmpty ? _voices.first : null;
  }

  String? _getValidEngine() {
    final currentEngine = widget.ttsSettings.engine;
    if (currentEngine != null && _engines.contains(currentEngine)) {
      return currentEngine;
    }
    return _engines.isNotEmpty ? _engines.first : null;
  }

  @override
  Widget build(BuildContext context) {
    return WorkoutDialog(
      title: const Text('Voice coach'),
      icon: Icons.record_voice_over_rounded,
      subtitle: 'Make your in-ride guidance sound right for you.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkoutSettingsPanel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Audio Coach'),
              value: widget.ttsSettings.enabled,
              onChanged: (value) async {
                await widget.ttsSettings.setEnabled(value);
                if (mounted) setState(() {});
              },
            ),
          ),
          if (widget.ttsSettings.enabled) ...[
            const SizedBox(height: 16),
            WorkoutSettingSlider(
              label: 'Voice Volume',
              valueLabel: '${(widget.ttsSettings.volume * 100).round()}%',
              value: widget.ttsSettings.volume,
              min: 0,
              max: 1,
              divisions: 10,
              onChanged: (value) async {
                await widget.ttsSettings.setVolume(value);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 16),
            WorkoutSettingSlider(
              label: 'Speech Rate',
              valueLabel: '${(widget.ttsSettings.rate * 100).round()}%',
              value: widget.ttsSettings.rate,
              min: .1,
              max: 1,
              divisions: 9,
              onChanged: (value) async {
                await widget.ttsSettings.setRate(value);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 16),
            WorkoutSettingSlider(
              label: 'Voice Pitch',
              valueLabel: '${(widget.ttsSettings.pitch * 100).round()}%',
              value: widget.ttsSettings.pitch,
              min: .5,
              max: 2,
              divisions: 15,
              onChanged: (value) async {
                await widget.ttsSettings.setPitch(value);
                if (mounted) setState(() {});
              },
            ),
            if (widget.ttsSettings.isAndroid) ...[
              const SizedBox(height: 16),
              const Text('Select Speech Engine'),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_engines.isEmpty)
                const Text('No engines available')
              else
                DropdownButton<String>(
                  value: _getValidEngine(),
                  isExpanded: true,
                  hint: const Text('Select an engine'),
                  items: _engines.map((engine) {
                    return DropdownMenuItem(
                      value: engine,
                      child: Text(engine, maxLines: 1, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      await widget.ttsSettings.setEngine(value);
                      if (!mounted) return;
                      setState(() {
                        _loading = true;
                        _voices = [];
                      });
                      final voices = await widget.ttsSettings.getAvailableVoices();
                      if (!mounted) return;
                      setState(() {
                        _voices = voices.toSet().toList();
                        _loading = false;
                      });
                    }
                  },
                ),
            ],
            const SizedBox(height: 16),
            const Text('Select Voice'),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_voices.isEmpty)
              const Text('No voices available')
            else
              DropdownButton<String>(
                value: _getValidVoice(),
                isExpanded: true,
                hint: const Text('Select a voice'),
                items: _voices.map((voice) {
                  return DropdownMenuItem(
                    value: voice,
                    child: Text(voice, maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    await widget.ttsSettings.setVoice(value);
                    if (mounted) setState(() {});
                  }
                },
              ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton(onPressed: _testVoice, child: const Text('Test Voice')),
            ),
          ],
        ],
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE'))],
    );
  }
}
