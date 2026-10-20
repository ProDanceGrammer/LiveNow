import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/form_effects.dart';
import 'package:livenow/domain/form_outline.dart';
import 'package:livenow/domain/forms.dart';

FormOption _opt(
  String id,
  String label, {
  List<String> metrics = const [],
  String? activity,
}) => FormOption(id: id, label: label, metricIds: metrics, activityName: activity);

void main() {
  group('payload codec', () => _codec());
  group('outline parser', () => _outline());
  group('computeEffects', () => _effects());
}

void _codec() {
  test('a form survives a round trip', () {
    final f = FormDef(
      name: 'Goals',
      description: 'Which goals does a task serve',
      icon: '🎯',
      questions: [
        FormQuestion(
          id: 'q1',
          title: 'Я вивчаю нове і воно...',
          icon: '📚',
          hint: '(pick any)',
          required: true,
          options: [
            FormOption(
              id: 'o1',
              label: 'відповідає моєму факу',
              icon: '🎓',
              metricIds: const ['m1', 'm2'],
              activityName: 'Study',
            ),
          ],
        ),
        const FormQuestion(
          id: 'q2',
          title: 'Love language',
          kindName: 'directions',
          metricIds: ['m9'],
        ),
      ],
    );
    final back = decodeFormPayload('Goals', encodeFormPayload(f));
    expect(back.name, 'Goals');
    expect(back.description, 'Which goals does a task serve');
    expect(back.icon, '🎯');
    expect(back.questions, hasLength(2));
    final q = back.questions.first;
    expect((q.id, q.title, q.icon, q.hint, q.required), ('q1', 'Я вивчаю нове і воно...', '📚', '(pick any)', true));
    final o = q.options.single;
    expect((o.id, o.label, o.icon, o.activityName), ('o1', 'відповідає моєму факу', '🎓', 'Study'));
    expect(o.metricIds, ['m1', 'm2']);
    expect(back.questions.last.kind, FormQuestionKind.directions);
    expect(back.questions.last.metricIds, ['m9']);
    expect(back.optionCount, 1);
  });

  test('a damaged or empty payload gives an empty form, never a crash', () {
    for (final bad in ['', 'not json', '[]', '{"questions": 5}', 'null']) {
      final f = decodeFormPayload('X', bad);
      expect(f.name, 'X');
      expect(f.questions, isEmpty);
    }
  });

  test('missing keys get defaults; entries without a title or label are dropped', () {
    final f = decodeFormPayload(
      'X',
      jsonEncode({
        'questions': [
          {'title': 'Only a title'},
          {'nope': 1},
          'text',
          {
            'title': 'With options',
            'options': [
              {'label': 'ok'},
              {'id': 'x'},
              5,
            ],
          },
        ],
      }),
    );
    expect(f.questions.map((q) => q.title), ['Only a title', 'With options']);
    expect(f.questions.first.kind, FormQuestionKind.checkboxes);
    expect(f.questions.first.id, isNotEmpty); // an id is made up
    expect(f.questions.last.options.map((o) => o.label), ['ok']);
  });

  test('a kind from a newer build is kept as written and not applied', () {
    final json = encodeFormPayload(
      const FormDef(
        name: 'X',
        questions: [
          FormQuestion(id: 'p', title: 'People', kindName: 'people'),
          FormQuestion(id: 'f', title: 'Future', kindName: 'sliders'),
          FormQuestion(id: 'c', title: 'Checks'),
        ],
      ),
    );
    final f = decodeFormPayload('X', json);
    expect(f.questions.map((q) => q.kind), [
      FormQuestionKind.people,
      FormQuestionKind.unknown,
      FormQuestionKind.checkboxes,
    ]);
    expect(f.questions[1].kindName, 'sliders'); // survives a save
    expect(f.activeQuestions.map((q) => q.id), ['c']);
    expect(decodeFormPayload('X', encodeFormPayload(f)).questions[1].kindName, 'sliders');
  });
}

