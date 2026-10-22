import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'code_block.dart' show codeBlockType;

/// The usual text-editor keys the package lacks or gets wrong for the Notes
/// editor: Home / End (and with Shift) go to the start / end of the LINE, not of
/// the whole block; Ctrl+Shift+Home / End select to the document edges and
/// Ctrl+Home / End move the caret there; Ctrl+L selects the line; the first
/// Ctrl+A inside a code block selects that block's code. (Ctrl+A, word moves on
/// Ctrl+Left / Right, Ctrl+Shift+Left / Right word selection, double click word
/// selection already come from the package.) Must be listed BEFORE
/// `standardCommandShortcutEvents`.

/// First and last offset of the physical line (between '\n') holding [offset].
({int start, int end}) physicalLineBounds(String text, int offset) {
  final at = offset.clamp(0, text.length);
  final before = at == 0 ? -1 : text.lastIndexOf('\n', at - 1);
  final after = text.indexOf('\n', at);
  return (start: before + 1, end: after < 0 ? text.length : after);
}

/// The line a position sits on: a code block's lines are its '\n'-separated
/// lines; any other block's line is the visual (wrapped) line it is drawn on.
({int start, int end}) lineBoundsAt(EditorState state, Node node, int offset) {
  final delta = node.delta;
  final length = delta?.length ?? 0;
  if (node.type == codeBlockType) {
    return physicalLineBounds(delta?.toPlainText() ?? '', offset);
  }
  final selectable = node.selectable;
  if (selectable != null) {
    try {
      final rect = selectable.getCursorRectInPosition(
        Position(path: node.path, offset: offset.clamp(0, length)),
      );
      if (rect != null) {
        final y = rect.center.dy;
        final left = selectable.getPositionInOffset(
          selectable.localToGlobal(Offset(-100000, y)),
        );
        final right = selectable.getPositionInOffset(
          selectable.localToGlobal(Offset(100000, y)),
        );
        final s = left.offset.clamp(0, length);
        final e = right.offset.clamp(0, length);
        if (s <= offset && offset <= e) return (start: s, end: e);
      }
    } catch (_) {
      // Not laid out (or not a text block): the whole block is the line.
    }
  }
  return (start: 0, end: length);
}

