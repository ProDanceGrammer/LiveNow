import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/material.dart' hide Overlay, OverlayEntry;
import 'package:flutter/services.dart';

// Not part of the package's public API.
// ignore: implementation_imports
import 'package:appflowy_editor/src/editor/editor_component/service/selection/mobile_selection_service.dart'
    show disableIOSSelectWordEdgeOnTap;

import '../layout.dart';
import 'notes_blocks/notes_blocks.dart';
import 'notes_blocks/swipe_indent.dart';
import 'notes_document.dart';

// ---------------------------------------------------------------------------
// Extension points for extra block types (toggle list, code block, ...).
// The integrator fills these two functions with the blocks from
// `notes_blocks/`; nothing else in this file needs to change.
// ---------------------------------------------------------------------------

/// Extra block component builders, keyed by node type (e.g. `toggle_list`,
/// `code`). Merged after the built-in blocks, so they can also override one.
///
/// Wired to the toggle-list and code blocks. Note: this also registers
/// `toggle_list` as indentable (a side effect of `customNotesBlockBuilders`),
/// which the standard Tab / Shift+Tab commands need, so it must run before the
/// user first presses Tab — it does, as the blocks map is built in `build`.
Map<String, BlockComponentBuilder> notesExtraBlockBuilders() =>
    customNotesBlockBuilders();

/// Extra character shortcuts (e.g. "> " -> toggle, "```" -> code block).
/// They are placed at the very START of the shortcut list, so they run before
/// the built-in ones, including the newline handler (an extra '\n' handler
/// therefore has to return false for blocks it does not own) and the inline
/// markdown events.
///
/// Wired to `> ` -> toggle list and ``` -> code block (plus their Enter
/// handlers).
List<CharacterShortcutEvent> notesExtraCharacterShortcuts() =>
    customNotesCharacterShortcuts();

/// `+ ` -> bulleted list (the package only knows `- ` and `* `).
final CharacterShortcutEvent formatPlusToBulletedList = CharacterShortcutEvent(
  key: 'format plus to bulleted list',
  character: ' ',
  handler: (editorState) => formatMarkdownSymbol(
    editorState,
    (node) => node.type != BulletedListBlockKeys.type,
    (_, text, _) => text == '+',
    (_, node, delta) => [
      node.copyWith(
        type: BulletedListBlockKeys.type,
        attributes: {
          BulletedListBlockKeys.delta: delta
              .compose(Delta()..delete(1))
              .toJson(),
        },
      ),
    ],
  ),
);

/// Only the shortcuts the user chose: todo, bullets (- * +), numbered,
/// heading, list/heading newline continuation and inline markdown. No quote,
/// divider, slash menu or arrow conversion.
List<CharacterShortcutEvent> notesCharacterShortcuts() => [
  ...notesExtraCharacterShortcuts(),
  insertNewLineAfterBulletedList,
  insertNewLineAfterTodoList,
  insertNewLineAfterNumberedList,
  insertNewLineAfterHeading,
  insertNewLine,
  formatAsteriskToBulletedList,
  formatMinusToBulletedList,
  formatPlusToBulletedList,
  formatNumberToNumberedList,
  formatSignToHeading,
  formatEmptyBracketsToUncheckedBox,
  formatHyphenEmptyBracketsToUncheckedBox,
  formatFilledBracketsToCheckedBox,
  formatHyphenFilledBracketsToCheckedBox,
  formatBackquoteToCode,
  formatUnderscoreToItalic,
  formatAsteriskToItalic,
  formatDoubleTilesToStrikethrough,
  formatDoubleAsterisksToBold,
  formatDoubleUnderscoresToBold,
];

/// The Notion-style notes editor of an action.
///
/// - [initialJson]: the stored Document JSON (`actions.notes`), or null/empty
///   for a blank document. Corrupt JSON must never throw: fall back to blank.
/// - [onChanged]: called (debounced) with the new Document JSON string after
///   every edit, or `null` when the document became empty.
/// - [height]: fixed height of the editor area (it scrolls inside).
/// - [expanded] / [onToggleExpand]: the toolbar's Expand/Collapse button; the
///   parent dialog resizes itself, the editor widget stays in the same place in
///   the tree (never two editors on one EditorState).
class NotesEditor extends StatefulWidget {
  final String? initialJson;
  final ValueChanged<String?> onChanged;
  final double height;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  /// Ctrl+Enter inside the editor (the host dialog's Save). Without it the
  /// package would use the key to toggle a checkbox.
  final VoidCallback? onSave;

