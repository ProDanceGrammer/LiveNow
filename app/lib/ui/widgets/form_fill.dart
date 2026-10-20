import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/form_effects.dart';
import '../../domain/form_service.dart';
import '../../domain/forms.dart';
import '../../domain/growth_rules.dart' show metricLabel;
import '../dialog_stack.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'metric_picker.dart';

/// Fills a form for a set of selected actions, like the Notion form it comes
/// from: a header, one block per question (emoji heading, "(Select as many as
/// you like)", checkboxes with emoji labels) and Submit. It only COLLECTS the
/// answers: [show] returns the parsed [FormEffects] (what to add) or null when
/// cancelled; the caller applies them (one undoable step) or merges them into
/// an action editor.
class FormFillDialog extends ConsumerStatefulWidget {
  const FormFillDialog({
    super.key,
    required this.form,
    required this.actionCount,
    this.actionNames = const [],
  });

  final FormItem form;

  /// How many actions the answers will go to (shown in the header).
  final int actionCount;

  /// Their names, listed in the header's tooltip (the first few).
  final List<String> actionNames;

  static Future<FormEffects?> show(
    BuildContext context, {
    required FormItem form,
    required int actionCount,
    List<String> actionNames = const [],
  }) => showStackedDialog<FormEffects>(
    context: context,
    builder: (_) => FormFillDialog(
      form: form,
      actionCount: actionCount,
      actionNames: actionNames,
    ),
  );

  @override
  ConsumerState<FormFillDialog> createState() => _FormFillDialogState();
}

class _FormFillDialogState extends ConsumerState<FormFillDialog> {
  /// One notifier per question, so a tick rebuilds only its own block (a real
  /// form has ~25 questions and ~110 options).
  final _answers = <String, ValueNotifier<Set<String>>>{};

  /// Bumped on every change: the footer (live summary, Submit) listens to it.
  final _changed = ValueNotifier<int>(0);

  ValueNotifier<Set<String>> _of(String questionId) =>
      _answers.putIfAbsent(questionId, () => ValueNotifier<Set<String>>({}));

  void _set(String questionId, Set<String> next) {
    _of(questionId).value = next;
    _changed.value++;
  }

  void _toggle(String questionId, String id, bool on) {
    final next = {..._of(questionId).value};
    on ? next.add(id) : next.remove(id);
    _set(questionId, next);
  }

  FormEffects _effects() => computeEffects(widget.form.def, {
    for (final e in _answers.entries) e.key: e.value.value,
  });

  @override
  void dispose() {
    for (final n in _answers.values) {
      n.dispose();
    }
    _changed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form.def;
    final questions = form.activeQuestions;
    final phone = usePhoneLayout(context);
    final size = MediaQuery.sizeOf(context);
    final body = Material(
      color: context.glass.fillDialog,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                key: const ValueKey('form-fill-list'),
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? 16 : 28,
                  vertical: 16,
                ),
                itemCount: questions.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _header(context, form);
                  final q = questions[i - 1];
                  return _QuestionBlock(
                    key: ValueKey('form-q-${q.id}'),
                    question: q,
                    answers: _of(q.id),
                    onToggle: (id, on) => _toggle(q.id, id, on),
                    onReplace: (ids) => _set(q.id, ids),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
    if (phone) {
      return Dialog.fullscreen(child: body);
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth(context, 760),
        height: size.height * 0.92,
        child: body,
      ),
    );
  }

  Widget _header(BuildContext context, FormDef form) {
    final theme = Theme.of(context);
    final names = widget.actionNames.take(12).join('\n');
    final more = widget.actionNames.length > 12
        ? '\n… and ${widget.actionNames.length - 12} more'
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            form.display,
            key: const ValueKey('form-fill-title'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (form.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(form.description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 10),
          Tooltip(
            message: names.isEmpty ? '' : '$names$more',
            child: Chip(
              key: const ValueKey('form-fill-actions'),
              avatar: const Icon(Icons.bolt_rounded, size: 18),
              label: Text(
                'Applying to ${widget.actionCount} '
                'action${widget.actionCount == 1 ? '' : 's'}',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: ValueListenableBuilder<int>(
        valueListenable: _changed,
        builder: (context, _, _) {
          final e = _effects();
          final n = widget.actionCount;
          final String line;
          if (!e.isComplete) {
            line = 'Required: ${e.missingRequired.join(', ')}';
          } else if (e.isEmpty) {
            line = 'Nothing ticked yet';
          } else {
            final d = e.metricIds.length;
            line =
                '$d direction${d == 1 ? '' : 's'}'
                '${e.activityName == null ? '' : ' + activity "${e.activityName}"'}'
                ' will be added to $n action${n == 1 ? '' : 's'}';
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  line,
                  key: const ValueKey('form-fill-summary'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: e.isComplete ? null : theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('form-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('form-submit'),
                onPressed: e.isComplete && !e.isEmpty
                    ? () => Navigator.of(context).pop(e)
                    : null,
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One question of the form being filled: only this block rebuilds on a tick.
class _QuestionBlock extends ConsumerWidget {
  const _QuestionBlock({
    super.key,
    required this.question,
    required this.answers,
    required this.onToggle,
    required this.onReplace,
  });

  final FormQuestion question;
  final ValueNotifier<Set<String>> answers;
  final void Function(String id, bool on) onToggle;
  final void Function(Set<String> ids) onReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final q = question;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: q.display),
                if (q.required)
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
            style: emojiLabelStyle.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (q.hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              q.hint,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            '(Select as many as you like)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<Set<String>>(
            valueListenable: answers,
            builder: (context, picked, _) => switch (q.kind) {
              FormQuestionKind.checkboxes => Column(
                children: [
                  for (final o in q.options)
                    CheckboxListTile(
                      key: ValueKey('form-option-${q.id}-${o.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(o.display, style: emojiLabelStyle),
                      value: picked.contains(o.id),
                      onChanged: (v) => onToggle(o.id, v ?? false),
                    ),
                ],
              ),
              FormQuestionKind.directions => _directions(context, ref, picked),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  /// A direction question: any direction, or the pool the builder chose.
  Widget _directions(BuildContext context, WidgetRef ref, Set<String> picked) {
    if (question.metricIds.isEmpty) {
      return MetricPicker(
        key: ValueKey('form-picker-${question.id}'),
        label: '',
        selectedIds: picked,
        onChanged: onReplace,
      );
    }
    final names = {
      for (final m in ref.watch(metricsProvider).value ?? const [])
        m.id: metricLabel(m.name, m.icon),
    };
    return Column(
      children: [
        for (final id in question.metricIds)
          if (names.containsKey(id))
            CheckboxListTile(
              key: ValueKey('form-direction-${question.id}-$id'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(names[id]!, style: emojiLabelStyle),
              value: picked.contains(id),
              onChanged: (v) => onToggle(id, v ?? false),
            ),
      ],
    );
  }
}
