import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../growth_import.dart' show parseDelimited;

/// The file cannot be read as a table; [message] is for the user (Ukrainian).
class StatementFormatException implements Exception {
  const StatementFormatException(this.message);
  final String message;

  @override
  String toString() => 'StatementFormatException: $message';
}

const _saveAs = 'Збережіть виписку як CSV або XLSX і надішліть ще раз.';

/// Any bank export (CSV, XLSX, HTML or text saved as .xls) as rows of cells.
/// Blank rows are dropped, cells are trimmed.
List<List<String>> readStatementTable(Uint8List bytes, {String? fileName}) {
  if (bytes.isEmpty) throw const StatementFormatException('Файл порожній.');
  List<List<String>> table;
  if (_starts(bytes, const [0x50, 0x4B])) {
    table = _readXlsx(bytes);
  } else if (_starts(bytes, const [0xD0, 0xCF, 0x11, 0xE0])) {
    throw const StatementFormatException('Це старий двійковий формат XLS. $_saveAs');
  } else if (_starts(bytes, const [0x25, 0x50, 0x44, 0x46])) {
    throw const StatementFormatException('Це PDF, а не таблиця. $_saveAs');
  } else {
    final probe = bytes.length < 2048 ? bytes : Uint8List.sublistView(bytes, 0, 2048);
    if (probe.contains(0)) {
      throw const StatementFormatException('Не вдалося прочитати файл як таблицю. $_saveAs');
    }
    final text = decodeStatementText(bytes);
    final head = text.trimLeft();
    if (head.startsWith('<') || text.toLowerCase().contains('<table')) {
      table = _readHtml(text);
    } else {
      table = parseDelimited(text, separator: detectSeparator(text));
    }
  }
  final out = <List<String>>[
    for (final r in table)
      if (r.any((c) => c.trim().isNotEmpty)) [for (final c in r) c.trim()],
  ];
  if (out.isEmpty) throw const StatementFormatException('У файлі не знайдено жодного рядка.');
  return out;
}

bool _starts(Uint8List b, List<int> magic) {
  if (b.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (b[i] != magic[i]) return false;
  }
  return true;
}

/// UTF-8 (a BOM is dropped), else Windows-1251.
String decodeStatementText(Uint8List bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    b = Uint8List.sublistView(b, 3);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return _cp1251(b);
  }
}

const _cp1251High = <int>[
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
];

String _cp1251(Uint8List b) {
  final out = StringBuffer();
  for (final x in b) {
    if (x < 0x80) {
      out.writeCharCode(x);
    } else if (x < 0xC0) {
      out.writeCharCode(_cp1251High[x - 0x80]);
    } else {
      out.writeCharCode(0x0410 + (x - 0xC0));
    }
  }
  return out.toString();
}

/// `,`, `;` or a tab: the one that occurs most outside quotes in the first lines.
String detectSeparator(String text) {
  final counts = {',': 0, ';': 0, '\t': 0};
  var inQuotes = false;
  var lines = 0;
  for (var i = 0; i < text.length && lines < 10; i++) {
    final c = text[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes) {
      if (c == '\n') {
        lines++;
      } else if (counts.containsKey(c)) {
        counts[c] = counts[c]! + 1;
      }
    }
  }
  var best = ',';
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

// ---- HTML saved as .xls ---------------------------------------------------------

List<List<String>> _readHtml(String html) {
  final rows = <List<String>>[];
  final tr = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  final td = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
  for (final r in tr.allMatches(html)) {
    rows.add([for (final c in td.allMatches(r.group(1)!)) _htmlText(c.group(1)!)]);
  }
  if (rows.isEmpty) throw const StatementFormatException('У файлі немає таблиці. $_saveAs');
  return rows;
}

String _htmlText(String s) {
  final t = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  return t
      .replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
        final e = m.group(1)!;
        if (e.startsWith('#')) {
          final code = e[1].toLowerCase() == 'x'
              ? int.tryParse(e.substring(2), radix: 16)
              : int.tryParse(e.substring(1));
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        return switch (e) {
          'nbsp' => ' ',
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          _ => m.group(0)!,
        };
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ---- XLSX -----------------------------------------------------------------------

List<List<String>> _readXlsx(Uint8List bytes) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    String? text(String path) {
      final f = zip.findFile(path);
      return f == null ? null : utf8.decode(f.content, allowMalformed: true);
    }

    final shared = <String>[];
    final ss = text('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(_plain(si));
      }
    }
    final dateStyles = _dateStyles(text('xl/styles.xml'));
    final sheetXml = text(_firstSheetPath(zip, text) ?? 'xl/worksheets/sheet1.xml');
    if (sheetXml == null) {
      throw const StatementFormatException('У файлі XLSX немає аркуша з даними.');
    }
    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
      final cells = <String>[];
      for (final c in row.findElements('c')) {
        final col = _columnOf(c.getAttribute('r'));
        while (cells.length < (col ?? cells.length)) {
          cells.add('');
        }
        cells.add(_cellValue(c, shared, dateStyles));
      }
      rows.add(cells);
    }
    return rows;
  } on StatementFormatException {
    rethrow;
  } catch (_) {
    throw const StatementFormatException('Не вдалося прочитати XLSX. $_saveAs');
  }
}

