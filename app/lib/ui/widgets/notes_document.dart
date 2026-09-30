import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

/// Pure helpers for the notes editor's document (no widget code): JSON
/// (de)serialisation, emptiness, checklist reset and Markdown import.

const _listTypes = {'todo_list', 'bulleted_list', 'numbered_list'};

Document _blank() => Document.blank(withInitialText: true);

/// Parses the stored `actions.notes` JSON. Null, empty, corrupt or
/// structurally empty input yields a blank document (one empty paragraph);
/// this never throws.
Document notesDocumentFromJson(String? json) {
  if (json == null || json.trim().isEmpty) return _blank();
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return _blank();
    final doc = Document.fromJson(Map<String, dynamic>.from(decoded));
    if (doc.root.children.isEmpty) return _blank();
    return doc;
  } catch (_) {
    return _blank();
  }
}

/// True when the document has no text and no non-paragraph blocks (only empty
/// paragraphs, possibly several).
bool notesDocumentIsEmpty(Document doc) {
  bool emptyNode(Node n) =>
      n.type == 'paragraph' &&
      (n.delta?.toPlainText().isEmpty ?? true) &&
      n.children.every(emptyNode);
  return doc.root.children.every(emptyNode);
}

/// The JSON to store for [doc], or null when it is empty.
String? notesDocumentToJson(Document doc) =>
    notesDocumentIsEmpty(doc) ? null : jsonEncode(doc.toJson());

/// Sets `checked: false` on every `todo_list` node (recursively) in one
/// transaction. Does nothing when no item is checked.
Future<void> resetChecklist(EditorState state) async {
  final transaction = state.transaction;
  var changed = false;
  void walk(Node node) {
    if (node.type == 'todo_list' && node.attributes['checked'] == true) {
      transaction.updateNode(node, {'checked': false});
      changed = true;
    }
    node.children.forEach(walk);
  }

  state.document.root.children.forEach(walk);
  if (changed) await state.apply(transaction);
}

/// Converts Markdown to a document. On top of the package's
/// `markdownToDocument` it trims the leading whitespace list items keep after
/// their marker (`- [ ]  text`) and turns fenced code blocks, which the
/// package silently drops, into `code` nodes at the right position.
Document markdownToNotesDocument(String markdown) {
  final nodes = <Node>[];
  final buffer = <String>[];
  final code = <String>[];
  var inFence = false;

  void flushText() {
    if (buffer.isEmpty) return;
    final text = buffer.join('\n');
    buffer.clear();
    if (text.trim().isEmpty) return;
    nodes.addAll(markdownToDocument(text).root.children.toList());
  }

  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final isFence = line.trimLeft().startsWith('```');
    if (!inFence && isFence) {
      flushText();
      inFence = true;
    } else if (inFence && isFence) {
      nodes.add(_codeNode(code.join('\n')));
      code.clear();
      inFence = false;
    } else if (inFence) {
      code.add(line);
    } else {
      buffer.add(line);
    }
  }
  // An unterminated fence: keep what was typed as code.
  if (inFence) nodes.add(_codeNode(code.join('\n')));
  flushText();

  for (final node in nodes) {
    _trimListText(node);
  }

  final doc = Document.blank();
  // Detach nodes from their previous parent before re-parenting.
  for (final n in nodes) {
    n.unlink();
  }
  if (nodes.isNotEmpty) doc.insert([0], nodes);
  return doc;
}

Node _codeNode(String text) =>
    Node(type: 'code', attributes: {'delta': (Delta()..insert(text)).toJson()});

void _trimListText(Node node) {
  if (_listTypes.contains(node.type)) {
    final delta = node.delta;
    if (delta != null) {
      final ops = delta.toList();
      final trimmed = Delta();
      var leading = true;
      for (final op in ops) {
        if (op is TextInsert) {
          var text = op.text;
          if (leading) {
            text = text.trimLeft();
            if (text.isEmpty) continue;
            leading = false;
          }
          trimmed.insert(text, attributes: op.attributes);
        } else {
          leading = false;
          trimmed.add(op);
        }
      }
      if (trimmed.toPlainText() != delta.toPlainText()) {
        node.updateAttributes({'delta': trimmed.toJson()});
      }
    }
  }
  node.children.forEach(_trimListText);
}
