/// Turkish receipt words -> Ukrainian, in code. The 3B model garbles names
/// (potatoes became "whole-grain bread", water got Greek letters), so what this list
/// knows never goes to the model. Pure Dart, no model.
///
/// A printed name is folded (lower case, no diacritics, `5O0G` = `500G`), cut into
/// words, and read longest-phrase first; a glued word (`TAMBUGDAYEKMK`) must split
/// completely into known words. Product words come first in the answer, then the
/// words nobody knows (a brand, kept in Latin letters), then the pack size.
library;

import 'unit_normalizer.dart' show foldText;

/// Folded Turkish word or phrase -> Ukrainian. Later entries win.
const _entries = <(String, String)>[
  // vegetables, fruit
  ('patates', 'картопля'), ('limon', 'лимон'), ('domates', 'помідори'),
  ('salatalik', 'огірки'), ('biber', 'перець'), ('sivri biber', 'перець гострий'),
  ('dolmalik biber', 'перець болгарський'), ('sogan', 'цибуля'),
  ('sarimsak', 'часник'), ('havuc', 'морква'), ('kabak', 'кабачок'),
  ('patlican', 'баклажан'), ('marul', 'салат'), ('ispanak', 'шпинат'),
  ('maydanoz', 'петрушка'), ('dereotu', 'кріп'), ('nane', 'м’ята'),
  ('roka', 'руккола'), ('brokoli', 'броколі'), ('karnabahar', 'цвітна капуста'),
  ('lahana', 'капуста'), ('pancar', 'буряк'), ('turp', 'редис'),
  ('mantar', 'гриби'), ('misir', 'кукурудза'), ('fasulye', 'квасоля'),
  ('taze fasulye', 'стручкова квасоля'), ('bezelye', 'горошок'),
  ('elma', 'яблука'), ('armut', 'груші'), ('muz', 'банани'),
  ('portakal', 'апельсини'), ('mandalina', 'мандарини'), ('cilek', 'полуниця'),
  ('uzum', 'виноград'), ('karpuz', 'кавун'), ('kavun', 'диня'),
  ('avokado', 'авокадо'), ('nar', 'гранат'), ('kivi', 'ківі'),
  ('seftali', 'персики'), ('kiraz', 'черешня'), ('visne', 'вишня'),
  ('ananas', 'ананас'), ('incir', 'інжир'), ('hurma', 'хурма'),
  // meat, fish, eggs
  ('pilic', 'курка'), ('tavuk', 'курка'), ('bonfile', 'філе'),
  ('pilic bonfile', 'куряче філе'), ('tavuk bonfile', 'куряче філе'),
  ('but', 'стегна'), ('kanat', 'крильця'), ('kiyma', 'фарш'),
  ('dana', 'телятина'), ('kuzu', 'баранина'), ('biftek', 'біфштекс'),
  ('sucuk', 'суджук'), ('sosis', 'сосиски'), ('salam', 'салямі'),
  ('pilic salam', 'куряча салямі'), ('hindi', 'індичка'), ('fume', 'копчена'),
  ('hindi fume', 'індичка копчена'), ('jambon', 'шинка'), ('balik', 'риба'),
  ('somon', 'лосось'), ('ton baligi', 'тунець'), ('karides', 'креветки'),
  ('yumurta', 'яйця'),
  // dairy
  ('sut', 'молоко'), ('yogurt', 'йогурт'), ('ayran', 'айран'),
  ('peynir', 'сир'), ('beyaz peynir', 'бринза'), ('kasar', 'сир кашкавал'),
  ('lor', 'сир кисломолочний'), ('labne', 'лабне'), ('krema', 'вершки'),
  ('tereyag', 'вершкове масло'), ('tereyagi', 'вершкове масло'),
  ('margarin', 'маргарин'), ('kaymak', 'каймак'), ('kefir', 'кефір'),
  // bread, grains, pasta
  ('ekmek', 'хліб'), ('ekmk', 'хліб'), ('tambugday', 'цільнозерновий'),
  ('tam bugday', 'цільнозерновий'), ('simit', 'симіт'), ('lavas', 'лаваш'),
  ('un', 'борошно'), ('makarna', 'макарони'), ('spagetti', 'спагеті'),
  ('pirinc', 'рис'), ('bulgur', 'булгур'), ('mercimek', 'сочевиця'),
  ('nohut', 'нут'), ('karabugday', 'гречка'), ('yulaf', 'вівсянка'),
  ('misir gevregi', 'кукурудзяні пластівці'), ('galeta', 'сухарі'),
  // pantry
  ('seker', 'цукор'), ('tuz', 'сіль'), ('yag', 'олія'),
  ('aycicek yagi', 'соняшникова олія'), ('zeytinyagi', 'оливкова олія'),
  ('zeytin', 'оливки'), ('sirke', 'оцет'), ('salca', 'томатна паста'),
  ('ketcap', 'кетчуп'), ('ketcup', 'кетчуп'), ('mayonez', 'майонез'),
  ('hardal', 'гірчиця'), ('bal', 'мед'), ('recel', 'джем'),
  ('findik', 'фундук'), ('ceviz', 'горіхи'), ('badem', 'мигдаль'),
  ('fistik', 'фісташки'), ('yer fistigi', 'арахіс'), ('kuru uzum', 'родзинки'),
  ('kuru kayisi', 'курага'), ('kuru erik', 'чорнослив'), ('yaprak', 'листя'),
  ('yapragi', 'листя'), ('defne', 'лавровий лист'), ('defne yapragi', 'лавровий лист'),
  ('tursu', 'мариновані'), ('ezmesi', 'паста'), ('kakao', 'какао'),
  // drinks
  ('cay', 'чай'), ('kahve', 'кава'), ('su', 'вода'),
  ('maden suyu', 'мінеральна вода'), ('soda', 'содова'), ('kola', 'кола'),
  ('meyve suyu', 'сік'), ('gazoz', 'лимонад'), ('icecek', 'напій'),
  ('icecegi', 'напій'), ('ici', 'напій'), ('badem ici', 'мигдальний напій'),
  ('badem icecegi', 'мигдальний напій'), ('bira', 'пиво'), ('sarap', 'вино'),
  // sweets, snacks
  ('cikolata', 'шоколад'), ('cikol', 'шоколад'), ('bisk', 'печиво'),
  ('biskuvi', 'печиво'), ('gofret', 'вафлі'), ('kek', 'кекс'),
  ('bar', 'батончик'), ('nuga', 'нуга'), ('cips', 'чіпси'), ('sakiz', 'жуйка'),
  ('seker lama', 'цукерки'), ('draje', 'драже'), ('lokum', 'лукум'),
  ('dondurma', 'морозиво'), ('helva', 'халва'), ('krakers', 'крекери'),
  // household, care
  ('sabun', 'мило'), ('sampuan', 'шампунь'), ('deterjan', 'пральний порошок'),
  ('camasir suyu', 'відбілювач'), ('bulasik', 'для посуду'),
  ('tuvalet kagidi', 'туалетний папір'), ('pecete', 'серветки'),
  ('kagit havlu', 'паперові рушники'), ('dis macunu', 'зубна паста'),
  ('dis fircasi', 'зубна щітка'), ('sac maske', 'маска для волосся'),
  ('poset', 'пакети'), ('pil', 'батарейки'),
];