  /// Extra controls under the toolbar row (the action editor's "What is done?").
  /// It receives the Expand/Collapse button (null without [onToggleExpand]) and
  /// places it itself; the toolbar row then leaves the button out.
  final Widget Function(Widget? expandToggle)? toolbarExtra;

  /// The scroll view the editor sits in (the dialog's). On a phone a drag that
  /// reaches the editor's own top or bottom edge is handed to it, so a long note
  /// never traps the finger: the page keeps scrolling.
  final ScrollController? outerScroll;

  const NotesEditor({
    super.key,
    this.initialJson,
    required this.onChanged,
    this.height = 320,
    this.expanded = false,
    this.onToggleExpand,
    this.onSave,
    this.toolbarExtra,
    this.outerScroll,
  });

  @override
  State<NotesEditor> createState() => NotesEditorState();
}

class NotesEditorState extends State<NotesEditor> with WidgetsBindingObserver {
  static const _debounce = Duration(milliseconds: 400);

  late final EditorState _editorState;
  late final EditorScrollController _scrollController;
  late final List<CommandShortcutEvent> _commands;
  late final List<CharacterShortcutEvent> _characters;
  // Rebuilt only when the theme changes: handing the editor fresh builder
  // objects on every parent rebuild would needlessly re-create its blocks.
  Map<String, BlockComponentBuilder>? _blocks;
  ColorScheme? _blocksScheme;

  /// The current theme's colours. The package's editor keeps the block builders
  /// it saw when it was first built (`editorState.renderer` is only replaced when
  /// its service changes), so a builder must NOT capture a colour: the struck-out
  /// grey of a checked line, the checkbox and the placeholder read this field
  /// when they draw, and therefore follow a light / dark switch (which also
  /// animates through in-between colours).
  late ColorScheme _liveScheme;
  StreamSubscription<EditorTransactionValue>? _sub;
  Timer? _timer;
  String? _lastEmitted;

  /// The last selection the user had in the editor. Leaving the app window makes
  /// Flutter suspend the focus and appflowy_editor answers by setting its
  /// selection to null (the caret vanishes); this is what gets put back when the
  /// window returns. Cleared only by a null selection while the app is active
  /// (the user clicked away or pressed Esc).
  Selection? _lastSelection;

  /// Number of editors created so far (tests assert it stays put while a
  /// collapsed section must not build the editor).
  @visibleForTesting
  static int createdCount = 0;

  @visibleForTesting
  EditorState get editorState => _editorState;

