import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_providers.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

/// Numbered questions with quick-reply chips (the recommended one highlighted)
/// and a free-text field. Answering writes into the card through the chat
/// service; the hub notices the answered card and resumes.
class AiQuestionCard extends ConsumerWidget {
  const AiQuestionCard({super.key, required this.message, this.latest = true});

  final AiMessage message;
  final bool latest;

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
  });

  final String messageId;
  final int number;
  final Question question;
  final bool latest;
  final ThemeData theme;

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

  Future<void> _answer(String a) async {
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiChatServiceProvider);
    try {
      await service.answerQuestion(widget.messageId, widget.question.id, a);
      _text.clear();
    } catch (e) {
      showInfoToast(overlay, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final cs = widget.theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.number + 1}. ${q.text}'),
        if (q.answer != null)
          Text(
            'Answer: ${q.answer}',
            style: widget.theme.textTheme.labelMedium,
          )
        else ...[
          if (q.options.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < q.options.length; i++)
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
                    onPressed: () => _answer(q.options[i]),
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
