import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants.dart';
import '../../widgets/control_bar_row.dart';
import '../../widgets/inverting_ink_well.dart';
import '../models/doc_ref.dart';

/// The reader's paged, title-only tab controls. The owning menu determines
/// visibility; paging and selection never animate.
class ReaderTabStrip extends StatefulWidget {
  final List<DocRef> tabs;
  final String? selectedTabId;
  final ValueChanged<DocRef> onSelect;
  final ValueChanged<DocRef> onClose;

  const ReaderTabStrip({
    super.key,
    required this.tabs,
    required this.selectedTabId,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<ReaderTabStrip> createState() => _ReaderTabStripState();
}

class _ReaderTabStripState extends State<ReaderTabStrip> {
  static const _pageSize = 3;
  int _start = 0;

  int get _lastStart => widget.tabs.isEmpty
      ? 0
      : ((widget.tabs.length - 1) ~/ _pageSize) * _pageSize;

  @override
  void initState() {
    super.initState();
    _showSelection();
  }

  @override
  void didUpdateWidget(ReaderTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTabId != widget.selectedTabId ||
        !listEquals(
          oldWidget.tabs.map((doc) => doc.id).toList(),
          widget.tabs.map((doc) => doc.id).toList(),
        )) {
      _showSelection();
    } else {
      _start = _start.clamp(0, _lastStart);
    }
  }

  void _showSelection() {
    final selectedIndex = widget.tabs.indexWhere(
      (doc) => doc.id == widget.selectedTabId,
    );
    if (selectedIndex >= 0) {
      _start = (selectedIndex ~/ _pageSize) * _pageSize;
    } else {
      _start = _start.clamp(0, _lastStart);
    }
  }

  void _page(int direction) {
    setState(
      () => _start = (_start + direction * _pageSize).clamp(0, _lastStart),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          key: const Key('reader-tab-strip'),
          height: kReaderChromeRowHeight,
          color: Colors.white,
          foregroundDecoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black)),
          ),
          child: ControlBarRow(
            children: [
              SizedBox(
                width: readerHeaderActionWidth(constraints.maxWidth),
                child: _PageArrow(
                  key: const Key('reader-tabs-previous'),
                  icon: Icons.chevron_left,
                  label: 'Previous tabs',
                  onPressed: _start == 0 ? null : () => _page(-1),
                ),
              ),
              for (var slot = 0; slot < _pageSize; slot++)
                Expanded(
                  child: _start + slot < widget.tabs.length
                      ? _TabCell(
                          doc: widget.tabs[_start + slot],
                          selected:
                              widget.tabs[_start + slot].id ==
                              widget.selectedTabId,
                          onSelect: widget.onSelect,
                          onClose: widget.onClose,
                        )
                      : const SizedBox.expand(),
                ),
              SizedBox(
                width: readerHeaderActionWidth(constraints.maxWidth),
                child: _PageArrow(
                  key: const Key('reader-tabs-next'),
                  icon: Icons.chevron_right,
                  label: 'Next tabs',
                  onPressed: _start >= _lastStart ? null : () => _page(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PageArrow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PageArrow({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      disabledColor: Colors.grey,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      padding: EdgeInsets.zero,
      icon: FittedBox(fit: BoxFit.scaleDown, child: Icon(icon, size: 44)),
    );
  }
}

class _TabCell extends StatelessWidget {
  final DocRef doc;
  final bool selected;
  final ValueChanged<DocRef> onSelect;
  final ValueChanged<DocRef> onClose;

  const _TabCell({
    required this.doc,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : Colors.black;
    return Material(
      key: ValueKey('reader-tab-${doc.id}'),
      color: selected ? Colors.black : Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Open ${doc.title}',
              excludeSemantics: true,
              child: InvertingInkWell(
                onTap: () => onSelect(doc),
                invertOnPress: !selected,
                color: selected ? Colors.black : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      doc.title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: InvertingPressListener(
              color: selected ? Colors.black : Colors.white,
              child: IconButton(
                key: ValueKey('reader-tab-close-${doc.id}'),
                tooltip: 'Close ${doc.title}',
                onPressed: () => onClose(doc),
                style: ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(foreground),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                icon: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    border: Border.all(color: foreground),
                  ),
                  child: const Icon(Icons.close, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
