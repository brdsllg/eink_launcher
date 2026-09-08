import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/battery_status.dart';
import '../../widgets/clock_text.dart';
import '../../widgets/control_bar_row.dart';
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
  final Widget? tabStrip;
  final bool controlsEnabled;

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
    this.tabStrip,
    this.controlsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final pageButton = TextButton(
      key: const Key('reader-page-jump-button'),
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(),
        minimumSize: const Size(0, kReaderChromeRowHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: !controlsEnabled || pageCount == 0 ? null : onJumpToPage,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          pageCount == 0 ? 'Page —' : 'Page ${currentPage + 1} of $pageCount',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final showSearch = !showPdfControls && onOpenSearch != null;
    final navigationBar = ControlBarRow(
      spans: const [1, 2, 3, 1, 1, 1],
      children: [
        const _StatusCell(
          key: Key('reader-battery-cell'),
          child: BatteryStatus(
            style: TextStyle(fontSize: 12),
            iconSize: kReaderChromeIconSize,
          ),
        ),
        const _StatusCell(
          key: Key('reader-clock-cell'),
          child: ClockText(style: TextStyle(fontSize: 12, color: Colors.black)),
        ),
        pageButton,
        _MenuButton(
          key: const Key('reader-percent-jump-button'),
          icon: Icons.percent,
          label: percent == null ? 'Jump' : '${(percent! * 100).round()}%',
          onPressed: controlsEnabled ? onJumpToPercent : null,
        ),
        _MenuButton(
          key: const Key('reader-toc-button'),
          icon: Icons.list_alt,
          label: 'Contents',
          showLabel: false,
          onPressed: controlsEnabled ? onOpenToc : null,
        ),
        _MenuButton(
          key: const Key('reader-settings-button'),
          icon: Icons.tune,
          label: 'Settings',
          showLabel: false,
          onPressed: controlsEnabled ? onOpenSettings : null,
        ),
      ],
    );
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
            border: const Border(bottom: BorderSide(color: Colors.black)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?tabStrip,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final iconWidth = readerHeaderActionWidth(
                      constraints.maxWidth,
                    );
                    return ControlBarRow(
                      children: [
                        _MenuButton(
                          width: iconWidth,
                          key: const Key('reader-close-button'),
                          icon: Icons.home,
                          label: 'Home',
                          showLabel: false,
                          onPressed: onCloseReader,
                        ),
                        _MenuButton(
                          width: iconWidth,
                          key: const Key('reader-bookmarks-button'),
                          icon: Icons.bookmark_outline,
                          label: 'Bookmarks',
                          showLabel: false,
                          onPressed: controlsEnabled ? onOpenBookmarks : null,
                        ),
                        Expanded(
                          child: Center(
                            key: const Key('reader-title-cell'),
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
                        ),
                        if (showSearch)
                          _MenuButton(
                            width: iconWidth,
                            key: const Key('reader-search-button'),
                            icon: Icons.search,
                            label: 'Search',
                            showLabel: false,
                            onPressed: controlsEnabled ? onOpenSearch : null,
                          ),
                        _MenuButton(
                          // Rotation includes a word as well as an icon.
                          width: iconWidth + 40,
                          key: const Key('reader-orientation-button'),
                          icon: Icons.screen_rotation,
                          label: settings.landscape ? 'Portrait' : 'Landscape',
                          onPressed: controlsEnabled
                              ? onToggleOrientation
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _MenuBar(
            safeBottom: true,
            border: const Border(top: BorderSide(color: Colors.black)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                navigationBar,
                if (showPdfControls) ...[
                  const Divider(height: 0, thickness: 1),
                  ControlBarRow(
                    spans: const [1, 1, 1],
                    children: [
                      _ModeButton(
                        key: const Key('reader-fit-height-button'),
                        icon: Icons.fit_screen,
                        label: 'Height',
                        selected: settings.fitMode == PdfFitMode.fitHeight,
                        onPressed: controlsEnabled
                            ? () => onSelectFitMode(PdfFitMode.fitHeight)
                            : null,
                      ),
                      _ModeButton(
                        key: const Key('reader-fit-width-button'),
                        icon: Icons.swap_horiz,
                        label: 'Width',
                        selected: settings.fitMode == PdfFitMode.fitWidth,
                        onPressed: controlsEnabled
                            ? () => onSelectFitMode(PdfFitMode.fitWidth)
                            : null,
                      ),
                      _ModeButton(
                        key: const Key('reader-zoom-scroll-button'),
                        icon: Icons.zoom_in,
                        label: 'Zoom / Scroll',
                        selected: settings.fitMode == PdfFitMode.zoom,
                        onPressed: controlsEnabled
                            ? () => onSelectFitMode(PdfFitMode.zoom)
                            : null,
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

class _StatusCell extends StatelessWidget {
  final Widget child;
  const _StatusCell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
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
        child: DecoratedBox(
          position: DecorationPosition.foreground,
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
  final VoidCallback? onPressed;
  final bool showLabel;
  final double? width;

  const _MenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showLabel = true,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: kReaderChromeRowHeight,
      child: !showLabel
          ? IconButton(
              tooltip: label,
              onPressed: onPressed,
              icon: Icon(icon, size: kReaderChromeIconSize),
            )
          : TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: kReaderChromeIconSize),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

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
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: kReaderChromeIconSize),
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
