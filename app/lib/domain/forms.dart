import 'dart:convert';

import '../core/ids.dart';

// Forms (schema v17): a questionnaire the owner fills for a set of selected
// actions. Every ticked answer adds growth directions (and optionally a
// Countable Activity) to them. Pure model + a tolerant JSON codec; the payload
// is stored in `forms.payload` and synced, so an older or newer build must read
// what it can and never crash on what it does not know.

/// The payload version this build writes.
const int kFormPayloadVersion = 1;

/// What a question asks. `people` is reserved (the People database does not
/// exist yet): such a question is kept when saved but neither shown nor applied.
enum FormQuestionKind {
  /// Checkboxes: every ticked option adds its own directions.
  checkboxes,

  /// A direction picker: the chosen directions are added as they are.
  directions,

  /// Reserved for the People database.
  people,

  /// A kind written by a newer build: kept, ignored.
  unknown;

  static FormQuestionKind byName(String name) => FormQuestionKind.values
      .where((k) => k.name == name && k != FormQuestionKind.unknown)
      .firstOrNull ??
      FormQuestionKind.unknown;
}

/// One answer of a checkbox question: what ticking it adds.
class FormOption {
  const FormOption({
    required this.id,
    required this.label,
    this.icon,
    this.metricIds = const [],
    this.activityName,
  });

  /// Stable across edits (a draft, Undo or a later history point at it).
  final String id;
  final String label;

  /// An emoji shown before the label, or null.
  final String? icon;

  /// The growth directions this answer adds (one or several).
  final List<String> metricIds;

  /// A Countable Activity (by NAME: robust across devices) set on actions that
  /// have none yet, or null.
  final String? activityName;

  FormOption copyWith({
    String? label,
    String? icon,
    bool clearIcon = false,
    List<String>? metricIds,
    String? activityName,
    bool clearActivity = false,
  }) => FormOption(
    id: id,
    label: label ?? this.label,
    icon: clearIcon ? null : (icon ?? this.icon),
    metricIds: metricIds ?? this.metricIds,
    activityName: clearActivity ? null : (activityName ?? this.activityName),
  );

  /// `🎓 label`, or the bare label.
  String get display => icon == null || icon!.isEmpty ? label : '$icon $label';

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (icon != null && icon!.isNotEmpty) 'icon': icon,
    if (metricIds.isNotEmpty) 'metrics': metricIds,
    if (activityName != null && activityName!.isNotEmpty)
      'activity': activityName,
  };

  static FormOption? fromJson(Object? j) {
    if (j is! Map) return null;
    final label = j['label'];
    if (label is! String) return null;
    final id = j['id'];
    return FormOption(
      id: id is String && id.isNotEmpty ? id : newId(),
      label: label,
      icon: j['icon'] is String ? j['icon'] as String : null,
      metricIds: _strings(j['metrics']),
      activityName: j['activity'] is String ? j['activity'] as String : null,
    );
  }
}

/// One question of a form.
class FormQuestion {
  const FormQuestion({
    required this.id,
    required this.title,
    this.kindName = 'checkboxes',
    this.icon,
    this.hint = '',
    this.required = false,
    this.options = const [],
    this.metricIds = const [],
  });

  final String id;
  final String title;

  /// The kind as written (kept verbatim, so a kind this build does not know
  /// survives a save).
  final String kindName;
  final String? icon;

  /// An optional second line under the title.
  final String hint;
  final bool required;

  /// The checkboxes (kind `checkboxes`).
  final List<FormOption> options;

  /// For a `directions` question: the directions to choose from (empty = any).
  final List<String> metricIds;

  FormQuestionKind get kind => FormQuestionKind.byName(kindName);

  /// Whether this build shows and applies the question.
  bool get isActive =>
      kind == FormQuestionKind.checkboxes ||
      kind == FormQuestionKind.directions;

  FormQuestion copyWith({
    String? title,
    String? kindName,
    String? icon,
    bool clearIcon = false,
    String? hint,
    bool? required,
    List<FormOption>? options,
    List<String>? metricIds,
  }) => FormQuestion(
    id: id,
    title: title ?? this.title,
    kindName: kindName ?? this.kindName,
    icon: clearIcon ? null : (icon ?? this.icon),
    hint: hint ?? this.hint,
    required: required ?? this.required,
    options: options ?? this.options,
    metricIds: metricIds ?? this.metricIds,
  );

  String get display => icon == null || icon!.isEmpty ? title : '$icon $title';

  /// A copy with a NEW id for the question and for every answer (ids must stay
  /// unique: a combination points at an answer by its ids), the same text,
  /// directions and activities. Combinations that use the original's answers
  /// are not copied: they keep pointing at the original.
  FormQuestion duplicated() => FormQuestion(
    id: newId(),
    title: title,
    kindName: kindName,
    icon: icon,
    hint: hint,
    required: required,
    options: [
      for (final o in options)
        FormOption(
          id: newId(),
          label: o.label,
          icon: o.icon,
          metricIds: [...o.metricIds],
          activityName: o.activityName,
        ),
    ],
    metricIds: [...metricIds],
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kindName,
    if (icon != null && icon!.isNotEmpty) 'icon': icon,
    if (hint.isNotEmpty) 'hint': hint,
    if (required) 'required': true,
    if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
    if (metricIds.isNotEmpty) 'metrics': metricIds,
  };

  static FormQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    final title = j['title'];
    if (title is! String) return null;
    final id = j['id'];
    final opts = j['options'];
    return FormQuestion(
      id: id is String && id.isNotEmpty ? id : newId(),
      title: title,
      kindName: j['kind'] is String ? j['kind'] as String : 'checkboxes',
      icon: j['icon'] is String ? j['icon'] as String : null,
      hint: j['hint'] is String ? j['hint'] as String : '',
      required: j['required'] == true,
      options: [
        if (opts is List)
          for (final o in opts)
            if (FormOption.fromJson(o) case final FormOption option) option,
      ],
      metricIds: _strings(j['metrics']),
    );
  }
}

