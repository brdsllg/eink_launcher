import 'package:flutter/material.dart';

import '../models/reader_settings.dart';

class ReaderMenuOverlay extends StatelessWidget {
  final String title;
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final VoidCallback onCloseReader;
  final VoidCallback onDismiss;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onJumpToPage;
  final VoidCallback onCycleFitMode;
  final VoidCallback onToggleCrop;
  final VoidCallback onToggleOrientation;
  final VoidCallback onOpenSettings;

  const ReaderMenuOverlay({
    super.key,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onCloseReader,
    required this.onDismiss,
    required this.onPrevious,
    required this.onNext,
    required this.onJumpToPage,
    required this.onCycleFitMode,
    required this.onToggleCrop,
    required this.onToggleOrientation,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('reader-menu-dismiss-area'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: _MenuBar(
            safeTop: true,
            border: const Border(
              bottom: BorderSide(color: Colors.black, width: 1.5),
            ),
            child: Row(
              children: [
                _MenuButton(
                  key: const Key('reader-close-button'),
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: onCloseReader,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _MenuButton(
                  icon: Icons.screen_rotation,
                  label: settings.landscape ? 'Portrait' : 'Landscape',
                  onPressed: onToggleOrientation,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _MenuBar(
            safeBottom: true,
            border: const Border(
              top: BorderSide(color: Colors.black, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MenuButton(
                  icon: Icons.chevron_left,
                  label: 'Previous',
                  onPressed: onPrevious,
                ),
                Expanded(
                  child: TextButton(
                    key: const Key('reader-page-jump-button'),
                    onPressed: pageCount == 0 ? null : onJumpToPage,
                    child: Text(
                      pageCount == 0
                          ? 'Page —'
                          : 'Page ${currentPage + 1} of $pageCount',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ),
                _MenuButton(
                  icon: Icons.chevron_right,
                  label: 'Next',
                  onPressed: onNext,
                ),
                _MenuButton(
                  key: const Key('reader-fit-mode-button'),
                  icon: _fitIcon(settings.fitMode),
                  label: _fitLabel(settings.fitMode),
                  onPressed: onCycleFitMode,
                ),
                _MenuButton(
                  key: const Key('reader-crop-button'),
                  icon: Icons.crop,
                  label: settings.autoCrop
                      ? settings.fitMode == PdfFitMode.continuousScroll
                            ? 'Uniform crop'
                            : 'Crop on'
                      : 'Crop off',
                  onPressed: onToggleCrop,
                ),
                _MenuButton(
                  icon: Icons.tune,
                  label: 'Settings',
                  onPressed: onOpenSettings,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static IconData _fitIcon(PdfFitMode mode) {
    return switch (mode) {
      PdfFitMode.fitHeight => Icons.fit_screen,
      PdfFitMode.fitWidth => Icons.swap_horiz,
      PdfFitMode.continuousScroll => Icons.view_stream,
      PdfFitMode.freeZoom => Icons.zoom_in,
    };
  }

  static String _fitLabel(PdfFitMode mode) {
    return switch (mode) {
      PdfFitMode.fitHeight => 'Height',
      PdfFitMode.fitWidth => 'Width',
      PdfFitMode.continuousScroll => 'Scroll',
      PdfFitMode.freeZoom => 'Zoom',
    };
  }
}

class _MenuBar extends StatelessWidget {
  final Widget child;
  final Border border;
  final bool safeTop;
  final bool safeBottom;

  const _MenuBar({
    required this.child,
    required this.border,
    this.safeTop = false,
    this.safeBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: safeTop,
        bottom: safeBottom,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(border: border),
          child: child,
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
