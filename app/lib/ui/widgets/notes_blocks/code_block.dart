import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:provider/provider.dart';

import '../app_toast.dart';
import 'notes_copy_memory.dart';
import 'toggle_list_block.dart' show convertToParagraph;

/// Block type string of the code block.
const String codeBlockType = 'code';

/// Builds a code block node. Node shape (persisted, do not change):
/// `{type: 'code', attributes: {delta}}` where the delta is the plain code
/// text (may contain '\n').
Node codeBlockNode(String text) {
  return Node(
    type: codeBlockType,
    attributes: {blockComponentDelta: (Delta()..insert(text)).toJson()},
  );
}

class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.delta != null;
}

class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: codeBlockType,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  late final editorState = Provider.of<EditorState>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final bodySize =
        editorState.editorStyle.textStyleConfiguration.text.fontSize ?? 16;
    final codeStyle = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Cascadia Mono', 'Courier New', 'monospace'],
      fontSize: bodySize - 2,
      height: 1.5,
    );

    Widget box = Container(
      width: double.infinity,
      alignment: alignment,
      // Room on the right for the copy button.
      padding: const EdgeInsets.fromLTRB(14, 10, 40, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: AppFlowyRichText(
        key: forwardKey,
        delegate: this,
        node: widget.node,
        editorState: editorState,
        textAlign: alignment?.toTextAlign ?? textAlign,
        placeholderText: placeholderText,
        textDirection: textDirection,
        textSpanDecorator: (textSpan) => textSpan
            .updateTextStyle(textStyleWithTextSpan())
            .updateTextStyle(codeStyle),
        placeholderTextSpanDecorator: (textSpan) => textSpan.updateTextStyle(
          placeholderTextStyleWithTextSpan(textSpan: textSpan),
        ),
        cursorColor: editorState.editorStyle.cursorColor,
        selectionColor: editorState.editorStyle.selectionColor,
        cursorWidth: editorState.editorStyle.cursorWidth,
      ),
    );

    // A Copy button in the corner: the block's whole code text on the
    // clipboard (no fences), for a phone where selecting inside code is fiddly.
    Widget child = Stack(
      children: [
        box,
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            key: ValueKey('code-copy-${widget.node.id}'),
            tooltip: 'Copy the code',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: Icon(
              Icons.copy_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            onPressed: () async {
              final overlay = rootOverlayOf(context);
              final text = widget.node.delta?.toPlainText() ?? '';
              await Clipboard.setData(ClipboardData(text: text));
              // Ctrl+V pastes the same code block back; Ctrl+Shift+V the text.
              NotesCopyMemory.last = text.isEmpty
                  ? null
                  : (text: text, nodes: [widget.node.toJson()]);
              showInfoToast(overlay, 'Copied');
            },
          ),
        ),
      ],
    );

    child = Container(key: blockComponentKey, padding: padding, child: child);

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return Padding(padding: margin, child: child);
  }
}

// ---------------------------------------------------------------------------
// Shortcuts
// ---------------------------------------------------------------------------

/// The third backtick typed in an otherwise empty paragraph that already has
/// two backticks turns it into an empty code block. Must run before
/// `formatBackquoteToCode` (see `customNotesCharacterShortcuts`).
final CharacterShortcutEvent formatBackticksToCodeBlock =
    CharacterShortcutEvent(
      key: 'format triple backticks to code block',
      character: '`',
      handler: (editorState) => formatMarkdownSymbol(
        editorState,
        (node) =>
            node.type == ParagraphBlockKeys.type &&
            node.children.isEmpty &&
            node.delta?.toPlainText() == '``',
        (_, text, selection) => text == '``',
        (_, node, delta) => [codeBlockNode('')],
      ),
    );

/// Enter inside a code block inserts a '\n' in the same block; Enter on an
/// empty last line removes that line and starts a paragraph after the block.
final CharacterShortcutEvent insertNewLineInCodeBlock = CharacterShortcutEvent(
  key: 'insert new line in code block',
  character: '\n',
  handler: (editorState) async {
    var selection = editorState.selection?.normalized;
    if (selection == null) return false;
    final startNode = editorState.getNodeAtPath(selection.start.path);
    if (startNode == null || startNode.type != codeBlockType) return false;
    if (!selection.isCollapsed) {
      if (!selection.isSingle) return false;
      await editorState.deleteSelection(selection);
      selection = editorState.selection?.normalized;
      if (selection == null) return false;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (node == null || node.type != codeBlockType || delta == null) {
      return false;
    }
    final offset = selection.start.offset;
    final text = delta.toPlainText();

    if (offset == text.length && text.endsWith('\n')) {
      final next = node.path.next;
      final transaction = editorState.transaction
        ..deleteText(node, text.length - 1, 1)
        ..insertNode(next, paragraphNode())
        ..afterSelection = Selection.collapsed(Position(path: next));
      await editorState.apply(transaction);
      return true;
    }

    final transaction = editorState.transaction
      ..insertText(node, offset, '\n')
      ..afterSelection = Selection.collapsed(
        Position(path: node.path, offset: offset + 1),
      );
    await editorState.apply(transaction);
    return true;
  },
);

/// One edit of a line-wise indent: at [offset] remove [remove] characters and
/// insert [insert].
typedef LineEdit = ({int offset, int remove, String insert});

/// The result of [indentLines] / [outdentLines]: the edits (LAST line first, so
/// applying them one after the other keeps every offset valid) and the selection
/// after them.
typedef LineShift = ({List<LineEdit> edits, int start, int end});

const String _kIndent = '  ';

/// Start offset of every line of [text].
List<int> _lineStarts(String text) => [
  0,
  for (var i = 0; i < text.length; i++)
    if (text[i] == '\n') i + 1,
];

/// The first and last line the selection [start]..[end] touches: a selection that
/// ends at the very START of a later line does not include that line.
(int first, int last) _touchedLines(List<int> starts, int start, int end) {
  int lineOf(int offset) {
    var line = 0;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] <= offset) line = i;
    }
    return line;
  }

  final first = lineOf(start);
  var last = lineOf(end);
  if (last > first && end == starts[last]) last--;
  return (first, last);
}

