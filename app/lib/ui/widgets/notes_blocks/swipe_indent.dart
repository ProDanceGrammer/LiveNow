import 'package:appflowy_editor/appflowy_editor.dart';
// Not part of the package's public API: the drag-mode flag lets the swipe stand
// down while a selection handle or the long-press caret is being dragged.
// ignore: implementation_imports
import 'package:appflowy_editor/src/editor/editor_component/service/selection/mobile_selection_service.dart'
    show MobileSelectionDragMode, selectionDragModeKey;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'code_block.dart'
    show codeBlockOutdentCommand, codeBlockTabCommand, codeBlockType;

/// Horizontal travel (logical px) a swipe needs before it counts.
const double kSwipeIndentDistance = 48;

enum SwipeIndent { none, indent, outdent }

/// What a finished touch of [dx] / [dy] means: a mostly horizontal move (at
/// least [kSwipeIndentDistance] and twice as far as it went vertically) to the
/// right is Tab (indent), to the left Shift+Tab (outdent); anything else nothing.
SwipeIndent swipeIndentDirection(double dx, [double dy = 0]) {
  if (dx.abs() < kSwipeIndentDistance || dx.abs() <= 2 * dy.abs()) {
    return SwipeIndent.none;
  }
  return dx > 0 ? SwipeIndent.indent : SwipeIndent.outdent;
}

/// Indents / outdents the block at [globalStart] like Tab / Shift+Tab would: the
/// code block's own line shift inside a code block, the package's block indent
/// everywhere else (a block that cannot move, such as a heading, stays put). The
/// selection is collapsed into the touched block first, unless that block is
/// already part of the current selection (then the whole selection moves).
/// Returns whether anything was dispatched.
bool applySwipeIndent(
  EditorState editorState,
  Offset globalStart,
  SwipeIndent direction,
) {
  if (direction == SwipeIndent.none) return false;
  if (_dragInProgress(editorState)) return false;

  final node = editorState.selectionService.getNodeInOffset(globalStart);
  if (node == null) return false;

  final current = editorState.selection?.normalized;
  final inSelection =
      current != null &&
      !current.isCollapsed &&
      editorState.getNodesInSelection(current).contains(node);
  if (!inSelection) {
    editorState.selection = Selection.collapsed(
      Position(path: node.path, offset: 0),
    );
  }

  final inCode = node.type == codeBlockType;
  final command = switch ((direction, inCode)) {
    (SwipeIndent.indent, true) => codeBlockTabCommand,
    (SwipeIndent.outdent, true) => codeBlockOutdentCommand,
    (SwipeIndent.indent, false) => indentCommand,
    _ => outdentCommand,
  };
  command.handler(editorState);
  return true;
}

/// True while a selection handle or the long-press caret is being dragged.
bool _dragInProgress(EditorState editorState) {
  final mode = editorState.selectionExtraInfo?[selectionDragModeKey];
  return mode != null && mode != MobileSelectionDragMode.none;
}

/// Wraps the editor: a touch swipe to the right on a line is Tab, to the left
/// Shift+Tab. It only WATCHES the touch (a raw pointer [Listener], no gesture
/// arena), so it never takes a gesture from the editor: taps, scrolling, the
/// handles and the dialog's scroll hand-off behave as before. Only touch takes
/// part (a mouse drag still selects text), a second finger cancels it, and a
/// handle / caret drag in progress never counts.
class SwipeIndentDetector extends StatefulWidget {
  const SwipeIndentDetector({
    super.key,
    required this.editorState,
    required this.child,
  });

  final EditorState editorState;
  final Widget child;

  @override
  State<SwipeIndentDetector> createState() => _SwipeIndentDetectorState();
}

class _SwipeIndentDetectorState extends State<SwipeIndentDetector> {
  int? _pointer;
  Offset _start = Offset.zero;
  bool _spoiled = false;

  void _reset() {
    _pointer = null;
    _spoiled = false;
  }

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    if (_pointer != null) {
      // A second finger (pinch): not a swipe.
      _spoiled = true;
      return;
    }
    _pointer = e.pointer;
    _start = e.position;
    _spoiled = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_dragInProgress(widget.editorState)) _spoiled = true;
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final delta = e.position - _start;
    final spoiled = _spoiled || _dragInProgress(widget.editorState);
    final start = _start;
    _reset();
    if (spoiled) return;
    applySwipeIndent(
      widget.editorState,
      start,
      swipeIndentDirection(delta.dx, delta.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _reset();
      },
      child: widget.child,
    );
  }
}
