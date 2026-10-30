import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/model_prompts.dart';

void main() {
  const cands = [
    CandidateCategory(id: 'a', name: 'Молоко'),
    CandidateCategory(id: 'b', name: 'Сир', hint: 'kg'),
  ];

  test('candidate choice: key mapping, none, garbage, clamped confidence', () {
    expect(parseCandidateChoice({'choice': 'c1', 'confidence': 0.9}, cands).category?.id, 'a');
    expect(parseCandidateChoice({'choice': 'none', 'confidence': 1}, cands).category, isNull);
    expect(parseCandidateChoice({'choice': 'c9'}, cands).category, isNull);
    expect(parseCandidateChoice({'choice': 'C2', 'confidence': 7}, cands).confidence, 1.0);
    expect(parseCandidateChoice({'choice': 'c2', 'confidence': '0.5'}, cands).confidence, 0.5);
  });

  test('candidate prompt lists every option and the item', () {
    final p = candidateChoicePrompt(itemText: 'SUT 1L', candidates: cands, merchant: 'BIM');
    expect(p.user, allOf(contains('SUT 1L'), contains('c1: Молоко'), contains('c2: Сир (kg)'), contains('BIM')));
    expect(p.system, contains('Ukrainian'));
  });

  test('written message: text or null', () {
    expect(parseWrittenMessage({'text': '  Привіт '}), 'Привіт');
    expect(parseWrittenMessage({'text': ''}), isNull);
    expect(parseWrittenMessage({}), isNull);
    final p = writeMessagePrompt(kind: WrittenMessageKind.question, facts: 'weight of line 3 unknown');
    expect(p.user, contains('weight of line 3 unknown'));
  });

  test('correction intent: valid, out-of-range line, incomplete, unknown', () {
    final ok = parseCorrectionIntent({
      'intent': 'set_category',
      'line': 2,
      'text': 'Снеки',
      'number': null,
      'unit': null,
    }, lineCount: 3);
    expect(ok.kind, CorrectionKind.setCategory);
    expect(ok.line, 2);
    expect(ok.text, 'Снеки');

    final bad = parseCorrectionIntent({'intent': 'set_quantity', 'line': 9, 'number': '2,5', 'unit': 'kg'}, lineCount: 3);
    expect(bad.kind, CorrectionKind.setQuantity);
    expect(bad.line, isNull);
    expect(bad.number, 2.5);

    expect(parseCorrectionIntent({'intent': 'delete_line', 'line': null}).kind, CorrectionKind.unknown);
    expect(parseCorrectionIntent({'intent': 'set_price'}).kind, CorrectionKind.unknown);
    expect(parseCorrectionIntent({'intent': 'fly'}).kind, CorrectionKind.unknown);
    expect(parseCorrectionIntent({'intent': 'confirm'}).kind, CorrectionKind.confirm);
  });

  test('correction schema enum matches the parser', () {
    final p = correctionIntentPrompt(userText: 'ні, це снеки', lines: ['MILKA 1,5', 'SUT']);
    final intents = p.schema['properties']['intent']['enum'] as List;
    expect(intents.length, CorrectionKind.values.length);
    expect(p.user, contains('1. MILKA 1,5'));
  });
}
