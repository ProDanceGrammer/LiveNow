import 'unit_normalizer.dart' show UnitKind, foldText;

// Bazaar note parser (spec 5.B): an iOS Notes checklist, paid in cash.
//   - [x] Кабачки 65/30=2,167   total 65, price 30 per kg, quantity 2.167
//   - [x] Морква 20             price 20 per kg, quantity 1
//   - [ ] Груші 80              not bought: ignored
//   - [x] Зелень 20             herbs are a Piece: price 20, quantity 1
// Pure; money math stays in code.

class BazaarItem {
  const BazaarItem({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.flags = const [],
  });

  final String name;

  /// kilograms, or pieces for herbs.
  final UnitKind unit;
  final double quantity;
  final double unitPrice;
  final double total;

  /// `herb`, `qty_mismatch` (T/P differs from the written quantity: the
  /// quantity became T/P, the paid total is kept), `qty_computed`.
  final List<String> flags;
}

class BazaarNote {
  const BazaarNote(this.items, this.ignored, this.unparsed);
  final List<BazaarItem> items;

  /// Names of the unchecked `[ ]` lines.
  final List<String> ignored;

  /// Checked lines without a readable price: ask the user.
  final List<String> unparsed;

  double get total =>
      ((items.fold(0.0, (a, i) => a + i.total)) * 100).round() / 100;
}

final _checkbox = RegExp(r'^\s*(?:[-*•]\s*)?\[\s*([xXхХ✓✔]?)\s*\]\s*(.+?)\s*$');
const _n = r'(\d+(?:[.,]\d+)?)';
final _item = RegExp('^(.*?)\\s+$_n\\s*(?:/\\s*$_n\\s*(?:=\\s*$_n)?)?\\s*\$');
const _herbs = [
  'зелен', 'кріп', 'кроп', 'укроп', 'петрушк', 'кінз', 'кинз', 'базилік',
  'базилик', "м'ят", 'мят', 'коріандр', 'кориандр',
];

double _d(String s) => double.parse(s.replaceAll(',', '.'));

bool _isHerb(String name) {
  final f = foldText(name);
  return _herbs.any(f.contains);
}

BazaarNote parseBazaarNote(String text) {
  final items = <BazaarItem>[];
  final ignored = <String>[];
  final unparsed = <String>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final box = _checkbox.firstMatch(line);
    if (box == null) continue;
    final body = box[2]!;
    if (box[1]!.isEmpty) {
      ignored.add(body);
      continue;
    }
    final m = _item.firstMatch(body);
    if (m == null) {
      unparsed.add(body);
      continue;
    }
    final name = m[1]!.trim();
    final first = _d(m[2]!);
    final flags = <String>[];
    final herb = _isHerb(name);
    if (herb) flags.add('herb');
    var price = first;
    var qty = 1.0;
    var total = first;
    if (m[3] != null) {
      price = _d(m[3]!);
      if (price <= 0) {
        unparsed.add(body);
        continue;
      }
      total = first;
      final computed = total / price;
      if (m[4] == null) {
        qty = computed;
        flags.add('qty_computed');
      } else {
        qty = _d(m[4]!);
        final tol = qty * 0.01 > 0.01 ? qty * 0.01 : 0.01;
        if ((computed - qty).abs() > tol) {
          qty = computed;
          flags.add('qty_mismatch');
        }
      }
    }
    items.add(
      BazaarItem(
        name: name,
        unit: herb ? UnitKind.pieces : UnitKind.kilograms,
        quantity: qty,
        unitPrice: price,
        total: total,
        flags: flags,
      ),
    );
  }
  return BazaarNote(items, ignored, unparsed);
}
