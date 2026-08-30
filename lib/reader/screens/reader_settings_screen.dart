import 'package:flutter/material.dart';

import '../models/doc_ref.dart';
import '../models/reader_settings.dart';

/// Discrete PDF controls; no animated switches or continuously repainting
/// sliders, keeping interaction predictable on an e-ink panel.
///
/// Only settings that actually affect the *current* mode are shown. The fit
/// mode itself is not repeated here: the reader menu overlay already offers
/// Height / Width / Zoom-Scroll.
class ReaderSettingsScreen extends StatefulWidget {
  final ReaderSettings initialSettings;
  final DocFormat format;

  const ReaderSettingsScreen({
    super.key,
    required this.initialSettings,
    this.format = DocFormat.pdf,
  });

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

  void _changeOverlap(double delta) {
    final overlap = (_settings.splitOverlap + delta).clamp(0.0, 0.20);
    setState(() => _settings = _settings.copyWith(splitOverlap: overlap));
  }

  void _save() => Navigator.of(context).pop(_settings);

  void _changeFontSize(int delta) {
    setState(
      () => _settings = _settings.copyWith(
        fontSizeStep: (_settings.fontSizeStep + delta).clamp(0, 7),
      ),
    );
  }

  void _changeLineHeight(double delta) {
    final value = (_settings.lineHeight + delta).clamp(1.2, 2.0);
    setState(
      () => _settings = _settings.copyWith(
        lineHeight: double.parse(value.toStringAsFixed(1)),
      ),
    );
  }

  List<Widget> _textControls() => [
    const _SectionLabel('Latin font'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final family in const ['Literata', 'EB Garamond', 'Inter'])
          _ChoiceButton(
            label: family,
            selected: _settings.latinFontFamily == family,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(latinFontFamily: family),
            ),
          ),
      ],
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Hebrew font'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final family in const [
          'Frank Ruhl Libre',
          'Noto Serif Hebrew',
          'Heebo',
        ])
          _ChoiceButton(
            label: family,
            selected: _settings.hebrewFontFamily == family,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(hebrewFontFamily: family),
            ),
          ),
      ],
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Text size'),
    _StepControl(
      value: '${_settings.fontSize.round()} pt',
      decreaseKey: const Key('reader-settings-font-smaller'),
      increaseKey: const Key('reader-settings-font-larger'),
      onDecrease: _settings.fontSizeStep == 0
          ? null
          : () => _changeFontSize(-1),
      onIncrease: _settings.fontSizeStep == 7 ? null : () => _changeFontSize(1),
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Line spacing'),
    _StepControl(
      value: _settings.lineHeight.toStringAsFixed(1),
      onDecrease: _settings.lineHeight <= 1.2
          ? null
          : () => _changeLineHeight(-0.1),
      onIncrease: _settings.lineHeight >= 2.0
          ? null
          : () => _changeLineHeight(0.1),
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Page margins'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < 4; index++)
          _ChoiceButton(
            label: const ['Tight', 'Normal', 'Wide', 'Extra'][index],
            selected: _settings.marginStep == index,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(marginStep: index),
            ),
          ),
      ],
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Paragraph layout'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChoiceButton(
          label: 'Blank line',
          selected: _settings.paragraphMode == ParagraphMode.blankLine,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(
              paragraphMode: ParagraphMode.blankLine,
            ),
          ),
        ),
        _ChoiceButton(
          label: 'First-line indent',
          selected: _settings.paragraphMode == ParagraphMode.firstLineIndent,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(
              paragraphMode: ParagraphMode.firstLineIndent,
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 28),
    const _SectionLabel('Text options'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChoiceButton(
          key: const Key('reader-settings-justify'),
          label: _settings.justify ? 'Justified' : 'Ragged edge',
          selected: _settings.justify,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(justify: !_settings.justify),
          ),
        ),
        _ChoiceButton(
          key: const Key('reader-settings-hyphenation'),
          label: _settings.hyphenate ? 'Hyphenation on' : 'Hyphenation off',
          selected: _settings.hyphenate,
          onPressed: () => setState(
            () =>
                _settings = _settings.copyWith(hyphenate: !_settings.hyphenate),
          ),
        ),
        _ChoiceButton(
          key: const Key('reader-settings-publisher-css'),
          label: _settings.honorPublisherCss
              ? 'Publisher style on'
              : 'Publisher style off',
          selected: _settings.honorPublisherCss,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(
              honorPublisherCss: !_settings.honorPublisherCss,
            ),
          ),
        ),
      ],
    ),
  ];

  /// Only the controls the active fit mode actually honours.
  List<Widget> _pdfControls(BuildContext context) {
    switch (_settings.fitMode) {
      case PdfFitMode.fitHeight:
        return [_cropControl()];

      case PdfFitMode.fitWidth:
        return [
          _cropControl(),
          const SizedBox(height: 28),
          const _SectionLabel('Fit-width overlap'),
          _overlapControl(context),
        ];

      case PdfFitMode.zoom:
        return [
          const _SectionLabel('Zoom out past the page'),
          _ChoiceButton(
            key: const Key('reader-settings-zoom-out'),
            label: _settings.allowZoomOutBeyondFit ? 'Enabled' : 'Disabled',
            selected: _settings.allowZoomOutBeyondFit,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(
                allowZoomOutBeyondFit: !_settings.allowZoomOutBeyondFit,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'When enabled, pinching in can shrink pages below the screen '
            'width so several can be skimmed at once. When disabled, the '
            'page never gets smaller than the screen width.',
          ),
          const SizedBox(height: 28),
          const Text(
            'Zoom / Scroll always scrolls continuously, always allows pinch '
            'zoom, and crops margins uniformly across the whole document, so '
            'it has no other options.',
          ),
        ];
    }
  }

  Widget _cropControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Automatic margin crop'),
        _ChoiceButton(
          key: const Key('reader-settings-crop'),
          label: _settings.autoCrop ? 'Enabled' : 'Disabled',
          selected: _settings.autoCrop,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(autoCrop: !_settings.autoCrop),
          ),
        ),
      ],
    );
  }

  Widget _overlapControl(BuildContext context) {
    return Row(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final textDocument = widget.format != DocFormat.pdf;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Text(textDocument ? 'Text settings' : 'PDF settings'),
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
          children: textDocument ? _textControls() : _pdfControls(context),
        ),
      ),
    );
  }
}

class _StepControl extends StatelessWidget {
  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final Key? decreaseKey;
  final Key? increaseKey;

  const _StepControl({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    this.decreaseKey,
    this.increaseKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(
          key: decreaseKey,
          onPressed: onDecrease,
          child: const Icon(Icons.remove),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        OutlinedButton(
          key: increaseKey,
          onPressed: onIncrease,
          child: const Icon(Icons.add),
        ),
      ],
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
