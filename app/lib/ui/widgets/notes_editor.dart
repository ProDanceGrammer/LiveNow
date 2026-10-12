import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart' hide Overlay, OverlayEntry;
import 'package:flutter/services.dart';

import '../layout.dart';
import 'notes_blocks/notes_blocks.dart';
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

  /// Extra controls in the toolbar row (the action editor's "What is done?").
  final Widget? toolbarExtra;

  const NotesEditor({
    super.key,
    this.initialJson,
    required this.onChanged,
    this.height = 320,
    this.expanded = false,
    this.onToggleExpand,
    this.onSave,
    this.toolbarExtra,
  });

  @override
  State<NotesEditor> createState() => NotesEditorState();
}

class NotesEditorState extends State<NotesEditor> {
  static const _debounce = Duration(milliseconds: 400);

  late final EditorState _editorState;
  late final EditorScrollController _scrollController;
  late final List<CommandShortcutEvent> _commands;
  late final List<CharacterShortcutEvent> _characters;
  // Rebuilt only when the theme changes: handing the editor fresh builder
  // objects on every parent rebuild would needlessly re-create its blocks.
  Map<String, BlockComponentBuilder>? _blocks;
  ColorScheme? _blocksScheme;
  StreamSubscription<EditorTransactionValue>? _sub;
  Timer? _timer;
  String? _lastEmitted;

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
      ...standardCommandShortcutEvents.where(
        (e) => e.key != pasteTextWithoutFormattingCommand.key,
      ),
    ];
    _sub = _editorState.transactionStream.listen((event) {
      if (event.$2.operations.isEmpty) return;
      _timer?.cancel();
      _timer = Timer(_debounce, _flush);
    });
  }

  @override
  void dispose() {
    if (_timer?.isActive ?? false) _flush();
    _timer?.cancel();
    _sub?.cancel();
    _scrollController.dispose();
    _editorState.dispose();
    super.dispose();
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
    final nodes = markdownToNotesDocument(text).root.children.toList();
    if (nodes.isEmpty) return;

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

  Future<void> _resetChecklist() => resetChecklist(_editorState);

  /// Ctrl+Enter on a checkbox row flips it, on a toggle row opens/closes it.
  /// False when the cursor is on any other line.
  bool _toggleCurrentRow() {
    final sel = _editorState.selection;
    if (sel == null) return false;
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

  /// Puts the selection on the clipboard as Markdown text.
  Future<void> copyAsMarkdown() async {
    final selection = _editorState.selection?.normalized;
    if (selection == null || selection.isCollapsed) return;
    final nodes = _editorState.getSelectedNodes(selection: selection);
    final document = Document.blank()..insert([0], nodes);
    var markdown = documentToMarkdown(
      document,
      customParsers: const [_ToggleListParser()],
    ).trimRight();
    if (markdown.isEmpty) {
      markdown = _editorState.getTextInSelection(selection).join('\n');
    }
    await AppFlowyClipboard.setData(text: markdown.isEmpty ? null : markdown);
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
    if (_blocks == null || _blocksScheme != scheme) {
      _blocks = _buildBlocks(scheme);
      _blocksScheme = scheme;
    }

    final style = EditorStyle.desktop(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.25),
      textStyleConfiguration: TextStyleConfiguration(
        text: base,
        bold: const TextStyle(fontWeight: FontWeight.w700),
        href: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: TextStyle(
          color: scheme.error,
          fontFamily: 'Consolas',
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        lineHeight: 1.45,
      ),
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
        _markdownItem('notes.paste_md', 'Paste MD', pasteAsMarkdown),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbarRow(scheme),
        if (widget.toolbarExtra != null) widget.toolbarExtra!,
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
            child: AppFlowyEditor(
              editorState: _editorState,
              editorScrollController: _scrollController,
              editorStyle: style,
              blockComponentBuilders: _blocks!,
              characterShortcutEvents: _characters,
              commandShortcutEvents: _commands,
            ),
          ),
        ),
      ],
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
              TextButton(
                style: buttonStyle,
                onPressed: _resetChecklist,
                child: const Text('Reset checkboxes'),
              ),
              // Windows: Ctrl+Shift+V does it. A phone keeps the button as a
              // fallback next to the selection toolbar's Paste MD.
              if (usePhoneLayout(context))
                TextButton(
                  style: buttonStyle,
                  onPressed: pasteAsMarkdown,
                  child: const Text('Paste as Markdown'),
                ),
            ],
          ),
        ),
        if (widget.onToggleExpand != null)
          TextButton(
            style: buttonStyle,
            onPressed: widget.onToggleExpand,
            child: Text(widget.expanded ? 'Collapse' : 'Expand'),
          ),
      ],
    );
  }

  Map<String, BlockComponentBuilder> _buildBlocks(ColorScheme scheme) {
    BlockComponentConfiguration plain([String Function(Node)? placeholder]) =>
        BlockComponentConfiguration(
          placeholderText: placeholder ?? (_) => '',
          placeholderTextStyle: (_, {textSpan}) =>
              TextStyle(color: scheme.onSurface.withValues(alpha: 0.4)),
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
        onTap: onCheck,
        child: Padding(
          padding: const EdgeInsets.only(right: 6, top: 2),
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? scheme.primary : scheme.onSurfaceVariant,
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
                color: scheme.onSurface.withValues(alpha: 0.55),
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
