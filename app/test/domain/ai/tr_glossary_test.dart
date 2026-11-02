import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/model_prompts.dart';
import 'package:livenow/domain/ai/tr_glossary.dart';

void main() {
  group('translateKnown: the BIM receipt names, no model', () {
    test('plain product words', () {
      expect(translateKnown('PATATES'), 'картопля');
      expect(translateKnown('LiMON'), 'лимон');
      expect(translateKnown('DOMATES'), 'помідори');
      expect(translateKnown('SALATALIK'), 'огірки');
    });

    test('phrases win over single words', () {
      expect(translateKnown('PiLIC BONFILE'), 'куряче філе');
      expect(translateKnown('HiNDi FUME 60G'), 'індичка копчена 60 г');
      expect(translateKnown('PiLiC SALAM 150G'), 'куряча салямі 150 г');
    });

    test('a glued word with an OCR zero is split and its pack read', () {
      expect(translateKnown('TAMBUGDAYEKMK5O0G'), 'цільнозерновий хліб 500 г');
    });

    test('unknown words stay as a Latin brand, the pack closes the name', () {
      expect(translateKnown('GUNLUK SUT 1L'), 'молоко Gunluk 1 л');
      expect(translateKnown('SAKA SU'), 'вода Saka');
      expect(translateKnown('BAR NUGA 240G MiNiKI'), 'батончик нуга Miniki 240 г');
    });

    test('whole-word buckwheat is still buckwheat, wheat bread is not', () {
      expect(translateKnown('REIS KARABUGDAY 1 KG'), contains('гречка'));
      expect(translateKnown('TAMBUGDAYEKMK'), isNot(contains('гречка')));
    });

    test('mostly unknown words go to the model, not a half translation', () {
      expect(translateKnown('GUNLUK SUT 1L DOST'), isNull);
      expect(translateKnown('MELIS KORNISON TURSU'), isNull);
    });

    test('names with no known word go to the model', () {
      expect(translateKnown('HARIBO CHAMMALLOHE'), isNull);
      expect(translateKnown('XYZ 500G'), isNull);
    });
  });

  group('isCleanTranslation: garbled model answers are dropped', () {
    test('Cyrillic, a Latin brand word, digits and punctuation pass', () {
      expect(isCleanTranslation('молоко Dost 1 л'), isTrue);
      expect(isCleanTranslation('гречка 500г'), isTrue);
      expect(isCleanTranslation('м’ясо (курка)'), isTrue);
    });

    test('a Greek letter inside Cyrillic fails', () {
      expect(isCleanTranslation('саκа сο'), isFalse);
    });

    test('a word that mixes Cyrillic and Latin letters fails', () {
      expect(isCleanTranslation('мolоко'), isFalse);
    });

    test('parseTranslatedItems keeps only the clean ones', () {
      final out = parseTranslatedItems({
        'items': [
          {'n': 1, 'ua': 'вода Saka'},
          {'n': 2, 'ua': 'саκа сο'},
        ],
      });
      expect(out, {1: 'вода Saka'});
    });
  });
}
