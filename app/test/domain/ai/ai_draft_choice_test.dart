import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/ai_draft.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';

void main() {
  group('DraftChoice', () {
    test('same-named categories read differently through their group', () {
      const a = DraftChoice('1', 'Сир', parentName: 'Їжа');
      const b = DraftChoice('2', 'Сир', parentName: 'Побут');
      expect(a.label, 'Їжа › Сир');
      expect(b.label, 'Побут › Сир');
      expect(a.label, isNot(b.label));
      expect(const DraftChoice('3', 'Сир').label, 'Сир', reason: 'no group: the bare name');
    });

    test('JSON keeps group, price and unit; an old card without them still loads', () {
      const c = DraftChoice('1', 'Сир', parentName: 'Їжа', price: 450, unit: 'kilogram');
      final back = DraftChoice.fromJson(c.toJson());
      expect((back.parentName, back.price, back.unit), ('Їжа', 450.0, 'kilogram'));
      final old = DraftChoice.fromJson({'id': '9', 'name': 'Хліб'});
      expect(old.parentName, isNull);
      expect(old.label, 'Хліб');
      expect(old.toJson().keys, ['id', 'name'], reason: 'nothing extra for an old reader');
    });
  });

  group('Question', () {
    test('option ids and the answer id survive JSON, and stay optional', () {
      const q = Question(
        id: 'cat:2',
        text: '?',
        options: ['Їжа › Сир', 'Створити «X» у «Їжа»'],
        optionIds: ['c1', 'create:g1'],
        answer: 'Їжа › Сир',
        answerId: 'c1',
      );
      final back = Question.fromJson(q.toJson());
      expect(back.optionIds, ['c1', 'create:g1']);
      expect(back.answerId, 'c1');
      final plain = Question.fromJson(
        const Question(id: 'w', text: '?', options: ['1 kg']).toJson(),
      );
      expect(plain.optionIds, isEmpty);
      expect(plain.answerId, isNull);
      expect(
        const Question(id: 'w', text: '?').toJson().containsKey('option_ids'),
        isFalse,
        reason: 'an older phone build never sees the new keys on plain questions',
      );
    });
  });
}
