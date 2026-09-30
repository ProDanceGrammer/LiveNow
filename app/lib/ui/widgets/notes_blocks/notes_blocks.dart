import 'package:appflowy_editor/appflowy_editor.dart';

import 'code_block.dart';
import 'toggle_list_block.dart';

export 'code_block.dart'
    show
        CodeBlockComponentBuilder,
        CodeBlockComponentWidget,
        codeBlockBackspaceCommand,
        codeBlockNode,
        formatBackticksToCodeBlock,
        codeBlockType;
export 'toggle_list_block.dart'
    show
        ToggleListBlockComponentBuilder,
        ToggleListBlockComponentWidget,
        formatGreaterToToggleList,
        toggleListBackspaceCommand,
        toggleListBlockType,
        toggleListCollapsedKey,
        toggleListNode;

/// Custom block builders. Merge after the standard map:
/// `{...standardBlockComponentBuilderMap, ...customNotesBlockBuilders()}`.
///
/// Side effect (idempotent): registers `toggle_list` in the package's global
/// `indentableBlockTypes`, so the standard Tab / Shift+Tab commands can nest
/// paragraphs and lists under a toggle and nest the toggle itself.
Map<String, BlockComponentBuilder> customNotesBlockBuilders() {
  indentableBlockTypes.add(toggleListBlockType);
  return {
    toggleListBlockType: ToggleListBlockComponentBuilder(
      configuration: const BlockComponentConfiguration(
        placeholderText: _toggleHint,
      ),
    ),
    codeBlockType: CodeBlockComponentBuilder(),
  };
}

String _toggleHint(Node node) => 'Toggle';

/// Must be inserted BEFORE `markdownSyntaxShortcutEvents` (the single-backtick
/// inline-code shortcut would otherwise swallow the backticks) and before the
/// standard `insertNewLine` (Enter handlers). Contains:
/// formatBackticksToCodeBlock, formatGreaterToToggleList, plus the Enter
/// handlers for code blocks and toggles.
List<CharacterShortcutEvent> customNotesCharacterShortcuts() => [
  insertNewLineInCodeBlock,
  insertNewLineInToggleList,
  formatBackticksToCodeBlock,
  formatGreaterToToggleList,
];

/// Must be inserted BEFORE `standardCommandShortcutEvents` (Tab in a code
/// block; Backspace in empty code block / at start of a toggle).
List<CommandShortcutEvent> customNotesCommandShortcuts() => [
  codeBlockTabCommand,
  codeBlockBackspaceCommand,
  toggleListBackspaceCommand,
];
