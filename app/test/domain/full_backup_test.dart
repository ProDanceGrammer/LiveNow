import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/full_backup.dart';

List<List<String?>> parse(String text, {int chunk = 1 << 20}) {
  final p = CsvRowParser();
  final rows = <List<String?>>[];
  for (var i = 0; i < text.length; i += chunk) {
    rows.addAll(p.add(text.substring(i, (i + chunk).clamp(0, text.length))));
  }
  rows.addAll(p.close());
  return rows;
}

void main() {
  test('NULL and the empty string survive a CSV round trip', () {
    final line = csvLine(['a', null, '', 'x,y', 'say "hi"', 'two\nlines', 5, 1.5]);
    expect(line, 'a,,"","x,y","say ""hi""","two\nlines",5,1.5');
    final rows = parse('$line\n');
    expect(rows, [
      ['a', null, '', 'x,y', 'say "hi"', 'two\nlines', '5', '1.5'],
    ]);
  });

  test('the parser is the same however the text is cut into chunks', () {
    final text = '${csvLine(['id', 'note'])}\n'
        '${csvLine(['1', 'He said "yes",\nthen left'])}\n'
        '${csvLine(['2', null])}\n'
        '${csvLine(['3', ''])}';
    final whole = parse(text);
    expect(whole, hasLength(4));
    for (final size in [1, 2, 3, 7]) {
      expect(parse(text, chunk: size), whole, reason: 'chunk $size');
    }
    expect(whole[2], ['2', null]);
    expect(whole[3], ['3', '']);
  });

  test('CRLF line ends and emoji are read correctly', () {
    expect(parse('a,b\r\n🇺🇦 ✅,"c"\r\n'), [
      ['a', 'b'],
      ['🇺🇦 ✅', 'c'],
    ]);
  });

  test('the header refuses foreign and too-new files', () {
    expect(
      () => parseHeaderLine('not json'),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => parseHeaderLine('{"format":"other"}'),
      throwsA(isA<BackupFormatException>()),
    );
    expect(
      () => parseHeaderLine(
        '{"format":"livenow-full","version":99,"schemaVersion":12}',
      ),
      throwsA(isA<BackupFormatException>()),
    );
    final ok = parseHeaderLine(encodeHeaderLine(12, DateTime.utc(2026, 10, 13)));
    expect(ok.schemaVersion, 12);
  });
}