void _outline() {
  test('headings become questions, bullets become options', () {
    final qs = parseOutline('''
📚 Я вивчаю нове і воно...
- 🎓 відповідає моєму факу
- 💻 додає практики у програмуванні

🔁 Я повторив щось...
- за сьогодні
- за тиждень
''');
    expect(qs, hasLength(2));
    expect((qs[0].icon, qs[0].title), ('📚', 'Я вивчаю нове і воно...'));
    expect(qs[0].options.map((o) => (o.icon, o.label)), [
      ('🎓', 'відповідає моєму факу'),
      ('💻', 'додає практики у програмуванні'),
    ]);
    expect((qs[1].icon, qs[1].title), ('🔁', 'Я повторив щось...'));
    expect(qs[1].options.map((o) => (o.icon, o.label)), [
      (null, 'за сьогодні'),
      (null, 'за тиждень'),
    ]);
  });

  test('every bullet style and indented lines count as options', () {
    final qs = parseOutline('Q\n* a\n• b\n☐ c\n[ ] d\n[x] e\n1. f\n2) g\n   h');
    expect(qs.single.options.map((o) => o.label), ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
  });

  test('a line in parentheses under a question is its hint', () {
    final qs = parseOutline('Q one\n(Select as many as you like)\n- a');
    expect(qs.single.hint, 'Select as many as you like');
    expect(qs.single.options.single.label, 'a');
  });

  test('windows line endings, blank lines and stray spaces are fine', () {
    final qs = parseOutline('\r\n  Q  \r\n\r\n -  a  \r\n\r\n\r\nQ2\r\n- b\r\n');
    expect(qs.map((q) => q.title), ['Q', 'Q2']);
    expect(qs.first.options.single.label, 'a');
  });

  test('options before any heading go to a question called Question', () {
    final qs = parseOutline('- a\n- b');
    expect(qs.single.title, 'Question');
    expect(qs.single.options, hasLength(2));
  });

  test('a flag or several emoji split off whole; # and digits stay in the text', () {
    final (icon, rest) = splitLeadingIcon('🇺🇦 Український контекст');
    expect(icon, '🇺🇦');
    expect(rest, 'Український контекст');
    expect(splitLeadingIcon('#tag stays'), (null, '#tag stays'));
    expect(splitLeadingIcon('3 things'), (null, '3 things'));
    expect(splitLeadingIcon('💙💛 Українського контексту').$1, '💙💛');
    expect(parseOutline(''), isEmpty);
    expect(parseOutline('   \n\n'), isEmpty);
  });

  test('parseOptionLines makes one option per line, dropping bullets and numbers', () {
    final o = parseOptionLines('- 🎓 matches\r\n\n2) practice\n  • 🇺🇦 context\n   \n');
    expect(o.map((x) => (x.icon, x.label)), [
      ('🎓', 'matches'),
      (null, 'practice'),
      ('🇺🇦', 'context'),
    ]);
    expect(parseOptionLines('  \n\n'), isEmpty);
  });

  test('every generated id is unique', () {
    final qs = parseOutline('A\n- x\n- y\nB\n- x\n- y');
    final ids = [
      for (final q in qs) ...[q.id, for (final o in q.options) o.id],
    ];
    expect(ids.toSet(), hasLength(ids.length));
  });
}

void _effects() {
  final form = FormDef(
    name: 'F',
    questions: [
      FormQuestion(
        id: 'q1',
        title: 'Learn',
        required: true,
        options: [
          _opt('a', 'matches my field', metrics: ['m1', 'm2'], activity: 'Study'),
          _opt('b', 'practice', metrics: ['m2', 'm3']),
        ],
      ),
      // The SAME label under another question is another answer.
      FormQuestion(
        id: 'q2',
        title: 'Health',
        options: [
          _opt('a', 'matches my field', metrics: ['m9'], activity: 'Sport'),
          _opt('c', 'rest', metrics: ['m4']),
        ],
      ),
      const FormQuestion(
        id: 'q3',
        title: 'Pick',
        kindName: 'directions',
        metricIds: ['m5', 'm6'],
      ),
      const FormQuestion(id: 'q4', title: 'People', kindName: 'people', required: true),
    ],
  );

  test('every ticked option adds its directions, in form order, without repeats', () {
    final e = computeEffects(form, {
      'q1': {'a', 'b'},
      'q2': {'c'},
    });
    expect(e.metricIds, ['m1', 'm2', 'm3', 'm4']); // m2 only once
    expect(e.isComplete, isTrue);
  });

  test('one option may add several directions, and nothing ticked adds nothing', () {
    expect(computeEffects(form, {'q1': {'a'}}).metricIds, ['m1', 'm2']);
    final none = computeEffects(form, const {});
    expect(none.metricIds, isEmpty);
    expect(none.isEmpty, isTrue);
  });

  test('the same option id in two questions are two different answers', () {
    expect(computeEffects(form, {'q2': {'a'}}).metricIds, ['m9']);
    expect(computeEffects(form, {'q1': {'a'}}).metricIds, ['m1', 'm2']);
  });

  test('the first ticked option with an activity decides it', () {
    expect(computeEffects(form, {'q1': {'a'}, 'q2': {'a'}}).activityName, 'Study');
    expect(computeEffects(form, {'q2': {'a'}}).activityName, 'Sport');
    expect(computeEffects(form, {'q1': {'b'}}).activityName, isNull);
  });

  test('a direction picker adds the chosen ones, limited to its pool', () {
    final e = computeEffects(form, {'q3': {'m5', 'zzz'}});
    expect(e.metricIds, ['m5']); // zzz is not in the pool
    expect(
      computeEffects(
        const FormDef(
          name: 'F',
          questions: [FormQuestion(id: 'any', title: 'Any', kindName: 'directions')],
        ),
        {'any': {'x', 'y'}},
      ).metricIds.toSet(),
      {'x', 'y'},
    );
  });

  test('a required question without an answer is reported', () {
    final e = computeEffects(form, {'q2': {'c'}});
    expect(e.missingRequired, ['Learn']);
    expect(e.isComplete, isFalse);
    expect(computeEffects(form, {'q1': {'b'}}).missingRequired, isEmpty);
  });

  test('unknown ids and people / unknown questions are ignored (even when required)', () {
    final e = computeEffects(form, {
      'q1': {'nope', 'b'},
      'q4': {'whatever'},
    });
    expect(e.metricIds, ['m2', 'm3']);
    expect(e.missingRequired, isEmpty); // the people question is not asked
  });
}