/// Tab over several lines of a code block: two spaces at the start of EVERY
/// touched line.
LineShift indentLines(String text, int start, int end) {
  final starts = _lineStarts(text);
  final (first, last) = _touchedLines(starts, start, end);
  final edits = <LineEdit>[
    for (var i = last; i >= first; i--)
      (offset: starts[i], remove: 0, insert: _kIndent),
  ];
  final count = last - first + 1;
  return (
    edits: edits,
    // A start in the middle of a line moves with its text; one at the line start
    // stays there (the new spaces are inside the selection).
    start: start > starts[first] ? start + _kIndent.length : start,
    end: end + count * _kIndent.length,
  );
}

/// Shift+Tab over the touched lines (a caret: its line): removes up to two
/// leading spaces (or one tab) from each.
LineShift outdentLines(String text, int start, int end) {
  final starts = _lineStarts(text);
  final (first, last) = _touchedLines(starts, start, end);
  final removed = <int, int>{};
  for (var i = first; i <= last; i++) {
    final s = starts[i];
    var n = 0;
    while (n < _kIndent.length && s + n < text.length && text[s + n] == ' ') {
      n++;
    }
    if (n == 0 && s < text.length && text[s] == '\t') n = 1;
    removed[i] = n;
  }
  int shift(int offset, {required int from, required int to}) {
    var total = 0;
    for (var i = from; i <= to; i++) {
      final overlap = offset - starts[i];
      if (overlap > 0) total += removed[i]! < overlap ? removed[i]! : overlap;
    }
    return total;
  }

  return (
    edits: [
      for (var i = last; i >= first; i--)
        if (removed[i]! > 0) (offset: starts[i], remove: removed[i]!, insert: ''),
    ],
    start: start - shift(start, from: first, to: first),
    end: end - shift(end, from: first, to: last),
  );
}

/// Applies [shift] to the code block [node] and moves the selection with it.
void _applyLineShift(EditorState editorState, Node node, LineShift shift) {
  final transaction = editorState.transaction;
  for (final e in shift.edits) {
    if (e.remove > 0) transaction.deleteText(node, e.offset, e.remove);
    if (e.insert.isNotEmpty) transaction.insertText(node, e.offset, e.insert);
  }
  transaction.afterSelection = Selection(
    start: Position(path: node.path, offset: shift.start),
    end: Position(path: node.path, offset: shift.end),
  );
  editorState.apply(transaction);
}

/// Shift+Tab in a code block outdents every selected line (never outdents the
/// block itself).
final CommandShortcutEvent codeBlockOutdentCommand = CommandShortcutEvent(
  key: 'code block shift+tab removes indentation',
  getDescription: () => 'Remove two spaces from the selected lines of a code block',
  command: 'shift+tab',
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null || !selection.isSingle) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null || node.type != codeBlockType) {
      return KeyEventResult.ignored;
    }
    final text = node.delta?.toPlainText() ?? '';
    _applyLineShift(
      editorState,
      node,
      outdentLines(text, selection.startIndex, selection.endIndex),
    );
    return KeyEventResult.handled;
  },
);

/// Tab inside a code block inserts two spaces (never indents the block); with a
/// selection over SEVERAL lines it indents every selected line instead.
final CommandShortcutEvent codeBlockTabCommand = CommandShortcutEvent(
  key: 'code block tab inserts spaces',
  getDescription: () => 'Insert two spaces in a code block',
  command: 'tab',
  handler: (editorState) {
    final selection = editorState.selection?.normalized;
    if (selection == null || !selection.isSingle) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null || node.type != codeBlockType) {
      return KeyEventResult.ignored;
    }
    final text = node.delta?.toPlainText() ?? '';
    if (!selection.isCollapsed &&
        text.substring(selection.startIndex, selection.endIndex).contains('\n')) {
      _applyLineShift(
        editorState,
        node,
        indentLines(text, selection.startIndex, selection.endIndex),
      );
      return KeyEventResult.handled;
    }
    final transaction = editorState.transaction;
    if (!selection.isCollapsed) {
      transaction.deleteText(
        node,
        selection.startIndex,
        selection.endIndex - selection.startIndex,
      );
    }
    transaction
      ..insertText(node, selection.startIndex, '  ')
      ..afterSelection = Selection.collapsed(
        Position(path: node.path, offset: selection.startIndex + 2),
      );
    editorState.apply(transaction);
    return KeyEventResult.handled;
  },
);

/// Backspace in an empty code block turns it into a paragraph.
final CommandShortcutEvent codeBlockBackspaceCommand = CommandShortcutEvent(
  key: 'empty code block backspace to paragraph',
  getDescription: () => 'Convert empty code block to paragraph',
  command: 'backspace',
  handler: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final node = editorState.getNodeAtPath(selection.end.path);
    final delta = node?.delta;
    if (node == null ||
        node.type != codeBlockType ||
        delta == null ||
        delta.isNotEmpty) {
      return KeyEventResult.ignored;
    }
    convertToParagraph(editorState, node);
    return KeyEventResult.handled;
  },
);
