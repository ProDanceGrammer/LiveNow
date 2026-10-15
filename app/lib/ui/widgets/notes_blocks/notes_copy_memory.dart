/// What the notes editors last copied: the exact text put on the clipboard and
/// the blocks as JSON. A later paste whose clipboard text is still that text
/// restores the blocks with every attribute (the clipboard itself can only carry
/// the text). Shared by every notes editor of the app and by a code block's Copy
/// button.
class NotesCopyMemory {
  NotesCopyMemory._();

  static ({String text, List<Map<String, Object>> nodes})? last;

  /// True when the last copy was ONE code block (a whole block, not a part of its
  /// text).
  static bool get isCodeBlock {
    final l = last;
    return l != null && l.nodes.length == 1 && l.nodes.first['type'] == 'code';
  }
}
