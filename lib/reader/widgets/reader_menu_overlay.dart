import 'package:flutter/material.dart';

import '../models/reader_settings.dart';

class ReaderMenuOverlay extends StatelessWidget {
  final String title;
  final int currentPage;
  final int pageCount;
  final ReaderSettings settings;
  final VoidCallback onCloseReader;
  final VoidCallback onDismiss;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onJumpToPage;
  final ValueChanged<PdfFitMode> onSelectFitMode;
  final VoidCallback onToggleOrientation;
  final VoidCallback onOpenSettings;
  final bool showPdfControls;
  final VoidCallback? onOpenToc;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onJumpToPercent;
  final double? percent;

  const ReaderMenuOverlay({
    super.key,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.settings,
    required this.onCloseReader,
    required this.onDismiss,
    required this.onOpenBookmarks,
    required this.onJumpToPage,
    required this.onSelectFitMode,
    required this.onToggleOrientation,
    required this.onOpenSettings,
    this.showPdfControls = true,
    this.onOpenToc,
    this.onOpenSearch,
    this.onJumpToPercent,
    this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final pageButton = TextButton(
      key: const Key('reader-page-jump-button'),
      onPressed: pageCount == 0 ? null : onJumpToPage,
      child: Text(
        pageCount == 0 ? 'Page —' : 'Page ${currentPage + 1} of $pageCount',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final navigationButtons = <Widget>[
      if (!showPdfControls && onOpenSearch != null)
        _MenuButton(
          key: const Key('reader-search-button'),
          icon: Icons.search,
          label: 'Search',
          onPressed: onOpenSearch!,
        ),
      if (onOpenToc != null)
        _MenuButton(
          key: const Key('reader-toc-button'),
          icon: Icons.list_alt,
          label: 'Contents',
          onPressed: onOpenToc!,
        ),
      if (showPdfControls) Expanded(child: pageButton) else pageButton,
      if (onJumpToPercent != null)
        _MenuButton(
          key: const Key('reader-percent-jump-button'),
          icon: Icons.percent,
          label: percent == null ? 'Jump' : '${(percent! * 100).round()}%',
          onPressed: onJumpToPercent!,
        ),
      _MenuButton(
        icon: Icons.tune,
        label: 'Settings',
        onPressed: onOpenSettings,
      ),
    ];
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
                _MenuButton(
                  key: const Key('reader-bookmarks-button'),
                  icon: Icons.bookmark_outline,
                  label: 'Bookmarks',
                  onPressed: onOpenBookmarks,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPdfControls)
                  Row(children: navigationButtons)
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: navigationButtons,
                  ),
                if (showPdfControls) ...[
                  const Divider(height: 1, thickness: 1),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeButton(
                          key: const Key('reader-fit-height-button'),
                          icon: Icons.fit_screen,
                          label: 'Height',
                          selected: settings.fitMode == PdfFitMode.fitHeight,
                          onPressed: () =>
                              onSelectFitMode(PdfFitMode.fitHeight),
                        ),
                      ),
                      Expanded(
                        child: _ModeButton(
                          key: const Key('reader-fit-width-button'),
                          icon: Icons.swap_horiz,
                          label: 'Width',
                          selected: settings.fitMode == PdfFitMode.fitWidth,
                          onPressed: () => onSelectFitMode(PdfFitMode.fitWidth),
                        ),
                      ),
                      Expanded(
                        child: _ModeButton(
                          key: const Key('reader-zoom-scroll-button'),
                          icon: Icons.zoom_in,
                          label: 'Zoom / Scroll',
                          selected: settings.fitMode == PdfFitMode.zoom,
                          onPressed: () => onSelectFitMode(PdfFitMode.zoom),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _ModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.black,
        backgroundColor: selected ? Colors.black : Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