final Map<String, String> _words = {
  for (final (k, v) in _entries) k: v,
};

/// Keys without a space (candidates for splitting a glued word), longest first.
final List<String> _single = [
  for (final k in _words.keys)
    if (!k.contains(' ')) k,
]..sort((a, b) => b.length.compareTo(a.length));

final _token = RegExp(r'[a-z0-9]+(?:[.,][0-9]+[a-z]*)?');
final _pack = RegExp(r'^(\d+(?:[.,]\d+)?)(kg|kgr|gr|g|ml|cl|lt|l|adet|ad)$');

const _packUnits = {
  'kg': 'кг', 'kgr': 'кг', 'g': 'г', 'gr': 'г', 'ml': 'мл', 'cl': 'сл',
  'l': 'л', 'lt': 'л', 'adet': 'шт', 'ad': 'шт',
};

/// A letter O between digits is a zero (`5O0G`); [s] is already folded.
String _fixO(String s) =>
    s.replaceAllMapped(RegExp(r'(?<=\d)o(?=[\dg])'), (_) => '0');

/// Splits a glued word completely into known single words, or null.
List<String>? _segment(String t) {
  final memo = <int, List<String>?>{};
  List<String>? from(int i) {
    if (i == t.length) return const [];
    if (memo.containsKey(i)) return memo[i];
    List<String>? best;
    for (final k in _single) {
      if (k.length < 3 && t.length != k.length) continue; // short keys alone only
      if (!t.startsWith(k, i)) continue;
      final rest = from(i + k.length);
      if (rest != null) {
        best = [k, ...rest];
        break;
      }
    }
    return memo[i] = best;
  }

  final r = from(0);
  return r == null || r.isEmpty ? null : r;
}

