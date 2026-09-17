import 'package:flutter/material.dart';

import '../../widgets/adaptive_grid.dart';
import '../models/annotation.dart';

Future<String?> showAnnotationEditor(BuildContext context, {String? note}) =>
    showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => _AnnotationEditor(note: note),
    );

enum AnnotationAction { edit, delete }

Future<AnnotationAction?> showAnnotationViewer(
  BuildContext context,
  Annotation annotation,
) => showDialog<AnnotationAction>(
  context: context,
  animationStyle: AnimationStyle.noAnimation,
  builder: (context) => GridDialog(
    title: const Text('Annotation'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(annotation.text),
        const SizedBox(height: 16),
        Text(annotation.note ?? 'No note — underline only'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, AnnotationAction.edit),
        child: const Text('Edit'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, AnnotationAction.delete),
        child: const Text('Delete'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _AnnotationEditor extends StatefulWidget {
  final String? note;
  const _AnnotationEditor({this.note});

  @override
  State<_AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<_AnnotationEditor> {
  late final _controller = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GridDialog(
    title: Text(widget.note == null ? 'Add Note' : 'Edit Note'),
    content: TextField(
      key: const Key('annotation-note-input'),
      controller: _controller,
      autofocus: true,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'Note',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
