import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_draft.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_providers.dart';
import 'ai_line_details_sheet.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

/// Numbered questions with quick-reply chips (the recommended one highlighted)
/// and a free-text field. Answering writes into the card through the chat
/// service; the hub notices the answered card and resumes. When the draft of the
/// same job is known ([draft]), a question about a line shows that line's data and
/// opens its details on tap (price, quantity, the offered categories).
class AiQuestionCard extends ConsumerWidget {
  const AiQuestionCard({
    super.key,
    required this.message,
    this.latest = true,
    this.draft,
  });

  final AiMessage message;
  final bool latest;
  final DraftCard? draft;

  /// The draft line a `cat:3` / `weight:3` question is about.
  DraftLine? _lineOf(String questionId) {
    final m = RegExp(r'^(?:cat|weight):(\d+)$').firstMatch(questionId);
    final d = draft;
    if (m == null || d == null) return null;
    final i = int.parse(m[1]!);
    for (final l in d.lines) {
      if (l.index == i) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = QuestionCard.fromJson(aiContent(message));
    final theme = Theme.of(context);
    return AiBubbleFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.body.isNotEmpty) Text(message.body),
          for (var q = 0; q < card.questions.length; q++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _QuestionRow(
                messageId: message.id,
                number: q,
                question: card.questions[q],
                latest: latest,
                theme: theme,
                line: _lineOf(card.questions[q].id),
                currency: draft?.currency ?? 'TRY',
              ),
            ),
        ],
      ),
    );
  }
}

class _QuestionRow extends ConsumerStatefulWidget {
  const _QuestionRow({
    required this.messageId,
    required this.number,
    required this.question,
    required this.latest,
    required this.theme,
    required this.line,
    required this.currency,
  });

  final String messageId;
  final int number;
  final Question question;
  final bool latest;
  final ThemeData theme;
  final DraftLine? line;
  final String currency;

  @override
  ConsumerState<_QuestionRow> createState() => _QuestionRowState();
}

class _QuestionRowState extends ConsumerState<_QuestionRow> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _key(String base) =>
      widget.latest ? base : '$base-${widget.messageId}';

  Future<void> _answer(String a, {String? optionId}) async {
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiChatServiceProvider);
    try {
      await service.answerQuestion(
        widget.messageId,
        widget.question.id,
        a,
        optionId: optionId,
      );
      _text.clear();
    } catch (e) {
      showInfoToast(overlay, '$e');
    }
  }

  /// The id of option [i] (see `Question.optionIds`), when the card has ids.
  String? _idOf(int i) {
    final ids = widget.question.optionIds;
    return i < ids.length && ids[i].isNotEmpty ? ids[i] : null;
  }

  /// The offered category behind option [i] (matched by id), when the line is known.
  DraftChoice? _choiceOfOption(int i) {
    final id = _idOf(i);
    final line = widget.line;
    if (id == null || line == null) return null;
    for (final c in line.candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _openDetails() {
    final line = widget.line!;
    return showAiLineDetails(
      context,
      line: line,
      currency: widget.currency,
      onChoose: widget.question.answer == null
          ? (c) => _answer(c.label, optionId: c.id)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final cs = widget.theme.colorScheme;
    final line = widget.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey(_key('ai-question-open-${widget.number}')),
          onTap: line == null ? null : _openDetails,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text('${widget.number + 1}. ${q.text}')),
                  if (line != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 6, top: 2),
                      child: Icon(Icons.info_outline, size: 16),
                    ),
                ],
              ),
              if (line != null)
                Text(
                  '${line.raw}  —  ${aiLineSummary(line, widget.currency)}',
                  key: ValueKey(_key('ai-question-line-${widget.number}')),
                  style: widget.theme.textTheme.labelMedium,
                ),
              if (line != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Details',
                    key: ValueKey(_key('ai-question-details-${widget.number}')),
                    style: widget.theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (q.answer != null)
          Text(
            'Answer: ${q.answer}',
            style: widget.theme.textTheme.labelMedium,
          )
        else ...[
          for (var i = 0; i < q.options.length; i++)
            if (_choiceOfOption(i) case final c?)
              // Its own Material: the chat bubble paints a coloured box behind.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: ValueKey(_key('ai-question-chip-${widget.number}-$i')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  tileColor: q.recommended == i ? cs.primaryContainer : null,
                  title: Text(c.label),
                  subtitle: choiceHint(c).isEmpty ? null : Text(choiceHint(c)),
                  trailing: IconButton(
                    key: ValueKey(_key('ai-question-info-${widget.number}-$i')),
                    tooltip: 'Details',
                    icon: const Icon(Icons.info_outline, size: 18),
                    onPressed: _openDetails,
                  ),
                  onTap: () => _answer(q.options[i], optionId: _idOf(i)),
                ),
              ),
          if (q.options.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < q.options.length; i++)
                  if (_choiceOfOption(i) == null)
                  ActionChip(
                    key: ValueKey(
                      _key('ai-question-chip-${widget.number}-$i'),
                    ),
                    label: Text(q.options[i]),
                    backgroundColor: q.recommended == i
                        ? cs.primaryContainer
                        : null,
                    side: q.recommended == i
                        ? BorderSide(color: cs.primary)
                        : null,
                    onPressed: () => _answer(q.options[i], optionId: _idOf(i)),
                  ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey(_key('ai-question-input-${widget.number}')),
                  controller: _text,
                  decoration: const InputDecoration(
                    hintText: 'Type an answer',
                    isDense: true,
                  ),
                  onSubmitted: (v) => _answer(v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, size: 18),
                onPressed: () => _answer(_text.text),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
