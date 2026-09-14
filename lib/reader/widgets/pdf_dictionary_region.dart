import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/pdf_word_selection.dart';
import '../services/pdf_render_scheduler.dart';
import 'dictionary_dialog.dart';

class PdfDictionaryRegion extends StatefulWidget {
  final Object identity;
  final Future<PdfWordSelection?> Function(Offset) selectWord;
  final Widget child;
  final Future<void> Function(String)? defineWord;

  const PdfDictionaryRegion({
    super.key,
    required this.identity,
    required this.selectWord,
    required this.child,
    this.defineWord,
  });

  @override
  State<PdfDictionaryRegion> createState() => _PdfDictionaryRegionState();
}

class _PdfDictionaryRegionState extends State<PdfDictionaryRegion> {
  int _generation = 0;
  bool _busy = false;
  PdfWordSelection? _selection;

  @override
  void didUpdateWidget(PdfDictionaryRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _generation++;
      _busy = false;
      _selection = null;
    }
  }

  Future<void> _select(Offset point) async {
    if (_busy) return;
    _busy = true;
    final generation = _generation;
    try {
      final selection = await widget.selectWord(point);
      if (!mounted ||
          generation != _generation ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (selection == null) return;
      setState(() => _selection = selection);
      await (widget.defineWord?.call(selection.word) ??
          showDictionaryDefinition(context, selection.word));
    } on PdfRenderCancelledException {
      // Navigation or suspension superseded the selected page.
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not read this PDF’s text layer. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _selection = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _SingleFingerLongPress:
          GestureRecognizerFactoryWithHandlers<_SingleFingerLongPress>(
            _SingleFingerLongPress.new,
            (recognizer) =>
                recognizer.onLongPressStart = (details) =>
                    _select(details.localPosition),
          ),
    },
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_selection != null)
          IgnorePointer(
            child: CustomPaint(painter: _SelectionPainter(_selection!)),
          ),
      ],
    ),
  );
}

/// A second finger immediately yields to the existing pinch recognizer rather
/// than delaying its start until movement exceeds the long-press touch slop.
class _SingleFingerLongPress extends LongPressGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    final secondPointer =
        state != GestureRecognizerState.ready &&
        primaryPointer != null &&
        event.pointer != primaryPointer;
    super.addAllowedPointer(event);
    if (secondPointer) resolve(GestureDisposition.rejected);
  }
}

class _SelectionPainter extends CustomPainter {
  final PdfWordSelection selection;
  _SelectionPainter(this.selection);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = const Color(0x55000000);
    for (final box in selection.boxes) {
      canvas.drawRect(box, paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      selection != oldDelegate.selection;
}
