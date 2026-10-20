import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/forms.dart';

/// Duplicating a question or a combination: same content, NEW ids (a
/// combination points at an answer by its ids, so a shared id would be a bug).
void main() {
  const q = FormQuestion(
    id: 'q1',
    title: 'What',
    icon: '📚',
    hint: 'pick',
    required: true,
    options: [
      FormOption(id: 'o1', label: 'Study', icon: '🎓', metricIds: ['m1', 'm2'], activityName: 'Learn'),
      FormOption(id: 'o2', label: 'Rest'),
    ],
    metricIds: ['m9'],
  );

  test('a duplicated question keeps its content and gets new ids everywhere', () {
    final d = q.duplicated();
    expect(d.id, isNot(q.id));
    expect(d.title, 'What');
    expect(d.icon, '📚');
    expect(d.hint, 'pick');
    expect(d.required, isTrue);
    expect(d.kindName, q.kindName);
    expect(d.metricIds, ['m9']);
    expect(d.options.map((o) => o.label), ['Study', 'Rest']);
    expect(d.options.first.icon, '🎓');
    expect(d.options.first.metricIds, ['m1', 'm2']);
    expect(d.options.first.activityName, 'Learn');
    final all = {q.id, ...q.options.map((o) => o.id), d.id, ...d.options.map((o) => o.id)};
    expect(all, hasLength(6)); // nothing shared
  });

  test('editing the copy does not touch the original (lists are not shared)', () {
    final d = q.duplicated();
    expect(identical(d.options.first.metricIds, q.options.first.metricIds), isFalse);
    expect(identical(d.metricIds, q.metricIds), isFalse);
  });

  test('a duplicated combination is the same rule under a new id', () {
    const c = FormCombo(
      id: 'c1',
      picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
      metricIds: ['m5'],
    );
    final d = c.duplicated();
    expect(d.id, isNot(c.id));
    expect(d.picks, c.picks);
    expect(d.metricIds, ['m5']);
    expect(identical(d.picks, c.picks), isFalse);
  });

  test('a copied question is a fresh question for the rules: old rules do not fire on it', () {
    final form = FormDef(
      name: 'F',
      questions: [q, q.duplicated()],
      combos: const [
        FormCombo(
          id: 'c',
          picks: [FormPick('q1', 'o1'), FormPick('q1', 'o2')],
          metricIds: ['m5'],
        ),
      ],
    );
    // The rule still lives on the original; the copy has other ids.
    expect(form.withoutDeadCombos().combos, hasLength(1));
    final copy = form.questions[1];
    expect(
      form.combos.single.picks.any((p) => p.questionId == copy.id),
      isFalse,
    );
  });
}
