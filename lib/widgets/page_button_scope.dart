import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Makes the visible page respond to an e-reader's physical page buttons.
///
/// Accepts standard page, directional, and volume mappings for side buttons.
/// A press is handled even at a page boundary, so a volume-mapped button
/// does not unexpectedly change the system volume there.
class PageButtonScope extends StatefulWidget {
  const PageButtonScope({
    super.key,
    required this.child,
    this.onPrevious,
    this.onNext,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool enabled;

  @override
  State<PageButtonScope> createState() => _PageButtonScopeState();
}

class _PageButtonScopeState extends State<PageButtonScope>
    with WidgetsBindingObserver {
  final Set<PhysicalKeyboardKey> _capturedKeys = {};
  ModalRoute<dynamic>? _route;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _resumed =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) _capturedKeys.clear();
  }

  bool get _editingText {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    return focusedContext != null &&
        (focusedContext.widget is EditableText ||
            focusedContext.findAncestorWidgetOfExactType<EditableText>() !=
                null);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_resumed) return false;

    // Finish the press we accepted, even if it opened a dialog or temporarily
    // disabled paging. Repeats must not turn more pages, and the key-up must not
    // escape to the platform as an unmatched volume-button release.
    if (event is KeyUpEvent) {
      return _capturedKeys.remove(event.physicalKey);
    }
    if (_capturedKeys.contains(event.physicalKey)) return true;

    final keyboard = HardwareKeyboard.instance;
    if (!widget.enabled ||
        (_route != null && !_route!.isCurrent) ||
        _editingText ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        event is! KeyDownEvent ||
        event.synthesized) {
      return false;
    }

    final previous = switch (event.logicalKey) {
      LogicalKeyboardKey.pageUp ||
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.audioVolumeUp => true,
      LogicalKeyboardKey.pageDown ||
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.audioVolumeDown => false,
      _ => null,
    };
    if (previous == null) return false;

    _capturedKeys.add(event.physicalKey);
    (previous ? widget.onPrevious : widget.onNext)?.call();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _capturedKeys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