  @override
  void initState() {
    super.initState();
    createdCount++;
    // iOS places the caret exactly where the finger lands (the package snaps it
    // to the nearest word edge unless told otherwise).
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      disableIOSSelectWordEdgeOnTap = true;
    }
    _editorState = EditorState(
      document: notesDocumentFromJson(widget.initialJson),
    );
    _lastEmitted = notesDocumentToJson(_editorState.document);
    _scrollController = EditorScrollController(editorState: _editorState);
    _characters = notesCharacterShortcuts();
    _commands = [
      CommandShortcutEvent(
        key: 'paste as markdown',
        getDescription: () => 'Paste as Markdown',
        command: 'ctrl+shift+v',
        macOSCommand: 'cmd+shift+v',
        handler: (_) {
          pasteAsMarkdown();
          return KeyEventResult.handled;
        },
      ),
      // Ctrl+Enter: ticks a checkbox row, opens/closes a toggle row; on any
      // other line it is the host dialog's Save.
      CommandShortcutEvent(
        key: 'checkbox, toggle or save',
        getDescription: () => 'Tick / open, otherwise Save',
        command: 'ctrl+enter',
        macOSCommand: 'cmd+enter',
        handler: (_) {
          if (_toggleCurrentRow()) return KeyEventResult.handled;
          if (widget.onSave == null) return KeyEventResult.ignored;
          // Hand the latest text over before the host saves.
          _flush();
          widget.onSave?.call();
          return KeyEventResult.handled;
        },
      ),
      // Ctrl+V: when the clipboard still holds what THIS editor copied, paste
      // the exact blocks back (toggles, bullets, numbers, checkboxes with their
      // state, code, collapsed state); anything else takes the package's paste.
      CommandShortcutEvent(
        key: 'paste keeping the structure',
        getDescription: () => 'Paste (same format for text copied here)',
        command: 'ctrl+v',
        macOSCommand: 'cmd+v',
        handler: (state) {
          // Inside a code block every pasted line stays in the block.
          if (codeBlockAtSelection(state) != null) {
            _pasteIntoCode();
            return KeyEventResult.handled;
          }
          if (NotesCopyMemory.last == null) return KeyEventResult.ignored;
          _pasteInApp(state);
          return KeyEventResult.handled;
        },
      ),
      // Ctrl+X: the same copy (Markdown text + exact blocks), then the cut.
      CommandShortcutEvent(
        key: 'cut keeping the structure',
        getDescription: () => 'Cut (same format when pasted here)',
        command: 'ctrl+x',
        macOSCommand: 'cmd+x',
        handler: (_) {
          final sel = _editorState.selection;
          if (sel == null || sel.isCollapsed) return KeyEventResult.ignored;
          _cutSelection();
          return KeyEventResult.handled;
        },
      ),
      // Ctrl+C puts Markdown on the clipboard (text channel).
      CommandShortcutEvent(
        key: 'copy as markdown',
        getDescription: () => 'Copy as Markdown',
        command: 'ctrl+c',
        macOSCommand: 'cmd+c',
        handler: (_) {
          final sel = _editorState.selection;
          if (sel == null || sel.isCollapsed) return KeyEventResult.ignored;
          copyAsMarkdown();
          return KeyEventResult.handled;
        },
      ),
      // The custom blocks' Tab / Backspace commands must run BEFORE the
      // standard ones, or the standard Tab / Backspace handle the key first.
      ...customNotesCommandShortcuts(),
      ...notesHotkeyCommands,
      ...standardCommandShortcutEvents.where(
        (e) => e.key != pasteTextWithoutFormattingCommand.key,
      ),
    ];
    _sub = _editorState.transactionStream.listen((event) {
      if (event.$2.operations.isEmpty) return;
      _timer?.cancel();
      _timer = Timer(_debounce, _flush);
    });
    _editorState.selectionNotifier.addListener(_rememberSelection);
    WidgetsBinding.instance.addObserver(this);
    // The selection service exists once the editor is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _editorState.selectionService.registerGestureInterceptor(
          _tripleClick,
        );
      } catch (_) {}
    });
  }

  late final SelectionGestureInterceptor _tripleClick =
      notesTripleClickInterceptor(_editorState);

  void _rememberSelection() {
    final sel = _editorState.selection;
    if (sel != null) {
      _lastSelection = sel;
    } else if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      // A deliberate clear. (While the window is away the null is only the
      // editor reacting to the suspended focus: keep what we remembered.)
      _lastSelection = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // The OS may kill a backgrounded app without another frame: do not
      // leave the last 400 ms of typing in the debounce.
      flushPending();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final sel = _lastSelection;
    if (sel == null || _editorState.selection != null) return;
    // After the frame: Flutter hands the suspended focus back during this
    // callback chain, and the selection update then re-attaches the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editorState.selection != null) return;
      final fitted = _fitSelection(sel);
      if (fitted == null) return;
      _editorState.updateSelectionWithReason(
        fitted,
        reason: SelectionUpdateReason.uiEvent,
      );
    });
  }

  /// [sel] clamped to the current document, or null when its nodes are gone.
  Selection? _fitSelection(Selection sel) {
    Position? fit(Position p) {
      final node = _editorState.getNodeAtPath(p.path);
      if (node == null) return null;
      final length = node.delta?.length ?? 0;
      return Position(path: p.path, offset: p.offset.clamp(0, length));
    }

    final start = fit(sel.start);
    final end = fit(sel.end);
    if (start == null || end == null) return null;
    return Selection(start: start, end: end);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editorState.selectionNotifier.removeListener(_rememberSelection);
    try {
      _editorState.selectionService.unregisterGestureInterceptor(
        _tripleClick.key,
      );
    } catch (_) {}
    if (_timer?.isActive ?? false) _flush();
    _timer?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    _editorState.dispose();
    super.dispose();
  }

  /// Hands a change that is still waiting in the debounce to [onChanged] now.
  void flushPending() {
    if (_timer?.isActive ?? false) _flush();
  }

  /// Replaces the whole document with [json] (the notes were saved elsewhere)
  /// in ONE transaction on the existing [EditorState]: the editor is not
  /// rebuilt, so the caret (kept where it still fits), the expand state and the
  /// scroll survive. Nothing is reported through `onChanged`: the new text came
  /// from the database, there is nothing to write back.
  Future<void> replaceDocument(String? json) async {
    final next = notesDocumentFromJson(json);
    final nodes = next.root.children.toList();
    final root = _editorState.document.root;
    final tx = _editorState.transaction;
    if (root.children.isNotEmpty) tx.deleteNodes(root.children.toList());
    tx.insertNodes([0], nodes);
    Position? fit(Position p) {
      final node = next.nodeAtPath(p.path);
      if (node == null) return null;
      return Position(
        path: p.path,
        offset: p.offset.clamp(0, node.delta?.length ?? 0),
      );
    }

    final sel = _editorState.selection;
    final start = sel == null ? null : fit(sel.start);
    final end = sel == null ? null : fit(sel.end);
    tx.afterSelection = start == null || end == null
        ? null
        : Selection(start: start, end: end);
    await _editorState.apply(tx);
    if (!mounted) return;
    // The transaction started the debounce: what is shown now IS the saved text.
    _timer?.cancel();
    _lastEmitted = notesDocumentToJson(_editorState.document);
  }

  void _flush() {
    _timer?.cancel();
    final json = notesDocumentToJson(_editorState.document);
    if (json == _lastEmitted) return;
    _lastEmitted = json;
    widget.onChanged(json);
  }

  /// Inserts the clipboard text, converted from Markdown, after the selected
  /// block (replacing it when it is an empty paragraph), or at the end when
  /// nothing is selected, and puts the cursor at the end of the insertion.
  Future<void> pasteAsMarkdown() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.trim().isEmpty) return;
    if (await pasteVerbatimIntoCodeBlock(_editorState, text)) return;
    // What was copied here as a code block is pasted as plain TEXT: converting
    // it would turn indented code back into a code block.
    if (NotesCopyMemory.isCodeBlock && NotesCopyMemory.last!.text == text) {
      pasteTextWithoutFormattingCommand.handler(_editorState);
      return;
    }
    final nodes = markdownToNotesDocument(text).root.children.toList();
    if (nodes.isEmpty) return;
    await _insertBlocks(nodes);
  }

  /// Inserts [nodes] after the selected block (replacing it when it is an empty
  /// paragraph), or at the end when nothing is selected, and puts the cursor at
  /// the end of the insertion.
  Future<void> _insertBlocks(List<Node> nodes) async {
    final root = _editorState.document.root;
    final selected = _editorState.selection == null
        ? null
        : _editorState.getNodeAtPath(_editorState.selection!.end.path);
    final replaceSelected =
        selected != null &&
        selected.type == 'paragraph' &&
        selected.children.isEmpty &&
        (selected.delta?.isEmpty ?? true);
    final at = selected == null
        ? [root.children.length]
        : (replaceSelected ? selected.path : selected.path.next);

    final transaction = _editorState.transaction;
    transaction.insertNodes(at, nodes);
    if (replaceSelected) transaction.deleteNode(selected);

    // Nodes are deep-copied on insert; the last inserted one sits at
    // at + (nodes.length - 1) at the same level.
    final lastPath = [...at.take(at.length - 1), at.last + nodes.length - 1];
    var last = nodes.last;
    var path = lastPath;
    while (last.children.isNotEmpty) {
      path = [...path, last.children.length - 1];
      last = last.children.last;
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: path, offset: last.delta?.length ?? 0),
    );
    await _editorState.apply(transaction);
  }

  /// Sets every checkbox row inside [sel] to [checked] in ONE transaction (one
  /// Undo step); the selection is kept so the next toggle works on the same rows.
  /// Returns how many rows it touched.
  int _setTodos(Selection sel, bool checked) {
    final todos = [
      for (final n in _editorState.getNodesInSelection(sel))
        if (n.type == 'todo_list') n,
    ];
    if (todos.isEmpty) return 0;
    final transaction = _editorState.transaction;
    for (final n in todos) {
      if ((n.attributes['checked'] == true) != checked) {
        transaction.updateNode(n, {'checked': checked});
      }
    }
    transaction.afterSelection = sel;
    _editorState.apply(transaction);
    return todos.length;
  }

  /// A tap on a checkbox: with several rows selected it sets ALL their
  /// checkboxes to the opposite of the tapped one; otherwise the normal toggle.
  void _tapCheckbox(Node node, VoidCallback onCheck) {
    final sel = _editorState.selection;
    if (sel != null && !sel.isCollapsed) {
      final inside = _editorState
          .getNodesInSelection(sel)
          .any((n) => identical(n, node) || listEquals(n.path, node.path));
      if (inside) {
        _setTodos(sel, node.attributes['checked'] != true);
        return;
      }
    }
    onCheck();
  }

  /// Ctrl+Enter on a checkbox row flips it, on a toggle row opens/closes it.
  /// With a selection over several checkbox rows it ticks them all (or clears
  /// them all when every one is ticked). False when the cursor is on any other
  /// line.
  bool _toggleCurrentRow() {
    final sel = _editorState.selection;
    if (sel == null) return false;
    if (!sel.isCollapsed) {
      final todos = [
        for (final n in _editorState.getNodesInSelection(sel))
          if (n.type == 'todo_list') n,
      ];
      if (todos.isNotEmpty) {
        _setTodos(sel, !todos.every((n) => n.attributes['checked'] == true));
        return true;
      }
    }
    final node = _editorState.getNodeAtPath(sel.end.path);
    if (node == null) return false;
    final Map<String, Object?> change;
    if (node.type == 'todo_list') {
      change = {'checked': node.attributes['checked'] != true};
    } else if (node.type == toggleListBlockType) {
      change = {
        toggleListCollapsedKey: node.attributes[toggleListCollapsedKey] != true,
      };
    } else {
      return false;
    }
    // The cursor stays where it was, so the next Ctrl+Enter flips it back.
    final transaction = _editorState.transaction
      ..updateNode(node, change)
      ..afterSelection = sel;
    _editorState.apply(transaction);
    return true;
  }


  /// Puts the selection on the clipboard as Markdown text (and remembers its
  /// blocks for an exact paste here). A selection inside ONE code block copies
  /// just its raw text.
  Future<void> copyAsMarkdown() async {
    final selection = _editorState.selection?.normalized;
    if (selection == null || selection.isCollapsed) return;
    if (listEquals(selection.start.path, selection.end.path) &&
        _editorState.getNodeAtPath(selection.start.path)?.type ==
            codeBlockType) {
      final node = _editorState.getNodeAtPath(selection.start.path)!;
      final raw = _editorState.getTextInSelection(selection).join('\n');
      // The WHOLE text of the block: remember the block, so Ctrl+V sets the
      // same code block again (a part of its text stays plain text).
      final whole =
          selection.start.offset == 0 &&
          selection.end.offset >= (node.delta?.length ?? 0);
      NotesCopyMemory.last = whole && raw.isNotEmpty
          ? (text: raw, nodes: [node.toJson()])
          : null;
      await AppFlowyClipboard.setData(text: raw.isEmpty ? null : raw);
      return;
    }
    final nodes = _editorState.getSelectedNodes(selection: selection);
    final document = Document.blank()..insert([0], nodes);
    var markdown = documentToMarkdown(
      document,
      customParsers: const [_ToggleListParser()],
    ).trimRight();
    if (markdown.isEmpty) {
      markdown = _editorState.getTextInSelection(selection).join('\n');
    }
    NotesCopyMemory.last = markdown.isEmpty
        ? null
        : (text: markdown, nodes: [for (final n in nodes) n.toJson()]);
    await AppFlowyClipboard.setData(text: markdown.isEmpty ? null : markdown);
  }

  /// The phone's paste buttons: the exact blocks when the clipboard holds what
  /// was copied here, otherwise the clipboard text converted from Markdown.
  Future<void> pasteSmart() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final stored = NotesCopyMemory.last;
    if (!mounted) return;
    final clip = data?.text;
    if (clip != null &&
        clip.isNotEmpty &&
        await pasteVerbatimIntoCodeBlock(_editorState, clip)) {
      return;
    }
    if (stored != null && data?.text == stored.text) {
      await _pasteNodes([for (final j in stored.nodes) Node.fromJson(j)]);
    } else {
      await pasteAsMarkdown();
    }
  }

  /// Cut: [copyAsMarkdown], then delete the selection.
  Future<void> _cutSelection() async {
    final selection = _editorState.selection?.normalized;
    if (selection == null || selection.isCollapsed) return;
    await copyAsMarkdown();
    await _editorState.deleteSelection(selection);
    final transaction = _editorState.transaction
      ..afterSelection = Selection.collapsed(selection.start);
    await _editorState.apply(transaction);
  }

  /// Ctrl+V inside a code block: the clipboard text goes in unchanged, all its
  /// lines in the same block.
  Future<void> _pasteIntoCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) return;
    await pasteVerbatimIntoCodeBlock(_editorState, text);
  }

  /// Ctrl+V with something copied here: the stored blocks when the clipboard
  /// still holds their text, else the package's own paste.
  Future<void> _pasteInApp(EditorState state) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final stored = NotesCopyMemory.last;
    if (!mounted) return;
    if (stored == null || data?.text != stored.text) {
      pasteCommand.handler(state);
      return;
    }
    // A code block pasted while the caret is inside a code block is its text.
    final at = state.selection == null
        ? null
        : state.getNodeAtPath(state.selection!.start.path);
    if (NotesCopyMemory.isCodeBlock && at?.type == codeBlockType) {
      await pasteVerbatimIntoCodeBlock(state, stored.text);
      return;
    }
    final nodes = [for (final j in stored.nodes) Node.fromJson(j)];
    await _pasteNodes(nodes);
  }

  /// Inserts [nodes] at the cursor: over a selection first deleting it; a single
  /// plain paragraph merges into the text, anything else is inserted as blocks
  /// after the current block (replacing an empty paragraph).
  Future<void> _pasteNodes(List<Node> nodes) async {
    if (nodes.isEmpty) return;
    await _editorState.deleteSelectionIfNeeded();
    final sel = _editorState.selection;
    final target = sel == null ? null : _editorState.getNodeAtPath(sel.end.path);
    if (sel != null &&
        target != null &&
        target.delta != null &&
        nodes.length == 1 &&
        nodes.first.type == 'paragraph' &&
        nodes.first.children.isEmpty &&
        nodes.first.delta != null) {
      final delta = nodes.first.delta!;
      final index = sel.end.offset;
      final transaction = _editorState.transaction
        ..insertTextDelta(target, index, delta)
        ..afterSelection = Selection.collapsed(
          Position(path: target.path, offset: index + delta.length),
        );
      await _editorState.apply(transaction);
      return;
    }
    await _insertBlocks(nodes);
  }

  /// Appends a new section at the end: a heading, then one empty checkbox per
  /// group with its items nested below it. Returns false when [groups] is
  /// empty. The whole append is one editor transaction (editor Undo reverts it).
  Future<bool> appendChecklistSection(
    String heading,
    List<(String, List<String>)> groups,
  ) async {
    if (groups.isEmpty) return false;
    final root = _editorState.document.root;
    final transaction = _editorState.transaction;
    final nodes = <Node>[
      headingNode(level: 2, text: heading),
      for (final (tag, items) in groups)
        todoListNode(
          checked: false,
          text: tag,
          children: [
            for (final item in items) todoListNode(checked: false, text: item),
          ],
        ),
    ];
    transaction.insertNodes([root.children.length], nodes);
    await _editorState.apply(transaction);
    _flush();
    return true;
  }

  /// Reverts the last editor change (used by the transfer's Undo).
  void undoLastEdit() => _editorState.undoManager.undo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor = scheme.onSurface;
    final base = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: usePhoneLayout(context) ? 17 : 16,
      color: textColor,
    );
    _liveScheme = scheme;
    if (_blocks == null || _blocksScheme != scheme) {
      _blocks = _buildBlocks(scheme);
      _blocksScheme = scheme;
    }

    final textConfig = TextStyleConfiguration(
      text: base,
      bold: const TextStyle(fontWeight: FontWeight.w700),
      href: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        color: scheme.error,
        fontFamily: 'Consolas',
        fontFamilyFallback: const ['Menlo', 'Courier New'],
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      lineHeight: 1.45,
    );
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final selectionColor = scheme.primary.withValues(alpha: 0.25);
    // The desktop style makes the selection handles and the magnifier
    // transparent and zero-sized, which on a real phone left no way to move the
    // caret or the selection. Touch platforms get the mobile style (visible
    // handles in the accent colour, a bigger ball to grab); the link decorator
    // stays the desktop one so links behave as before.
    final touch =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final style = touch
        ? EditorStyle.mobile(
            padding: padding,
            cursorColor: scheme.primary,
            dragHandleColor: scheme.primary,
            selectionColor: selectionColor,
            textStyleConfiguration: textConfig,
            textSpanDecorator: defaultTextSpanDecoratorForAttribute,
            mobileDragHandleBallSize: const Size(12, 12),
            mobileDragHandleWidth: 3,
          )
        : EditorStyle.desktop(
            padding: padding,
            cursorColor: scheme.primary,
            selectionColor: selectionColor,
            textStyleConfiguration: textConfig,
          );

    final toolbarStyle = FloatingToolbarStyle(
      backgroundColor: scheme.surfaceContainerHighest,
      toolbarActiveColor: scheme.primary,
      toolbarIconColor: scheme.onSurface,
      toolbarShadowColor: Colors.black54,
      toolbarElevation: 4,
    );
    final floatingItems = [
      ...markdownFormatItems.where(
        (i) => const {
          'editor.bold',
          'editor.italic',
          'editor.strikethrough',
          'editor.code',
        }.contains(i.id),
      ),
      linkItem,
      // No keyboard shortcuts on a phone: Markdown copy/paste live in the
      // selection toolbar next to the formatting items.
      if (usePhoneLayout(context)) ...[
        _markdownItem('notes.copy_md', 'Copy MD', copyAsMarkdown),
        _markdownItem('notes.paste_md', 'Paste MD', pasteSmart),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbarRow(scheme),
        if (widget.toolbarExtra != null)
          widget.toolbarExtra!(_buildExpandToggle()),
        const SizedBox(height: 4),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.06 : 0.45,
            ),
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: FloatingToolbar(
            items: floatingItems,
            style: toolbarStyle,
            editorState: _editorState,
            editorScrollController: _scrollController,
            textDirection: TextDirection.ltr,
            child: _withScrollHandOff(
              context,
              AppFlowyEditor(
                editorState: _editorState,
                editorScrollController: _scrollController,
                editorStyle: style,
                blockComponentBuilders: _blocks!,
                characterShortcutEvents: _characters,
                commandShortcutEvents: _commands,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Phone: clamping physics make the editor's list report the drag it cannot
  /// use ([OverscrollNotification]); that rest moves the OUTER scroll view.
  Widget _withScrollHandOff(BuildContext context, Widget bare) {
    // A swipe right / left on a line is Tab / Shift+Tab (touch only).
    final editor = SwipeIndentDetector(editorState: _editorState, child: bare);
    final outer = widget.outerScroll;
    if (outer == null || !usePhoneLayout(context)) return editor;
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical || !outer.hasClients) return false;
        final p = outer.position;
        final target = (p.pixels + n.overscroll).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        );
        if (target != p.pixels) outer.jumpTo(target);
        return true;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(
          context,
        ).copyWith(physics: const ClampingScrollPhysics()),
        child: editor,
      ),
    );
  }

  ToolbarItem _markdownItem(String id, String label, VoidCallback onTap) =>
      ToolbarItem(
        id: id,
        group: 9,
        isActive: (_) => true,
        builder: (context, editorState, highlightColor, iconColor, tooltip) =>
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(label),
            ),
      );

  Widget _buildToolbarRow(ColorScheme scheme) {
    // Buttons that look like buttons before any hover: a soft tinted fill and
    // a thin border, bold labels.
    final buttonStyle = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      backgroundColor: scheme.primary.withValues(alpha: 0.12),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The left buttons wrap onto a second line on a narrow phone.
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              // Windows: Ctrl+Shift+V does it. A phone keeps the button as a
              // fallback next to the selection toolbar's Paste MD.
              if (usePhoneLayout(context))
                TextButton(
                  style: buttonStyle,
                  onPressed: pasteSmart,
                  child: const Text('Paste as Markdown'),
                ),
            ],
          ),
        ),
        // Full screen hides the dialog's own buttons: Save lives here.
        if (widget.expanded && widget.onSave != null) ...[
          TextButton(
            key: const ValueKey('notes-save'),
            style: buttonStyle,
            onPressed: () {
              _flush();
              widget.onSave?.call();
            },
            child: const Text('Save'),
          ),
          const SizedBox(width: 6),
        ],
        if (widget.toolbarExtra == null) ?_buildExpandToggle(),
      ],
    );
  }

  Widget? _buildExpandToggle() => widget.onToggleExpand == null
      ? null
      : IconButton(
          key: const ValueKey('notes-expand-toggle'),
          padding: EdgeInsets.zero,
          iconSize: 17,
          tooltip: widget.expanded ? 'Collapse' : 'Expand',
          icon: Icon(
            widget.expanded ? Icons.fullscreen_exit : Icons.fullscreen,
          ),
          onPressed: widget.onToggleExpand,
        );

  Map<String, BlockComponentBuilder> _buildBlocks(ColorScheme scheme) {
    BlockComponentConfiguration plain([String Function(Node)? placeholder]) =>
        BlockComponentConfiguration(
          placeholderText: placeholder ?? (_) => '',
          placeholderTextStyle: (_, {textSpan}) =>
              TextStyle(color: _liveScheme.onSurface.withValues(alpha: 0.4)),
        );

    String firstHint(Node node) =>
        node.path.length == 1 &&
            node.path.first == 0 &&
            _editorState.document.root.children.length == 1
        ? 'Notes — type [] for a checklist'
        : '';

    Widget checkbox(BuildContext context, Node node, VoidCallback onCheck) {
      final checked = node.attributes[TodoListBlockKeys.checked] == true;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapCheckbox(node, onCheck),
        child: Padding(
          padding: const EdgeInsets.only(right: 6, top: 2),
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    TextStyle heading(int level) => TextStyle(
      fontSize: switch (level) {
        1 => 24.0,
        2 => 20.0,
        3 => 17.0,
        _ => 15.0,
      },
      fontWeight: FontWeight.w700,
    );

    return {
      PageBlockKeys.type: PageBlockComponentBuilder(),
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: plain(firstHint),
      ),
      TodoListBlockKeys.type: TodoListBlockComponentBuilder(
        configuration: plain(),
        iconBuilder: checkbox,
        textStyleBuilder: (checked) => checked
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: _liveScheme.onSurface.withValues(alpha: 0.55),
              )
            : const TextStyle(),
      ),
      BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
        configuration: plain(),
      ),
      NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
        configuration: plain(),
      ),
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: plain((node) => 'Heading'),
        textStyleBuilder: heading,
      ),
      ...notesExtraBlockBuilders(),
    };
  }
}

/// Markdown for a toggle row (the package has no parser for it): a bullet with
/// the children indented under it.
class _ToggleListParser extends NodeParser {
  const _ToggleListParser();

  @override
  String get id => toggleListBlockType;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final delta = node.delta ?? (Delta()..insert(''));
    final children = encoder?.convertNodes(node.children, withIndent: true);
    var markdown = '* ${DeltaMarkdownEncoder().convert(delta)}\n';
    if (children != null && children.isNotEmpty) markdown += children;
    return markdown;
  }
}
