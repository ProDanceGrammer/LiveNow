import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/statement/statement_table.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _cp1251(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      out.add(r);
    } else if (r >= 0x410 && r <= 0x44F) {
      out.add(0xC0 + r - 0x410);
    } else if (r == 0x456) {
      out.add(0xB3); // i (Ukrainian)
    } else if (r == 0x406) {
      out.add(0xB2); // I (Ukrainian)
    } else {
      throw ArgumentError('no cp1251 for $r');
    }
  }
  return Uint8List.fromList(out);
}

Uint8List _xlsx() {
  const ct =
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>';
  const wb = '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="A" sheetId="1" r:id="rId7"/></sheets></workbook>';
  const rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId7" Type="x" Target="worksheets/data.xml"/></Relationships>';
  const shared = '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<si><t>Дата</t></si><si><t>Опис</t></si><si><r><t>Ка</t></r><r><t>ва</t></r></si></sst>';
  const styles = '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      r'<numFmts count="1"><numFmt numFmtId="164" formatCode="dd\.mm\.yyyy\ hh:mm"/></numFmts>'
      '<cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs></styleSheet>';
  // 45000 = 2023-03-15; 45000.5 = noon.
  const sheet = '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>'
      '<c r="D1" t="inlineStr"><is><t>Сума</t></is></c></row>'
      '<row r="2"><c r="A2" s="1"><v>45000</v></c><c r="B2" t="s"><v>2</v></c><c r="D2"><v>-12.5</v></c></row>'
      '<row r="3"><c r="A3" s="2"><v>45000.5</v></c><c r="B3" t="str"><v>x</v></c>'
      '<c r="D3" s="0"><v>7</v></c></row>'
      '</sheetData></worksheet>';
  final a = Archive();
  void add(String n, String c) {
    final b = utf8.encode(c);
    a.addFile(ArchiveFile(n, b.length, b));
  }

  add('[Content_Types].xml', ct);
  add('xl/workbook.xml', wb);
  add('xl/_rels/workbook.xml.rels', rels);
  add('xl/sharedStrings.xml', shared);
  add('xl/styles.xml', styles);
  add('xl/worksheets/data.xml', sheet);
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('comma CSV with quotes, commas, newlines and a BOM', () {
    final t = readStatementTable(_utf8('﻿a,b\n"x, y","line1\nline2"\n\n1,2\n'));
    expect(t, [
      ['a', 'b'],
      ['x, y', 'line1\nline2'],
      ['1', '2'],
    ]);
  });

  test('semicolon CSV with decimal commas', () {
    final t = readStatementTable(_utf8('Дата;Сума;Залишок\n01.11.2026;-12,5;100,25\n'));
    expect(t[1], ['01.11.2026', '-12,5', '100,25']);
  });

  test('tab separated', () {
    expect(readStatementTable(_utf8('a\tb\tc\n1\t2\t3\n'))[1], ['1', '2', '3']);
  });

  test('Windows-1251 bytes are decoded', () {
    final t = readStatementTable(_cp1251('Дата;Опис\n01.11.2026;Кава Іра\n'));
    expect(t[0], ['Дата', 'Опис']);
    expect(t[1][1], 'Кава Іра');
  });

  test('XLSX: shared, inline, numeric and date cells, gaps kept', () {
    final t = readStatementTable(_xlsx(), fileName: 'x.xlsx');
    expect(t[0], ['Дата', 'Опис', '', 'Сума']);
    expect(t[1], ['15.03.2023', 'Кава', '', '-12.5']);
    expect(t[2], ['15.03.2023 12:00:00', 'x', '', '7']);
  });

  test('HTML saved as .xls', () {
    const html = '<html><body><table><tr><th>Дата</th><th>Сума</th></tr>'
        '<tr><td>01.11.2026&nbsp;10:00</td><td>-5 &amp; 1<br/>x</td></tr></table></body></html>';
    final t = readStatementTable(_utf8(html), fileName: 'a.xls');
    expect(t[0], ['Дата', 'Сума']);
    expect(t[1], ['01.11.2026 10:00', '-5 & 1 x']);
  });

  test('text saved as .xls is read as CSV', () {
    expect(readStatementTable(_utf8('a;b\n1;2\n'), fileName: 'a.xls')[1], ['1', '2']);
  });

  test('binary XLS (OLE2) gets a typed Ukrainian error', () {
    final bytes = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]);
    expect(
      () => readStatementTable(bytes, fileName: 'a.xls'),
      throwsA(isA<StatementFormatException>().having((e) => e.message, 'message', contains('CSV або XLSX'))),
    );
  });

  test('empty and corrupt zip are refused', () {
    expect(() => readStatementTable(Uint8List(0)), throwsA(isA<StatementFormatException>()));
    expect(
      () => readStatementTable(Uint8List.fromList([0x50, 0x4B, 1, 2, 3])),
      throwsA(isA<StatementFormatException>()),
    );
  });
}