/// One answer picked by a [FormCombo]: an option of a question. The pair is
/// needed because option ids are only unique inside their question.
class FormPick {
  const FormPick(this.questionId, this.optionId);

  final String questionId;
  final String optionId;

  @override
  bool operator ==(Object other) =>
      other is FormPick &&
      other.questionId == questionId &&
      other.optionId == optionId;

  @override
  int get hashCode => Object.hash(questionId, optionId);
}

/// A combination rule: when EVERY answer in [picks] is ticked (in one question
/// or across several), [metricIds] are added ON TOP of what the answers add on
/// their own.
class FormCombo {
  const FormCombo({
    required this.id,
    this.picks = const [],
    this.metricIds = const [],
    this.activityName,
  });

  final String id;
  final List<FormPick> picks;
  final List<String> metricIds;

  /// A Countable Activity (by NAME, like an answer's) set on actions that have
  /// none yet when the rule fires. It WINS over the activities of the single
  /// answers: the rule is the more specific statement.
  final String? activityName;

  FormCombo copyWith({
    List<FormPick>? picks,
    List<String>? metricIds,
    String? activityName,
    bool clearActivity = false,
  }) => FormCombo(
    id: id,
    picks: picks ?? this.picks,
    metricIds: metricIds ?? this.metricIds,
    activityName: clearActivity ? null : (activityName ?? this.activityName),
  );

  /// The same rule under a new id (the answers and directions are shared by
  /// value, so the copy starts identical and is then edited).
  FormCombo duplicated() => FormCombo(
    id: newId(),
    picks: [...picks],
    metricIds: [...metricIds],
    activityName: activityName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'picks': [
      for (final p in picks) {'q': p.questionId, 'o': p.optionId},
    ],
    if (metricIds.isNotEmpty) 'metrics': metricIds,
    if (activityName != null && activityName!.trim().isNotEmpty)
      'activity': activityName,
  };

  static FormCombo? fromJson(Object? j) {
    if (j is! Map) return null;
    final raw = j['picks'];
    final picks = [
      if (raw is List)
        for (final p in raw)
          if (p is Map && p['q'] is String && p['o'] is String)
            FormPick(p['q'] as String, p['o'] as String),
    ];
    if (picks.isEmpty) return null;
    final id = j['id'];
    return FormCombo(
      id: id is String && id.isNotEmpty ? id : newId(),
      picks: picks,
      metricIds: _strings(j['metrics']),
      activityName: j['activity'] is String && (j['activity'] as String).trim().isNotEmpty
          ? j['activity'] as String
          : null,
    );
  }
}

/// A whole form.
class FormDef {
  const FormDef({
    required this.name,
    this.description = '',
    this.icon,
    this.questions = const [],
    this.combos = const [],
  });

  final String name;
  final String description;
  final String? icon;
  final List<FormQuestion> questions;

  /// Combination rules (see [FormCombo]); empty for most forms.
  final List<FormCombo> combos;

  FormDef copyWith({
    String? name,
    String? description,
    String? icon,
    bool clearIcon = false,
    List<FormQuestion>? questions,
    List<FormCombo>? combos,
  }) => FormDef(
    name: name ?? this.name,
    description: description ?? this.description,
    icon: clearIcon ? null : (icon ?? this.icon),
    questions: questions ?? this.questions,
    combos: combos ?? this.combos,
  );

  /// The same form without rules that point at an answer or question that is
  /// gone, and without rules left with fewer than two answers.
  FormDef withoutDeadCombos() {
    final live = <FormPick>{
      for (final q in questions)
        for (final o in q.options) FormPick(q.id, o.id),
    };
    return copyWith(
      combos: [
        for (final c in combos)
          if (c.picks.every(live.contains) && c.picks.length >= 2) c,
      ],
    );
  }

  String get display => icon == null || icon!.isEmpty ? name : '$icon $name';

  /// The questions this build shows and applies.
  List<FormQuestion> get activeQuestions => [
    for (final q in questions)
      if (q.isActive) q,
  ];

  int get optionCount =>
      questions.fold(0, (sum, q) => sum + q.options.length);
}

/// The JSON written to `forms.payload` (the name has its own column).
String encodeFormPayload(FormDef f) => jsonEncode({
  'v': kFormPayloadVersion,
  if (f.description.isNotEmpty) 'description': f.description,
  if (f.icon != null && f.icon!.isNotEmpty) 'icon': f.icon,
  'questions': [for (final q in f.questions) q.toJson()],
  if (f.combos.isNotEmpty) 'combos': [for (final c in f.combos) c.toJson()],
});

/// Reads a payload; a damaged one gives an empty form instead of throwing.
FormDef decodeFormPayload(String name, String payload) {
  Object? j;
  try {
    j = jsonDecode(payload);
  } on Object {
    j = null;
  }
  if (j is! Map) return FormDef(name: name);
  final qs = j['questions'];
  final cs = j['combos'];
  return FormDef(
    name: name,
    description: j['description'] is String ? j['description'] as String : '',
    icon: j['icon'] is String ? j['icon'] as String : null,
    questions: [
      if (qs is List)
        for (final q in qs)
          if (FormQuestion.fromJson(q) case final FormQuestion question)
            question,
    ],
    combos: [
      if (cs is List)
        for (final c in cs)
          if (FormCombo.fromJson(c) case final FormCombo combo) combo,
    ],
  );
}

List<String> _strings(Object? v) => [
  if (v is List)
    for (final x in v)
      if (x is String) x,
];