KeyEventResult _toLineEdge(
  EditorState state, {
  required bool end,
  required bool select,
}) {
  final sel = state.selection;
  if (sel == null) return KeyEventResult.ignored;
  final node = state.getNodeAtPath(sel.end.path);
  if (node == null || node.delta == null) return KeyEventResult.ignored;
  final b = lineBoundsAt(state, node, sel.end.offset);
  final target = Position(path: node.path, offset: end ? b.end : b.start);
  state.updateSelectionWithReason(
    select
        ? Selection(start: sel.start, end: target)
        : Selection.collapsed(target),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
}

/// First / last caret position of the document, or null when it has no text.
Position? _docEdge(EditorState state, {required bool end}) {
  final root = state.document.root;
  if (root.children.isEmpty) return null;
  if (!end) return Position(path: [0]);
  final last = state.getLastSelectable();
  return last?.$2.end(last.$1);
}

KeyEventResult _toDocEdge(
  EditorState state, {
  required bool end,
  required bool select,
}) {
  final sel = state.selection;
  final target = _docEdge(state, end: end);
  if (sel == null || target == null) return KeyEventResult.ignored;
  state.updateSelectionWithReason(
    select
        ? Selection(start: sel.start, end: target)
        : Selection.collapsed(target),
    reason: SelectionUpdateReason.uiEvent,
  );
  return KeyEventResult.handled;
}

CommandShortcutEvent _key(
  String key,
  String description,
  String command,
  CommandShortcutEventHandler handler,
) => CommandShortcutEvent(
  key: key,
  getDescription: () => description,
  command: command,
  macOSCommand: command.replaceAll('ctrl+', 'cmd+'),
  handler: handler,
);

final List<CommandShortcutEvent> notesHotkeyCommands = [
  _key(
    'notes: line start',
    'Move to the start of the line',
    'home',
    (s) => _toLineEdge(s, end: false, select: false),
  ),
  _key(
    'notes: line end',
    'Move to the end of the line',
    'end',
    (s) => _toLineEdge(s, end: true, select: false),
  ),
  _key(
    'notes: select to line start',
    'Select to the start of the line',
    'shift+home',
    (s) => _toLineEdge(s, end: false, select: true),
  ),
  _key(
    'notes: select to line end',
    'Select to the end of the line',
    'shift+end',
    (s) => _toLineEdge(s, end: true, select: true),
  ),
  _key(
    'notes: document start',
    'Move to the start of the notes',
    'ctrl+home',
    (s) => _toDocEdge(s, end: false, select: false),
  ),
  _key(
    'notes: document end',
    'Move to the end of the notes',
    'ctrl+end',
    (s) => _toDocEdge(s, end: true, select: false),
  ),
  _key(
    'notes: select to document start',
    'Select to the start of the notes',
    'ctrl+shift+home',
    (s) => _toDocEdge(s, end: false, select: true),
  ),
  _key(
    'notes: select to document end',
    'Select to the end of the notes',
    'ctrl+shift+end',
    (s) => _toDocEdge(s, end: true, select: true),
  ),
  _key('notes: select line', 'Select the line', 'ctrl+l', (s) {
    final sel = s.selection;
    if (sel == null) return KeyEventResult.ignored;
    final node = s.getNodeAtPath(sel.end.path);
    if (node == null || node.delta == null) return KeyEventResult.ignored;
    final b = lineBoundsAt(s, node, sel.end.offset);
    s.updateSelectionWithReason(
      Selection(
        start: Position(path: node.path, offset: b.start),
        end: Position(path: node.path, offset: b.end),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
    return KeyEventResult.handled;
  }),
  // The first Ctrl+A in a code block selects its code; a second one (the code
  // already selected) selects everything.
  _key('notes: select all in a code block', 'Select the code, then all', 'ctrl+a', (
    s,
  ) {
    final sel = s.selection?.normalized;
    if (sel == null || !sel.isSingle) return KeyEventResult.ignored;
    final node = s.getNodeAtPath(sel.start.path);
    if (node == null || node.type != codeBlockType) {
      return KeyEventResult.ignored;
    }
    final length = node.delta?.length ?? 0;
    if (sel.startIndex == 0 && sel.endIndex >= length) {
      return KeyEventResult.ignored;
    }
    s.updateSelectionWithReason(
      Selection(
        start: Position(path: node.path),
        end: Position(path: node.path, offset: length),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
    return KeyEventResult.handled;
  }),
];

/// The code block the caret / a one-block selection is in, or null.
Node? codeBlockAtSelection(EditorState state) {
  final sel = state.selection?.normalized;
  if (sel == null || !sel.isSingle) return null;
  final node = state.getNodeAtPath(sel.start.path);
  return node?.type == codeBlockType ? node : null;
}

/// Inserts [text] into the code block the selection is in, EXACTLY as it is
/// (every line stays in the block; the package's paste would start a paragraph
/// for each line after the first). False when the selection is not in one code
/// block.
Future<bool> pasteVerbatimIntoCodeBlock(EditorState state, String text) async {
  final node = codeBlockAtSelection(state);
  if (node == null) return false;
  final sel = state.selection!.normalized;
  final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final transaction = state.transaction;
  if (!sel.isCollapsed) {
    transaction.deleteText(node, sel.startIndex, sel.endIndex - sel.startIndex);
  }
  if (clean.isNotEmpty) transaction.insertText(node, sel.startIndex, clean);
  transaction.afterSelection = Selection.collapsed(
    Position(path: node.path, offset: sel.startIndex + clean.length),
  );
  await state.apply(transaction);
  return true;
}

/// A triple click inside a code block selects the LINE under the pointer, not
/// the whole block (the package selects the whole block). The package applies
/// its own selection right after the interceptor, so ours is set in a microtask.
SelectionGestureInterceptor notesTripleClickInterceptor(EditorState state) =>
    SelectionGestureInterceptor(
      key: 'notes-code-triple-click',
      canTripleTap: (details) {
        final service = state.selectionService;
        final node = service.getNodeInOffset(details.globalPosition);
        if (node == null || node.type != codeBlockType) return true;
        final selectable = node.selectable;
        if (selectable == null) return true;
        final at = selectable.getPositionInOffset(details.globalPosition);
        final b = lineBoundsAt(state, node, at.offset);
        scheduleMicrotask(() {
          state.updateSelectionWithReason(
            Selection(
              start: Position(path: node.path, offset: b.start),
              end: Position(path: node.path, offset: b.end),
            ),
            reason: SelectionUpdateReason.uiEvent,
          );
        });
        return true;
      },
    );
