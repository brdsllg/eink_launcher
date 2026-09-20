import 'package:flutter/material.dart';

import '../../widgets/adaptive_grid.dart';
import '../../widgets/control_bar_row.dart';
import '../models/doc_ref.dart';
import '../models/parsed_book.dart';
import '../models/reader_settings.dart';

/// Discrete controls with a grid appropriate to each choice group. The active
/// fit mode itself lives in the reader's Height / Width / Zoom-Scroll bar.
class ReaderSettingsScreen extends StatefulWidget {
  final ReaderSettings initialSettings;
  final DocFormat format;
  final VoidCallback? onBackToText;
  final List<String> studySources;
  final List<StudyTranslationOption> studyTranslations;
  final String? primaryStudyTranslationId;

  const ReaderSettingsScreen({
    super.key,
    required this.initialSettings,
    this.format = DocFormat.pdf,
    this.onBackToText,
    this.studySources = const [],
    this.studyTranslations = const [],
    this.primaryStudyTranslationId,
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
    final ids = widget.studyTranslations.map((option) => option.id).toSet();
    if (widget.studyTranslations.isNotEmpty &&
        !ids.contains(_settings.studyTranslation)) {
      final primary = widget.primaryStudyTranslationId;
      final legacy = widget.studyTranslations
          .where((option) => option.label == _settings.studyTranslation)
          .firstOrNull;
      _settings = _settings.copyWith(
        studyTranslation: legacy?.id ??
            (primary != null && ids.contains(primary)
            ? primary
            : widget.studyTranslations.first.id),
      );
    }
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
    if (widget.onBackToText != null)
      TextButton(
        onPressed: widget.onBackToText,
        child: const Text("Back to previous reading position"),
      ),
    if (widget.studySources.isNotEmpty ||
        widget.studyTranslations.isNotEmpty) ...[
      SwitchListTile(
        title: const Text('Inline commentary'),
        value: _settings.inlineCommentary,
        onChanged: (value) => setState(
          () => _settings = _settings.copyWith(inlineCommentary: value),
        ),
      ),
      const Text(
        'Selected commentary appears after each verse. If a language or translation is missing, the available text is kept.',
      ),
      _StudySelector(
        label: 'Commentary language',
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _settings.commentaryLanguage,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'both', child: Text('Hebrew and English')),
            DropdownMenuItem(value: 'he', child: Text('Hebrew')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (value) => setState(
            () => _settings = _settings.copyWith(commentaryLanguage: value),
          ),
        ),
      ),
      if (widget.studyTranslations.isNotEmpty)
        _StudySelector(
          label: 'Main translation',
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _settings.studyTranslation,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final option in widget.studyTranslations)
                DropdownMenuItem(
                  value: option.id,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(studyTranslation: value),
            ),
          ),
        ),
      ExpansionTile(
        title: const Text('Commentary sources'),
        subtitle: Text(
          _settings.commentarySources.isEmpty
              ? 'All sources'
              : '${_settings.commentarySources.length} selected',
        ),
        children: [
          TextButton(
            onPressed: () => setState(
              () => _settings = _settings.copyWith(
                commentarySources: [],
                inlineCommentary: true,
              ),
            ),
            child: const Text('Show all sources'),
          ),
          for (final source in widget.studySources)
            CheckboxListTile(
              title: Text(source),
              value:
                  _settings.inlineCommentary &&
                  (_settings.commentarySources.isEmpty ||
                      _settings.commentarySources.contains(source)),
              onChanged: (value) => setState(() {
                final selected =
                    (!_settings.inlineCommentary
                            ? <String>[]
                            : _settings.commentarySources.isEmpty
                            ? widget.studySources
                            : _settings.commentarySources)
                        .toSet();
                if (value == true) {
                  selected.add(source);
                } else {
                  selected.remove(source);
                }
                _settings = _settings.copyWith(
                  commentarySources: selected.toList(),
                  inlineCommentary: selected.isNotEmpty,
                );
              }),
            ),
        ],
      ),
      const SizedBox(height: 20),
    ],
    _SettingsGroup(
      label: 'Latin font',
      child: GridActions(
        minCellWidth: 96,
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
    ),
    _SettingsGroup(
      label: 'Hebrew font',
      child: GridActions(
        minCellWidth: 96,
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
    ),
    _SettingsGroup(
      label: 'Text size',
      child: _StepControl(
        value: '${_settings.fontSize.round()} pt',
        decreaseKey: const Key('reader-settings-font-smaller'),
        increaseKey: const Key('reader-settings-font-larger'),
        onDecrease: _settings.fontSizeStep == 0
            ? null
            : () => _changeFontSize(-1),
        onIncrease: _settings.fontSizeStep == 7
            ? null
            : () => _changeFontSize(1),
      ),
    ),
    _SettingsGroup(
      label: 'Line spacing',
      child: _StepControl(
        value: _settings.lineHeight.toStringAsFixed(1),
        onDecrease: _settings.lineHeight <= 1.2
            ? null
            : () => _changeLineHeight(-0.1),
        onIncrease: _settings.lineHeight >= 2.0
            ? null
            : () => _changeLineHeight(0.1),
      ),
    ),
    _SettingsGroup(
      label: 'Page margins',
      child: GridActions(
        minCellWidth: 64,
        maxColumns: 4,
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
    ),
    _SettingsGroup(
      label: 'Paragraph layout',
      child: GridActions(
        minCellWidth: 120,
        maxColumns: 2,
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
    ),
    _SettingsGroup(
      label: 'Text options',
      child: GridActions(
        minCellWidth: 96,
        children: [
          _ChoiceButton(
            key: const Key('reader-settings-justify'),
            toggle: true,
            label: _settings.justify ? 'Justified' : 'Ragged edge',
            selected: _settings.justify,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(justify: !_settings.justify),
            ),
          ),
          _ChoiceButton(
            key: const Key('reader-settings-hyphenation'),
            toggle: true,
            label: _settings.hyphenate ? 'Hyphenation on' : 'Hyphenation off',
            selected: _settings.hyphenate,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(
                hyphenate: !_settings.hyphenate,
              ),
            ),
          ),
          _ChoiceButton(
            key: const Key('reader-settings-publisher-css'),
            toggle: true,
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
    ),
  ];

  /// Only the controls the active fit mode actually honours.
  List<Widget> _pdfControls() {
    switch (_settings.fitMode) {
      case PdfFitMode.fitHeight:
        return [_cropControl()];
      case PdfFitMode.fitWidth:
        return [
          _cropControl(),
          _overlapControl('Fit-width overlap'),
          _overlapGuideControl(),
        ];
      case PdfFitMode.zoom:
        return [
          _overlapControl('Scroll-step overlap'),
          _overlapGuideControl(),
          _SettingsGroup(
            label: 'Zoom out past the page',
            child: GridActions(
              children: [
                _ChoiceButton(
                  key: const Key('reader-settings-zoom-out'),
                  toggle: true,
                  label: _settings.allowZoomOutBeyondFit
                      ? 'Enabled'
                      : 'Disabled',
                  selected: _settings.allowZoomOutBeyondFit,
                  onPressed: () => setState(
                    () => _settings = _settings.copyWith(
                      allowZoomOutBeyondFit: !_settings.allowZoomOutBeyondFit,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'When enabled, pinching in can shrink pages below the screen '
            'width so several can be skimmed at once. When disabled, the '
            'page never gets smaller than the screen width.',
          ),
          const SizedBox(height: 20),
          const Text(
            'Zoom / Scroll always scrolls continuously, always allows pinch '
            'zoom, and crops margins uniformly across the whole document, so '
            'these geometry options are fixed.',
          ),
        ];
    }
  }

  Widget _overlapControl(String label) => _SettingsGroup(
    label: label,
    child: _StepControl(
      value: '${(_settings.splitOverlap * 100).round()}%',
      decreaseKey: const Key('reader-settings-overlap-decrease'),
      increaseKey: const Key('reader-settings-overlap-increase'),
      onDecrease: _settings.splitOverlap <= 0
          ? null
          : () => _changeOverlap(-0.01),
      onIncrease: _settings.splitOverlap >= 0.20
          ? null
          : () => _changeOverlap(0.01),
    ),
  );

  Widget _overlapGuideControl() => _SettingsGroup(
    label: 'Reading continuation arrows',
    child: GridActions(
      children: [
        _ChoiceButton(
          key: const Key('reader-settings-overlap-guide'),
          toggle: true,
          label: _settings.overlapGuideEnabled ? 'Enabled' : 'Disabled',
          selected: _settings.overlapGuideEnabled,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(
              overlapGuideEnabled: !_settings.overlapGuideEnabled,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _navigationControls() => [
    _SettingsGroup(
      label: 'Left / right page-turn tap zones',
      child: GridActions(
        children: [
          _ChoiceButton(
            key: const Key('reader-settings-tap-zones'),
            toggle: true,
            label: _settings.pageTurnTapZonesEnabled ? 'Enabled' : 'Disabled',
            selected: _settings.pageTurnTapZonesEnabled,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(
                pageTurnTapZonesEnabled: !_settings.pageTurnTapZonesEnabled,
              ),
            ),
          ),
        ],
      ),
    ),
    _SettingsGroup(
      label: 'Physical page buttons',
      child: GridActions(
        children: [
          _ChoiceButton(
            key: const Key('reader-settings-page-buttons'),
            toggle: true,
            label: _settings.pageButtonsEnabled ? 'Enabled' : 'Disabled',
            selected: _settings.pageButtonsEnabled,
            onPressed: () => setState(
              () => _settings = _settings.copyWith(
                pageButtonsEnabled: !_settings.pageButtonsEnabled,
              ),
            ),
          ),
        ],
      ),
    ),
  ];

  Widget _cropControl() => _SettingsGroup(
    label: 'Automatic margin crop',
    child: GridActions(
      children: [
        _ChoiceButton(
          key: const Key('reader-settings-crop'),
          toggle: true,
          label: _settings.autoCrop ? 'Enabled' : 'Disabled',
          selected: _settings.autoCrop,
          onPressed: () => setState(
            () => _settings = _settings.copyWith(autoCrop: !_settings.autoCrop),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final textDocument = widget.format != DocFormat.pdf;
    return Scaffold(
      appBar: GridAppBar(
        leadingWidth: 56,
        actionWidth: 88,
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Text(textDocument ? 'Text settings' : 'PDF settings'),
        actions: [
          TextButton(
            key: const Key('reader-settings-save'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsGroup(
                  label: 'Page color',
                  child: GridActions(
                    children: [
                      _ChoiceButton(
                        key: const Key('reader-settings-color'),
                        toggle: true,
                        label: _settings.colorEnabled
                            ? 'Color'
                            : 'Black and white',
                        selected: _settings.colorEnabled,
                        onPressed: () => setState(
                          () => _settings = _settings.copyWith(
                            colorEnabled: !_settings.colorEnabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!textDocument) ...[
                  _SettingsGroup(
                    label: 'Image dithering',
                    child: GridActions(
                      children: [
                        _ChoiceButton(
                          key: const Key('reader-settings-dithering'),
                          toggle: true,
                          label: _settings.pdfDithering
                              ? 'Dithering on'
                              : 'Dithering off',
                          selected: _settings.pdfDithering,
                          onPressed: () => setState(
                            () => _settings = _settings.copyWith(
                              pdfDithering: !_settings.pdfDithering,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: Text(
                      'Try dithering for scanned pages and photos with banded gradients. '
                      'It also works in color; leave it off if your device already smooths images well.',
                    ),
                  ),
                ],
                ...textDocument ? _textControls() : _pdfControls(),
                ..._navigationControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudySelector extends StatelessWidget {
  final String label;
  final Widget child;

  const _StudySelector({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        child,
      ],
    ),
  );
}

/// Portrait keeps the complete width for choices. Wider screens line up the
/// setting labels in a fixed column so each group's controls start together.
class _SettingsGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsGroup({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final text = Text(
          label,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        );
        if (constraints.maxWidth >= 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 176,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
                  child: text,
                ),
              ),
              Expanded(child: child),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: 8), child: text),
            child,
          ],
        );
      },
    ),
  );
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
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
    child: ControlBarRow(
      children: [
        SizedBox(
          width: 56,
          child: OutlinedButton(
            key: decreaseKey,
            onPressed: onDecrease,
            style: _cellButtonStyle,
            child: const Icon(Icons.remove),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(value, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        SizedBox(
          width: 56,
          child: OutlinedButton(
            key: increaseKey,
            onPressed: onIncrease,
            style: _cellButtonStyle,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    ),
  );
}

final _cellButtonStyle = OutlinedButton.styleFrom(
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  side: BorderSide.none,
  shape: const RoundedRectangleBorder(),
);

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool toggle;
  final VoidCallback onPressed;

  const _ChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    this.toggle = false,
    required this.onPressed,
  });

  bool _reversesWhilePressed(Set<WidgetState> states) =>
      states.contains(WidgetState.pressed) && (!selected || toggle);

  Color _background(Set<WidgetState> states) {
    if (_reversesWhilePressed(states)) {
      return selected ? Colors.white : Colors.black;
    }
    return selected ? Colors.black : Colors.white;
  }

  Color _foreground(Set<WidgetState> states) {
    if (_reversesWhilePressed(states)) {
      return selected ? Colors.black : Colors.white;
    }
    return selected ? Colors.white : Colors.black;
  }

  @override
  Widget build(BuildContext context) => Padding(
    // Keep adjacent selected options visibly separate inside the black grid.
    padding: const EdgeInsets.all(1),
    child: OutlinedButton(
      onPressed: onPressed,
      style: _cellButtonStyle.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(_background),
        foregroundColor: WidgetStateProperty.resolveWith(_foreground),
      ),
      child: Text(label, textAlign: TextAlign.center, maxLines: 2),
    ),
  );
}
