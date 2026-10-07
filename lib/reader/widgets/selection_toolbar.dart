import 'package:flutter/material.dart';

/// Instant, monochrome actions for a text selection. **More** extends the
/// selection through the next readable paragraph (repeatable); Copy,
/// Dictionary, Add Note and Underline then apply to the whole range.
class SelectionToolbar extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback onDictionary;
  final VoidCallback onAddNote;
  final VoidCallback onUnderline;
  final VoidCallback? onExtend;

  const SelectionToolbar({
    super.key,
    required this.onCopy,
    required this.onDictionary,
    required this.onAddNote,
    required this.onUnderline,
    this.onExtend,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black)),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          _button('Copy', 'copy', onCopy),
          _button('Dictionary', 'dictionary', onDictionary),
          _button('Add Note', 'note', onAddNote),
          _button('Underline', 'underline', onUnderline),
          if (onExtend != null) _button('More', 'extend', onExtend!),
        ],
      ),
    ),
  );

  Widget _button(String label, String key, VoidCallback callback) => Expanded(
    child: TextButton(
      key: Key('selection-$key'),
      onPressed: callback,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(),
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
        animationDuration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 56),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, style: const TextStyle(fontSize: 15)),
      ),
    ),
  );
}
