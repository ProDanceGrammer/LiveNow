import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../dialog_stack.dart';
import 'direction_badge.dart' show emojiLabelStyle;

/// Opens the emoji / flag chooser; null when closed without a choice. Flags
/// are drawn with the bundled Twemoji font first (Segoe UI Emoji shows a flag
/// as two letters on Windows), the same order as everywhere else.
Future<String?> pickEmoji(BuildContext context) => showStackedDialog<String>(
  context: context,
  builder: (dialogContext) {
    final scheme = Theme.of(dialogContext).colorScheme;
    return Dialog(
      child: SizedBox(
        width: 440,
        height: 420,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) =>
              Navigator.of(dialogContext).pop(emoji.emoji),
          config: Config(
            height: 420,
            emojiTextStyle: emojiLabelStyle.copyWith(fontSize: 24),
            emojiViewConfig: const EmojiViewConfig(emojiSizeMax: 28),
            categoryViewConfig: const CategoryViewConfig(
              initCategory: Category.SMILEYS,
            ),
            // The magnifier in the bottom bar opens the search (by name, English).
            bottomActionBarConfig: BottomActionBarConfig(
              showBackspaceButton: false,
              backgroundColor: scheme.surfaceContainerHighest,
              buttonColor: scheme.primary,
              buttonIconColor: scheme.onPrimary,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: scheme.surfaceContainerHighest,
              buttonIconColor: scheme.onSurfaceVariant,
              hintText: 'Search emoji or flag',
            ),
          ),
        ),
      ),
    );
  },
);

/// A small button beside an icon / name text box that opens [pickEmoji] and
/// puts the choice into [controller]: it REPLACES the text when [replace]
/// (an icon field holds one emoji), else it is inserted at the cursor (a name).
/// Typing an emoji by keyboard keeps working.
class EmojiPickerButton extends StatelessWidget {
  const EmojiPickerButton({
    super.key,
    required this.controller,
    this.replace = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool replace;

  /// Called after the controller changed (e.g. to rebuild a dirty check).
  final VoidCallback? onChanged;

  Future<void> _pick(BuildContext context) async {
    final emoji = await pickEmoji(context);
    if (emoji == null) return;
    final t = controller.text;
    if (replace) {
      controller.text = emoji;
      controller.selection = TextSelection.collapsed(offset: emoji.length);
    } else {
      final sel = controller.selection;
      final at = sel.isValid ? sel.start : t.length;
      final end = sel.isValid ? sel.end : t.length;
      controller.text = t.replaceRange(at, end, emoji);
      controller.selection = TextSelection.collapsed(offset: at + emoji.length);
    }
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('emoji-picker-button'),
    icon: const Icon(Icons.emoji_emotions_outlined),
    tooltip: 'Pick an emoji or flag',
    visualDensity: VisualDensity.compact,
    onPressed: () => _pick(context),
  );
}
