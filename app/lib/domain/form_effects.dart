import 'forms.dart';

/// What filling a form does to the selected actions.
class FormEffects {
  const FormEffects({
    this.metricIds = const [],
    this.activityName,
    this.missingRequired = const [],
  });

  /// The directions to ADD, in form order, without repeats.
  final List<String> metricIds;

  /// The Countable Activity to set on actions that have none: the first ticked
  /// option's (in form order) that names one.
  final String? activityName;

  /// Titles of required questions that have no answer.
  final List<String> missingRequired;

  bool get isEmpty => metricIds.isEmpty && activityName == null;
  bool get isComplete => missingRequired.isEmpty;
}

/// The parser: turns the [answers] of [form] into what to add. [answers] maps a
/// question id to the ticked option ids (a `checkboxes` question) or to the
/// chosen direction ids (a `directions` question). Unknown ids, and questions of
/// a kind this build does not apply (people, unknown), are ignored. An option is
/// identified by its id inside its question, never by its text, so the same
/// label under two questions stays two different answers.
FormEffects computeEffects(FormDef form, Map<String, Set<String>> answers) {
  final metrics = <String>[];
  final seen = <String>{};
  String? activity;
  final missing = <String>[];

  void add(Iterable<String> ids) {
    for (final id in ids) {
      if (seen.add(id)) metrics.add(id);
    }
  }

  for (final q in form.activeQuestions) {
    final picked = answers[q.id] ?? const <String>{};
    var answered = false;
    switch (q.kind) {
      case FormQuestionKind.checkboxes:
        for (final o in q.options) {
          if (!picked.contains(o.id)) continue;
          answered = true;
          add(o.metricIds);
          final a = o.activityName?.trim();
          if (activity == null && a != null && a.isNotEmpty) activity = a;
        }
      case FormQuestionKind.directions:
        final pool = q.metricIds.toSet();
        final chosen = [
          for (final id in picked)
            if (pool.isEmpty || pool.contains(id)) id,
        ];
        answered = chosen.isNotEmpty;
        add(chosen);
      case FormQuestionKind.people:
      case FormQuestionKind.unknown:
        break;
    }
    if (q.required && !answered) missing.add(q.title);
  }

  // Combination rules: when EVERY answer of a rule is ticked, its directions
  // come on top. A rule pointing at an answer that no longer exists (or at a
  // question this build does not apply) never fires.
  final ticked = <FormPick>{
    for (final q in form.activeQuestions)
      if (q.kind == FormQuestionKind.checkboxes)
        for (final o in q.options)
          if ((answers[q.id] ?? const <String>{}).contains(o.id))
            FormPick(q.id, o.id),
  };
  String? comboActivity;
  for (final c in form.combos) {
    if (c.picks.length >= 2 && c.picks.every(ticked.contains)) {
      add(c.metricIds);
      // The first firing rule that names an activity decides it, and it wins
      // over the single answers' activities (a rule is the more specific
      // statement).
      final a = c.activityName?.trim();
      if (comboActivity == null && a != null && a.isNotEmpty) comboActivity = a;
    }
  }
  return FormEffects(
    metricIds: metrics,
    activityName: comboActivity ?? activity,
    missingRequired: missing,
  );
}