String _title(String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';

/// The Ukrainian name of [printed] when it holds at least one word of the list;
/// null otherwise (the model translates those). Unknown words stay as a Latin
/// brand after the product words; the pack size (`500G`, `1L`) closes the name.
String? translateKnown(String printed) {
  final r = _read(printed);
  // Mostly unknown words (`MELIS KORNISON TURSU`: only `tursu` is known, and it is
  // just a modifier): the glossary would invent a half translation, the model gets it.
  if (r.product.isEmpty || r.brand.length > r.product.length) return null;
  return [...r.product, ...r.brand, ?r.pack].join(' ');
}

/// What the category lookup should search for: the known product words in
/// Ukrainian plus the words nobody knows (a brand: `Dost` finds `Молоко Dost`),
/// without the pack size. Unlike [translateKnown] it also answers when brand words
/// outnumber the known ones, because a lookup only ranks categories and the user
/// still confirms; null when no word of the name is known.
String? glossaryQuery(String printed) {
  final words = glossaryName(printed);
  if (words == null) return null;
  // Budgets spell some words differently from the receipt's translation: the
  // category is `Курка`, the translation `куряче філе`.
  return [for (final w in words.split(' ')) _lookupForms[w] ?? w].join(' ');
}

/// A display name for a line the glossary only half knows (`GUNLUK SUT 1L DOST`
/// -> `молоко Gunluk Dost`): the known words in Ukrainian, the others kept, no pack.
/// Better than the printed Latin name when nothing translates it; null when no
/// word is known.
String? glossaryName(String printed) {
  final r = _read(printed);
  if (r.product.isEmpty) return null;
  return [...r.product, ...r.brand].join(' ');
}

const _lookupForms = {'куряче': 'курка', 'куряча': 'курка', 'курячий': 'курка'};

({List<String> product, List<String> brand, String? pack}) _read(String printed) {
  final tokens = [
    for (final m in _token.allMatches(_fixO(foldText(printed)))) m[0]!,
  ];
  final product = <String>[];
  final brand = <String>[];
  String? pack;
  var i = 0;
  while (i < tokens.length) {
    String? hit;
    var used = 0;
    for (var n = 3; n >= 1 && hit == null; n--) {
      if (i + n > tokens.length) continue;
      final v = _words[tokens.sublist(i, i + n).join(' ')];
      if (v != null) {
        hit = v;
        used = n;
      }
    }
    if (hit != null) {
      product.add(hit);
      i += used;
      continue;
    }
    final t = tokens[i];
    final p = _pack.firstMatch(t);
    // `1 KG`, `500 G`: the number and its unit as two words.
    final spaced = i + 1 < tokens.length && RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t)
        ? _pack.firstMatch('$t${tokens[i + 1]}')
        : null;
    if (spaced != null) {
      pack ??= '${spaced[1]!.replaceAll(',', '.')} ${_packUnits[spaced[2]]}';
      i += 2;
      continue;
    }
    if (p != null) {
      pack ??= '${p[1]!.replaceAll(',', '.')} ${_packUnits[p[2]]}';
    } else if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t)) {
      // a lone number (VAT `1`, a count): noise
    } else {
      // The pack may be glued behind words (`tambugdayekmk500g`).
      final glued = RegExp(r'^([a-z]+)(\d+(?:[.,]\d+)?(?:kg|kgr|gr|g|ml|cl|lt|l))$').firstMatch(t);
      final word = glued?[1] ?? t;
      final seg = _segment(word);
      if (seg != null) {
        product.addAll([for (final k in seg) _words[k]!]);
        final gp = glued == null ? null : _pack.firstMatch(glued[2]!);
        if (gp != null) pack ??= '${gp[1]!.replaceAll(',', '.')} ${_packUnits[gp[2]]}';
      } else if (word.length >= 2) {
        brand.add(_title(word));
        final gp = glued == null ? null : _pack.firstMatch(glued[2]!);
        if (gp != null) pack ??= '${gp[1]!.replaceAll(',', '.')} ${_packUnits[gp[2]]}';
      }
    }
    i++;
  }
  return (product: product, brand: brand, pack: pack);
}
