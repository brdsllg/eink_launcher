import 'package:flutter/material.dart';

// Dialog builders used by the file browser for New Folder / Rename / Delete
// confirm. These are standard AlertDialogs (fine per the "no transitions rule",
// which targets screen/route transitions, not modal dialogs) styled to match
// the rest of the theme via the app's shared ThemeData.

/// Validates a folder/file name for creation or rename.
///
/// Returns a human-readable error string, or null if the name is usable.
/// [existingNames] may be a case-insensitive list of siblings to check against.
/// [currentName] (rename only) lets the unchanged name pass without error.
String? validateEntryName(
  String rawName,
  Iterable<String> existingNames, {
  String? currentName,
}) {
  final name = rawName.trim();
  if (name.isEmpty) return 'Name can\'t be empty';
  if (name == '.' || name == '..') return 'That name isn\'t allowed';
  if (name.contains('/') || name.contains(r'\')) {
    return 'Name can\'t contain / or \\';
  }

  // Case-insensitive clash with an existing sibling — equal to the current
  // name is fine (no-op rename).
  for (final existing in existingNames) {
    if (existing.toLowerCase() == name.toLowerCase() &&
        existing.toLowerCase() != (currentName ?? '').toLowerCase()) {
      return 'An item with that name already exists';
    }
  }
  return null;
}

/// New Folder dialog. Resolves with the new folder name, or null if cancelled.
Future<String?> showNewFolderDialog(
  BuildContext context,
  List<String> existingNames,
) {
  return _showNameDialog(
    context: context,
    title: 'New Folder',
    confirmLabel: 'Create',
    existingNames: existingNames,
  );
}

/// Rename dialog (exactly one item selected). Field is pre-filled with the
/// current name; the unchanged name is allowed. Resolves with the new name or
/// null if cancelled.
Future<String?> showRenameDialog(
  BuildContext context,
  String currentName,
  List<String> existingNames,
) {
  return _showNameDialog(
    context: context,
    title: 'Rename',
    confirmLabel: 'Rename',
    initialValue: currentName,
    existingNames: existingNames,
    currentName: currentName,
  );
}

/// Delete-confirm dialog. Resolves with true if the user confirms deletion.
Future<bool> showDeleteConfirmDialog(BuildContext context, int count) {
  final noun = count == 1 ? 'item' : 'items';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete'),
      content: Text('Delete $count $noun?\n\nThis can\'t be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  ).then((v) => v ?? false);
}

Future<String?> _showNameDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<String> existingNames,
  String initialValue = '',
  String? currentName,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NameDialog(
      title: title,
      confirmLabel: confirmLabel,
      existingNames: existingNames,
      initialValue: initialValue,
      currentName: currentName,
    ),
  );
}

// A StatefulWidget owns the TextEditingController so it can be disposed in
// State.dispose(), which runs only after the dialog route has fully unmounted
// its element (post exit-animation). Disposing the controller via
// showDialog(...).whenComplete(...) trips Flutter's
// InheritedElement.debugDeactivated() assert because the TextField is still
// deactivating at the moment the route future resolves.
class _NameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final List<String> existingNames;
  final String initialValue;
  final String? currentName;

  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.existingNames,
    required this.initialValue,
    this.currentName,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate() =>
      validateEntryName(_controller.text, widget.existingNames,
          currentName: widget.currentName);

  void _submit() {
    final error = _validate();
    setState(() => _errorText = error);
    if (error == null) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Folder name',
          errorText: _errorText,
          border: const UnderlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