/// Text of a shared/inline string element: all `<t>` pieces, phonetic runs left out.
String _plain(XmlElement e) => [
  for (final t in e.findAllElements('t'))
    if (!t.ancestorElements.any((a) => a.name.local == 'rPh')) t.innerText,
].join();

String? _firstSheetPath(Archive zip, String? Function(String) text) {
  final wb = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  if (wb == null || rels == null) return null;
  final sheets = XmlDocument.parse(wb).findAllElements('sheet');
  if (sheets.isEmpty) return null;
  final id = sheets.first.attributes
      .where((a) => a.name.local == 'id')
      .map((a) => a.value)
      .firstOrNull;
  if (id == null) return null;
  for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
    if (r.getAttribute('Id') == id) {
      final t = r.getAttribute('Target');
      if (t == null) return null;
      return t.startsWith('/') ? t.substring(1) : 'xl/$t';
    }
  }
  return null;
}

int? _columnOf(String? ref) {
  if (ref == null) return null;
  final m = RegExp(r'^([A-Za-z]+)').firstMatch(ref);
  if (m == null) return null;
  var n = 0;
  for (final u in m.group(1)!.toUpperCase().codeUnits) {
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

/// Style indexes (`s=` of a cell) whose number format is a date/time.
Set<int> _dateStyles(String? styles) {
  if (styles == null) return const {};
  final doc = XmlDocument.parse(styles);
  final custom = <int, String>{};
  for (final f in doc.findAllElements('numFmt')) {
    final id = int.tryParse(f.getAttribute('numFmtId') ?? '');
    if (id != null) custom[id] = f.getAttribute('formatCode') ?? '';
  }
  bool isDate(int id) {
    if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47)) return true;
    final code = custom[id];
    if (code == null) return false;
    final bare = code
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\\.'), '')
        .toLowerCase();
    return RegExp(r'[dmyhs]').hasMatch(bare);
  }

  final out = <int>{};
  final xfs = doc.findAllElements('cellXfs').firstOrNull;
  if (xfs == null) return out;
  var i = 0;
  for (final xf in xfs.findElements('xf')) {
    final id = int.tryParse(xf.getAttribute('numFmtId') ?? '');
    if (id != null && isDate(id)) out.add(i);
    i++;
  }
  return out;
}

String _cellValue(XmlElement c, List<String> shared, Set<int> dateStyles) {
  final type = c.getAttribute('t');
  if (type == 'inlineStr') {
    final is_ = c.findElements('is').firstOrNull;
    return is_ == null ? '' : _plain(is_);
  }
  final v = c.findElements('v').firstOrNull?.innerText ?? '';
  if (v.isEmpty) return '';
  switch (type) {
    case 's':
      final i = int.tryParse(v);
      return i != null && i >= 0 && i < shared.length ? shared[i] : '';
    case 'str' || 'e':
      return v;
    case 'b':
      return v == '1' ? 'TRUE' : 'FALSE';
  }
  final style = int.tryParse(c.getAttribute('s') ?? '');
  final serial = double.tryParse(v);
  if (serial != null && style != null && dateStyles.contains(style)) {
    return _serialToText(serial);
  }
  return v;
}

String _serialToText(double serial) {
  final whole = serial.floor();
  final secs = ((serial - whole) * 86400).round();
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: whole, seconds: secs));
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  if (whole == 0) return time;
  final date = '${two(d.day)}.${two(d.month)}.${d.year.toString().padLeft(4, '0')}';
  return secs == 0 ? date : '$date $time';
}
