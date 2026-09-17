import 'package:flutter/material.dart';

/// Four instant, monochrome actions for a block-local text selection.
class SelectionToolbar extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback onDictionary;
  final VoidCallback onAddNote;
  final VoidCallback onUnderline;

  const SelectionToolbar({
    super.key,
    required this.onCopy,
    required this.onDictionary,
    required this.onAddNote,
    required this.onUnderline,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.black)),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          _button('Copy', 'copy', onCopy),
          _button('Dictionary', 'dictionary', onDictionary),
          _button('Add Note', 'note', onAddNote),
          _button('Underline', 'underline', onUnderline),
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
        padding: const EdgeInsets.symmetric(horizontal: 2),
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
    ),
  );
}
