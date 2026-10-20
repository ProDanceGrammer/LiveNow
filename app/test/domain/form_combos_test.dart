import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/form_effects.dart';
import 'package:livenow/domain/forms.dart';

FormOption _opt(String id, String label, {List<String> metrics = const []}) =>
    FormOption(id: id, label: label, metricIds: metrics);

/// Combination rules: when EVERY answer of a rule is ticked, its directions come
/// on top of what the answers add by themselves.
void main() {
  FormDef form({List<FormCombo> combos = const [], String q2Kind = 'checkboxes'}) =>
      FormDef(
        name: 'F',
        questions: [
          FormQuestion(
            id: 'q1',
            title: 'What',
            options: [
              _opt('gym', 'Gym', metrics: ['m-sport']),
              _opt('read', 'Read', metrics: ['m-learn']),
            ],
          ),
          FormQuestion(
            id: 'q2',
            title: 'When',
            kindName: q2Kind,
            options: [
              _opt('eve', 'Evening', metrics: ['m-night']),
              // The same option id as in q1: only the pair is unique.
              _opt('gym', 'Gym again'),
            ],
          ),
        ],
        combos: combos,
      );

  const gymEvening = FormCombo(
    id: 'c1',
    picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
    metricIds: ['m-routine'],
  );

  group('effects', () {
    test('all answers ticked (across two questions) add the rule on top', () {
      final e = computeEffects(form(combos: [gymEvening]), {
        'q1': {'gym'},
        'q2': {'eve'},
      });
      expect(e.metricIds, ['m-sport', 'm-night', 'm-routine']);
    });

    test('a rule inside ONE question works too', () {
      final f = form(
        combos: const [
          FormCombo(
            id: 'c',
            picks: [FormPick('q1', 'gym'), FormPick('q1', 'read')],
            metricIds: ['m-both'],
          ),
        ],
      );
      expect(
        computeEffects(f, {'q1': {'gym', 'read'}}).metricIds,
        ['m-sport', 'm-learn', 'm-both'],
      );
    });

    test('one answer missing: the rule does not fire, the answers still add', () {
      final f = form(combos: [gymEvening]);
      expect(computeEffects(f, {'q1': {'gym'}}).metricIds, ['m-sport']);
      expect(computeEffects(f, {'q2': {'eve'}}).metricIds, ['m-night']);
    });

    test('the same option id under another question is another answer', () {
      final e = computeEffects(form(combos: [gymEvening]), {
        'q1': {'read'},
        'q2': {'eve', 'gym'}, // q2's "gym" is NOT q1's "gym"
      });
      expect(e.metricIds, ['m-learn', 'm-night']);
    });

    test('a direction already added is not repeated', () {
      final f = form(
        combos: const [
          FormCombo(
            id: 'c',
            picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
            metricIds: ['m-sport', 'm-new'],
          ),
        ],
      );
      expect(
        computeEffects(f, {'q1': {'gym'}, 'q2': {'eve'}}).metricIds,
        ['m-sport', 'm-night', 'm-new'],
      );
    });

    test('a rule with a vanished answer, or a single pick, never fires', () {
      final f = form(
        combos: const [
          FormCombo(
            id: 'gone',
            picks: [FormPick('q1', 'gym'), FormPick('q1', 'deleted')],
            metricIds: ['x'],
          ),
          FormCombo(id: 'one', picks: [FormPick('q1', 'gym')], metricIds: ['y']),
        ],
      );
      expect(
        computeEffects(f, {'q1': {'gym', 'deleted'}}).metricIds,
        ['m-sport'],
      );
    });

    test('a rule on a question this build does not apply never fires', () {
      final f = form(combos: [gymEvening], q2Kind: 'people');
      expect(
        computeEffects(f, {'q1': {'gym'}, 'q2': {'eve'}}).metricIds,
        ['m-sport'],
      );
    });
  });

  group('payload', () {
    test('rules survive a round trip, in order', () {
      final f = form(combos: [gymEvening]);
      final back = decodeFormPayload('F', encodeFormPayload(f));
      expect(back.combos, hasLength(1));
      expect(back.combos.single.id, 'c1');
      expect(back.combos.single.picks, gymEvening.picks);
      expect(back.combos.single.metricIds, ['m-routine']);
    });

    test('a form without rules writes no combos key and reads as none', () {
      final payload = encodeFormPayload(form());
      expect(jsonDecode(payload), isNot(contains('combos')));
      expect(decodeFormPayload('F', payload).combos, isEmpty);
    });

    test('malformed rules are dropped without hurting the questions', () {
      final payload = jsonEncode({
        'questions': [
          {'id': 'q', 'title': 'T'},
        ],
        'combos': [
          'junk',
          {'id': 'x', 'picks': []},
          {
            'id': 'bad',
            'picks': [
              {'q': 1, 'o': 'a'},
            ],
          },
          {
            'id': 'ok',
            'picks': [
              {'q': 'q', 'o': 'a'},
              {'q': 'q', 'o': 'b'},
            ],
          },
        ],
      });
      final f = decodeFormPayload('F', payload);
      expect(f.questions, hasLength(1));
      expect(f.combos.map((c) => c.id), ['ok']);
    });

    test('combos is not a list: ignored', () {
      final f = decodeFormPayload('F', jsonEncode({'combos': 5}));
      expect(f.combos, isEmpty);
    });
  });

  test('withoutDeadCombos drops rules with a missing answer or under 2 picks', () {
    final f = form(
      combos: const [
        FormCombo(
          id: 'live',
          picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
        ),
        FormCombo(
          id: 'dead',
          picks: [FormPick('q1', 'gym'), FormPick('q9', 'eve')],
        ),
        FormCombo(id: 'short', picks: [FormPick('q1', 'gym')]),
        FormCombo(id: 'empty'),
      ],
    );
    expect(f.withoutDeadCombos().combos.map((c) => c.id), ['live']);
  });

  group('a combination can set a Countable Activity', () {
    FormDef withActivities(List<FormCombo> combos) => FormDef(
      name: 'F',
      questions: [
        FormQuestion(
          id: 'q1',
          title: 'What',
          options: [
            FormOption(id: 'gym', label: 'Gym', activityName: 'Sport'),
            FormOption(id: 'read', label: 'Read'),
          ],
        ),
        FormQuestion(
          id: 'q2',
          title: 'When',
          options: [FormOption(id: 'eve', label: 'Evening')],
        ),
      ],
      combos: combos,
    );

    const rule = FormCombo(
      id: 'c',
      picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
      activityName: 'Night training',
    );

    test('it wins over the activity of a single answer, once it fires', () {
      final f = withActivities([rule]);
      expect(
        computeEffects(f, {'q1': {'gym'}, 'q2': {'eve'}}).activityName,
        'Night training',
      );
      // Not fired: the answer's own activity stays.
      expect(computeEffects(f, {'q1': {'gym'}}).activityName, 'Sport');
    });

    test('a rule without an activity leaves the answers\' activity alone', () {
      final f = withActivities(const [
        FormCombo(id: 'c', picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')]),
      ]);
      expect(
        computeEffects(f, {'q1': {'gym'}, 'q2': {'eve'}}).activityName,
        'Sport',
      );
    });

    test('the first firing rule that names one decides; blank names count as none', () {
      final f = withActivities(const [
        FormCombo(
          id: 'blank',
          picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
          activityName: '   ',
        ),
        FormCombo(
          id: 'first',
          picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
          activityName: 'First',
        ),
        FormCombo(
          id: 'second',
          picks: [FormPick('q1', 'gym'), FormPick('q2', 'eve')],
          activityName: 'Second',
        ),
      ]);
      expect(
        computeEffects(f, {'q1': {'gym'}, 'q2': {'eve'}}).activityName,
        'First',
      );
    });

    test('a rule with only an activity (no directions) still gives effects', () {
      final f = withActivities([rule]);
      final e = computeEffects(f, {'q1': {'read', 'gym'}, 'q2': {'eve'}});
      expect(e.isEmpty, isFalse);
      expect(e.activityName, 'Night training');
    });

    test('the activity survives the payload round trip and a duplicate; blank is dropped', () {
      final f = withActivities([rule]);
      final back = decodeFormPayload('F', encodeFormPayload(f));
      expect(back.combos.single.activityName, 'Night training');
      expect(rule.duplicated().activityName, 'Night training');
      expect(rule.copyWith(clearActivity: true).activityName, isNull);
      expect(
        jsonEncode(const FormCombo(id: 'x', picks: [FormPick('a', 'b')], activityName: ' ').toJson()),
        isNot(contains('activity')),
      );
      expect(
        decodeFormPayload(
          'F',
          jsonEncode({
            'combos': [
              {
                'id': 'c',
                'picks': [
                  {'q': 'a', 'o': 'b'},
                ],
                'activity': '  ',
              },
            ],
          }),
        ).combos.single.activityName,
        isNull,
      );
    });
  });
}
