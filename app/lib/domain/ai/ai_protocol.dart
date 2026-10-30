/// The vocabulary the chat (phone / desktop), the hub's worker and the sync
/// share: message roles and kinds, the job state machine, and the JSON shapes
/// of the cards stored in `ai_messages.content_json` / `ai_jobs.payload_json`.
/// Plain strings (not enums) in the database so an older app tolerates a newer
/// value; the constants here are the only place they are spelled.
library;

import 'dart:convert';

/// `ai_messages.role`
abstract final class AiRole {
  static const user = 'user';
  static const assistant = 'assistant';
  static const system = 'system';
}

/// `ai_messages.kind`
abstract final class AiMessageKind {
  /// Plain text (a user line, an assistant sentence).
  static const text = 'text';

  /// A user message carrying a photo (the image is in `ai_blobs`).
  static const photo = 'photo';

  /// The live status line of a job (the worker updates ONE row in place).
  static const status = 'status';

  /// The assistant's draft: lines, categories, sums. Nothing is written yet.
  static const draft = 'draft';

  /// Numbered questions with options (see [QuestionCard]).
  static const question = 'question';

  /// What was recorded after a commit (lines + the batch id for Undo).
  static const result = 'result';

  /// The user's decision on a draft: confirm / reject (+ line edits).
  static const confirm = 'confirm';

  /// Something went wrong (the text says what to do).
  static const error = 'error';
}

/// `ai_jobs.state`
abstract final class AiJobState {
  static const queued = 'queued';
  static const running = 'running';

  /// Waiting for the user to answer a question card.
  static const needsInput = 'needs_input';

  /// A draft is shown; waiting for Confirm / Reject.
  static const draftReady = 'draft_ready';
  static const committing = 'committing';
  static const done = 'done';
  static const failed = 'failed';

  /// States in which the worker still has something to do.
  static const active = {queued, running, committing};

  /// States that wait for the user.
  static const waiting = {needsInput, draftReady};

  static bool isFinal(String s) => s == done || s == failed;
}

/// `ai_jobs.kind`
abstract final class AiJobKind {
  /// A photo of a shop receipt.
  static const receipt = 'receipt';

  /// A photo of a bank screenshot (amount + rate).
  static const screenshot = 'screenshot';

  /// A bazaar checklist pasted as text.
  static const bazaar = 'bazaar';

  /// A free-text request ('moved 12,582.50 from FOP to Monobank').
  static const text = 'text';
}

/// Stage strings the worker writes to `ai_jobs.stage` and the status message.
abstract final class AiStage {
  static const queued = 'Queued';
  static const reading = 'Reading receipt';
  static const matching = 'Matching categories';
  static const checking = 'Checking sums';
  static const waiting = 'Waiting for you';
  static const saving = 'Saving';
  static const done = 'Done';
}

/// `ai_messages.content_json` of a [AiMessageKind.question] message.
class QuestionCard {
  const QuestionCard(this.questions);

  final List<Question> questions;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'questions': [for (final q in questions) q.toJson()],
  };

  factory QuestionCard.fromJson(Map<String, dynamic> j) => QuestionCard([
    if (j['questions'] is List)
      for (final q in j['questions'] as List)
        if (q is Map) Question.fromJson(Map<String, dynamic>.from(q)),
  ]);
}

class Question {
  const Question({
    required this.id,
    required this.text,
    this.options = const [],
    this.recommended,
    this.answer,
  });

  /// Stable within the job (e.g. `weight:3`), so an answer maps back to a line.
  final String id;
  final String text;
  final List<String> options;

  /// Index into [options] the assistant recommends (a quick-reply chip).
  final int? recommended;

  /// Set when the user answered (the worker reads it).
  final String? answer;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'options': options,
    'recommended': recommended,
    'answer': answer,
  };

  factory Question.fromJson(Map<String, dynamic> j) => Question(
    id: (j['id'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    options: [
      if (j['options'] is List)
        for (final o in j['options'] as List) o.toString(),
    ],
    recommended: j['recommended'] is int ? j['recommended'] as int : null,
    answer: j['answer']?.toString(),
  );
}

/// `ai_messages.content_json` of a [AiMessageKind.confirm] message: the user's
/// decision on a draft. `action` is `confirm` or `reject`; `edits` are line
/// changes made in the tap-to-edit sheet before confirming.
class ConfirmDecision {
  const ConfirmDecision({
    required this.draftMessageId,
    required this.confirm,
    this.edits = const [],
  });

  final String draftMessageId;
  final bool confirm;
  final List<LineEdit> edits;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'draft_message_id': draftMessageId,
    'action': confirm ? 'confirm' : 'reject',
    'edits': [for (final e in edits) e.toJson()],
  };

  factory ConfirmDecision.fromJson(Map<String, dynamic> j) => ConfirmDecision(
    draftMessageId: (j['draft_message_id'] ?? '').toString(),
    confirm: j['action'] != 'reject',
    edits: [
      if (j['edits'] is List)
        for (final e in j['edits'] as List)
          if (e is Map) LineEdit.fromJson(Map<String, dynamic>.from(e)),
    ],
  );
}

/// A change to one draft line (null = unchanged).
class LineEdit {
  const LineEdit({
    required this.index,
    this.categoryId,
    this.quantity,
    this.unitPrice,
  });

  final int index;
  final String? categoryId;
  final double? quantity;
  final double? unitPrice;

  Map<String, dynamic> toJson() => {
    'i': index,
    'category_id': categoryId,
    'quantity': quantity,
    'unit_price': unitPrice,
  };

  factory LineEdit.fromJson(Map<String, dynamic> j) => LineEdit(
    index: (j['i'] as num?)?.toInt() ?? 0,
    categoryId: j['category_id']?.toString(),
    quantity: (j['quantity'] as num?)?.toDouble(),
    unitPrice: (j['unit_price'] as num?)?.toDouble(),
  );
}

/// `ai_jobs.payload_json`: what the worker needs to start.
class JobPayload {
  const JobPayload({this.messageId, this.blobIds = const [], this.text});

  /// The user message that started the job.
  final String? messageId;

  /// `ai_blobs` ids (the photos), in order.
  final List<String> blobIds;

  /// Pasted text (bazaar note / free text), when the job has no photo.
  final String? text;

  String encode() => jsonEncode({
    'message_id': messageId,
    'blob_ids': blobIds,
    'text': text,
  });

  factory JobPayload.decode(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! Map) return const JobPayload();
      return JobPayload(
        messageId: j['message_id']?.toString(),
        blobIds: [
          if (j['blob_ids'] is List)
            for (final b in j['blob_ids'] as List) b.toString(),
        ],
        text: j['text']?.toString(),
      );
    } catch (_) {
      return const JobPayload();
    }
  }
}

/// `ai_settings` keys (the hub's device-local settings).
abstract final class AiSettingKey {
  static const llmUrl = 'llm_url';
  static const llmModel = 'llm_model';
  static const llmToken = 'llm_token';
  static const ocrUrl = 'ocr_url';
  static const visionModel = 'vision_model';

  /// How many receipts need a draft first (then auto-commit). Default 5.
  static const draftFirstCount = 'draft_first_count';

  /// How many receipts were already confirmed (drives the switch above).
  static const confirmedCount = 'confirmed_count';
  static const photoRetentionDays = 'photo_retention_days';
}
