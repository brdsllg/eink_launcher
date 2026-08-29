import 'package:flutter/material.dart';

import '../models/reader_settings.dart';

/// Discrete PDF controls; no animated switches or continuously repainting
/// sliders, keeping interaction predictable on an e-ink panel.
class ReaderSettingsScreen extends StatefulWidget {
  final ReaderSettings initialSettings;

  const ReaderSettingsScreen({super.key, required this.initialSettings});

  @override
  State<ReaderSettingsScreen> createState() => _ReaderSettingsScreenState();
}

class _ReaderSettingsScreenState extends State<ReaderSettingsScreen> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _setFitMode(PdfFitMode mode) {
    setState(() => _settings = _settings.copyWith(fitMode: mode));
  }

  void _changeOverlap(double delta) {
    final overlap = (_settings.splitOverlap + delta).clamp(0.0, 0.20);
    setState(() => _settings = _settings.copyWith(splitOverlap: overlap));
  }

  void _save() => Navigator.of(context).pop(_settings);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: const Text('PDF settings'),
        centerTitle: true,
        actions: [
          TextButton(
            key: const Key('reader-settings-save'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
        shape: const Border(
          bottom: BorderSide(color: Colors.black, width: 1.5),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            const _SectionLabel('Page fit'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChoiceButton(
                  label: 'Fit height',
                  selected: _settings.fitMode == PdfFitMode.fitHeight,
                  onPressed: () => _setFitMode(PdfFitMode.fitHeight),
                ),
                _ChoiceButton(
                  label: 'Fit width',
                  selected: _settings.fitMode == PdfFitMode.fitWidth,
                  onPressed: () => _setFitMode(PdfFitMode.fitWidth),
                ),
                _ChoiceButton(
                  label: 'Continuous',
                  selected: _settings.fitMode == PdfFitMode.continuousScroll,
                  onPressed: () => _setFitMode(PdfFitMode.continuousScroll),
                ),
                _ChoiceButton(
                  label: 'Free zoom',
                  selected: _settings.fitMode == PdfFitMode.freeZoom,
                  onPressed: () => _setFitMode(PdfFitMode.freeZoom),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _SectionLabel('Automatic margin crop'),
            _ChoiceButton(
              key: const Key('reader-settings-crop'),
              label: _settings.autoCrop ? 'Enabled' : 'Disabled',
              selected: _settings.autoCrop,
              onPressed: () => setState(
                () => _settings = _settings.copyWith(
                  autoCrop: !_settings.autoCrop,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const _SectionLabel('Continuous-scroll momentum'),
            _ChoiceButton(
              key: const Key('reader-settings-momentum'),
              label: _settings.scrollMomentum ? 'Enabled' : 'Disabled',
              selected: _settings.scrollMomentum,
              onPressed: () => setState(
                () => _settings = _settings.copyWith(
                  scrollMomentum: !_settings.scrollMomentum,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Disabled stops the page immediately when a drag is released.',
            ),
            const SizedBox(height: 28),
            const _SectionLabel('Fit-width overlap'),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _settings.splitOverlap <= 0
                      ? null
                      : () => _changeOverlap(-0.01),
                  child: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    '${(_settings.splitOverlap * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                OutlinedButton(
                  onPressed: _settings.splitOverlap >= 0.20
                      ? null
                      : () => _changeOverlap(0.01),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _ChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? Colors.black : Colors.white,
        foregroundColor: selected ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      child: Text(label),
    );
  }
}
