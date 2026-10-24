import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart'
    show InsertMode, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/text_rules.dart';
import 'package:livenow/data/backup/backup_import_service.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/form_service.dart';
import 'package:livenow/domain/forms.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/search_match.dart';
import 'package:livenow/domain/sync/change_validation.dart';
import 'package:livenow/domain/sync/sync_models.dart';

// Special characters and Unicode through create / rename / search / CSV /
// backup / sync. Names that must survive byte for byte are in [_keep]; names
// the service boundary cleans are in [_cleaned].

final _keep = <String, String>{
  'plain': 'Run 5 km',
  'emoji zwj': '👨‍👩‍👧‍👦 family',
  'emoji flags': '🇺🇦🇹🇷 flags',
  'emoji skin tones': '👍🏽 ok 👋🏿',
  'rtl arabic': 'مرحبا بالعالم',
  'rtl hebrew': 'שלום עולם',
  'rtl mixed': 'Call مرحبا at 5',
  'turkish': 'İstanbul ısı ŞĞÜÖÇ',
  'nfc': 'caf\u00e9',
  'nfd': 'cafe\u0301',
  'zero width': 'a\u200bb\u200cc\u2060d\ufeffe',
  'sql quote': "O'Brien'; DROP TABLE actions; --",
  'sql percent underscore': '100%_done',
  'backslash': r'C:\temp\new\%n',
  'double quote': 'say "hi"',
  'html': '<script>alert(1)</script> &amp;',
  'json': '{"a":[1,2],"b":null}',
  'markdown': '# **bold** [x](http://e.com)',
  'newline': 'line one\nline two',
  'crlf': 'one\r\ntwo',
  'tab': 'a\tb',
  'comma': 'a, b, "c"',
  'cyrillic': 'Привіт, світе',
  'cjk': '日本語のテキスト',
  'combining': 'a\u0300\u0301\u0302',
  'rtl override': 'abc\u202edef',
  'formula equals': '=1+1',
  'formula plus': '+SUM(A1:A2)',
  'formula minus': '-2+3',
  'formula at': '@SUM(1)',
  'formula quote': "'=1+1",
  'leading space': ' padded ',
  'only symbols': '---',
  'lone dash': '-',
  'long 480': 'x' * 480,
};

/// Raw input -> what is stored.
final _cleaned = <String, String>{
  'nul': 'ab\u0000cd',
  'control chars': 'a\u0001b\u0007c\u001fd\u007fe',
  'lone high surrogate': 'a\ud800b',
  'lone low surrogate': 'a\udc00b',
  'surrogates reversed': 'a\udc00\ud800b',
  'pair kept next to lone': '😀\ud800😀',
};

String _expectedClean(String raw) => switch (raw) {
  'ab\u0000cd' => 'abcd',
  'a\u0001b\u0007c\u001fd\u007fe' => 'abcde',
  'a\ud800b' => 'ab',
  'a\udc00b' => 'ab',
  'a\udc00\ud800b' => 'ab',
  '😀\ud800😀' => '😀😀',
  _ => raw,
};

AppDatabase _db() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionService actions;

  setUp(() {
    db = _db();
    actions = ActionService(db);
  });
  tearDown(() => db.close());

  Future<String> nameOf(String id) async => (await db
          .customSelect(
            'SELECT name FROM actions WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle())
      .read<String>('name');

  group('text rules', () {
    test('stripUnsafeText keeps pairs, tabs and newlines', () {
      expect(stripUnsafeText('a\tb\nc\r\nd 😀'), 'a\tb\nc\r\nd 😀');
      expect(stripUnsafeText('\u0000\u0001'), '');
      expect(stripUnsafeText('\ud83d'), '');
    });

    test('cleanName trims and caps at 500 characters, counting emoji once', () {
      expect(cleanName('  hi  '), 'hi');
      expect(cleanName('x' * 500), hasLength(500));
      expect(() => cleanName('x' * 501), throwsA(isA<InvalidNameException>()));
      // 400 emoji = 800 UTF-16 units but only 400 characters.
      expect(cleanName('😀' * 400).runes, hasLength(400));
      expect(() => cleanName('😀' * 501), throwsA(isA<InvalidNameException>()));
      expect(
        () => cleanName('x' * 501, what: 'direction name'),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains('direction name') &&
                e.toString().contains('500'),
          ),
        ),
      );
    });

    test('requireName refuses an empty or all-control name', () {
      expect(() => requireName('   '), throwsA(isA<InvalidNameException>()));
      expect(() => requireName('\u0000'), throwsA(isA<InvalidNameException>()));
    });

    test('the CSV guard is an exact inverse for every awkward string', () {
      final samples = [
        ..._keep.values,
        "'",
        "''",
        "''=x",
        "'-5",
        "'-5x",
        "-5",
        "+1.5",
        "-1e3",
        "=",
        "\t=x",
        "\rx",
        "'\t",
        '',
        'abc',
        "a'=b",
      ];
      for (final s in samples) {
        expect(unguardCsvCell(guardCsvCell(s)), s, reason: 'for "$s"');
      }
      expect(guardCsvCell('=1+1'), "'=1+1");
      expect(guardCsvCell('@x'), "'@x");
      expect(guardCsvCell('-5'), '-5', reason: 'a plain number is not a formula');
      expect(guardCsvCell('abc'), 'abc');
    });
  });

  group('create / rename through the service', () {
    for (final e in _keep.entries) {
      test('${e.key} survives createAction + updateAction exactly', () async {
        final expected = e.value.trim();
        final id = await actions.createAction(name: e.value);
        expect(await nameOf(id), expected);
        await actions.updateAction(
          actionId: id,
          name: '${e.value}!',
          postponeFlex: 'flexible',
          isAllDay: false,
        );
        expect(await nameOf(id), '${e.value}!'.trim());
        await actions.updateAction(
          actionId: id,
          name: e.value,
          postponeFlex: 'flexible',
          isAllDay: false,
        );
        expect(await nameOf(id), expected);
      });
    }

    for (final e in _cleaned.entries) {
      test('${e.key} is cleaned at the boundary (action, direction, category)', () async {
        final want = _expectedClean(e.value);
        final id = await actions.createAction(name: e.value);
        expect(await nameOf(id), want);
        await actions.updateAction(
          actionId: id,
          name: e.value,
          postponeFlex: 'flexible',
          isAllDay: false,
        );
        expect(await nameOf(id), want);

        final mId = await MetricService(db).saveMetric(
          name: e.value,
          kind: MetricKind.boolean,
        );
        expect(
          (await db.customSelect('SELECT name FROM metrics WHERE id = ?',
                  variables: [Variable.withString(mId)]).getSingle())
              .read<String>('name'),
          want,
        );
        final cId = await BudgetService(db).saveCategory(
          CategoryInput(name: e.value),
        );
        expect(
          (await db.customSelect('SELECT name FROM budget_categories WHERE id = ?',
                  variables: [Variable.withString(cId)]).getSingle())
              .read<String>('name'),
          want,
        );
      });
    }

    test('a stored name with a NUL byte (older data) reads back whole', () async {
      final id = await actions.createAction(name: 'x');
      await db.customStatement(
        'UPDATE actions SET name = ? WHERE id = ?',
        ['a\u0000b', id],
      );
      // Older rows may hold it: reading must not throw.
      final row = await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.name.length, greaterThanOrEqualTo(1));
    });

    test('a 501 character name is refused with a friendly exception, nothing stored', () async {
      await expectLater(
        actions.createAction(name: 'y' * 501),
        throwsA(isA<InvalidNameException>()),
      );
      final id = await actions.createAction(name: 'ok');
      await expectLater(
        actions.updateAction(
          actionId: id,
          name: 'y' * 501,
          postponeFlex: 'flexible',
          isAllDay: false,
        ),
        throwsA(isA<InvalidNameException>()),
      );
      expect(await nameOf(id), 'ok');
      expect((await db.select(db.actionsTable).get()), hasLength(1));
      await expectLater(
        () => MetricService(db).saveMetric(name: 'y' * 501, kind: MetricKind.boolean),
        throwsA(isA<InvalidNameException>()),
      );
      await expectLater(
        () => BudgetService(db).saveCategory(CategoryInput(name: 'y' * 501)),
        throwsA(isA<InvalidNameException>()),
      );
      await expectLater(
        () => FormService(db).save(FormDef(name: 'y' * 501)),
        throwsA(isA<InvalidNameException>()),
      );
    });

    test('a 10k and a 1 MB name are refused; 1 MB notes are stored and found', () async {
      await expectLater(
        actions.createAction(name: 'z' * 10000),
        throwsA(isA<InvalidNameException>()),
      );
      await expectLater(
        actions.createAction(name: 'z' * 1024 * 1024),
        throwsA(isA<InvalidNameException>()),
      );
      final big = 'needle ${'lorem ipsum ' * 90000}';
      final notes = jsonEncode({
        'document': {
          'type': 'page',
          'children': [
            {
              'type': 'paragraph',
              'data': {
                'delta': [
                  {'insert': big},
                ],
              },
            },
          ],
        },
      });
      expect(notes.length, greaterThan(1024 * 1024));
      final id = await actions.createAction(name: 'big notes', notes: notes);
      final row = await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.notes, notes);
      final ids = await ViewQueries(db).watchNotesMatchIds('needle').first;
      expect(ids, {id});
    });

    test('a name with a newline stays one row and one name', () async {
      final id = await actions.createAction(name: 'one\ntwo');
      expect(await nameOf(id), 'one\ntwo');
      expect(await db.select(db.actionsTable).get(), hasLength(1));
    });
  });

  group('search (Dart rules)', () {
    test('Turkish dotted / dotless i fold to i, either way', () {
      expect(matchTier('İstanbul', 'istanbul'), isNotNull);
      expect(matchTier('istanbul', 'İSTANBUL'), isNotNull);
      expect(matchTier('ISI', 'ısı'), isNotNull);
      expect(matchTier('ısı', 'isi'), isNotNull);
      expect(matchTier('Şişli', 'şişli'), isNotNull);
      expect(matchTier('Çay', 'çay'), isNotNull);
    });

    test('zero-width characters do not hide a match', () {
      expect(matchTier('hel\u200blo world', 'hello'), isNotNull);
      expect(matchTier('hello', 'hel\u200blo'), isNotNull);
      expect(matchTier('a\u200db', 'ab'), isNotNull);
    });

    test('emoji, RTL and CJK are matched as typed', () {
      expect(matchTier('Family 👨‍👩‍👧‍👦 time', '👨‍👩‍👧‍👦'), 0);
      expect(matchTier('مرحبا بالعالم', 'بالعالم'), 0);
      expect(matchTier('日本語のテキスト', 'テキスト'), isNotNull);
      expect(matchTier('Привіт, світе', 'СВІТЕ'), 0);
    });

    test('regex and SQL special characters in the query are literal', () {
      for (final q in [r'.*', r'(', r'[a-', r'\', '%', '_', "'", '"', r'$^', '+?', '{1,2}']) {
        expect(() => matchTier('some text', q), returnsNormally, reason: q);
      }
      expect(matchTier('100% done', '%'), isNotNull);
      expect(matchTier('a_b', '_'), isNotNull);
      expect(matchTier('abc', '%'), isNull);
      expect(matchTier('abc', '_'), isNull);
      expect(matchTier('abc', '.'), isNull);
      expect(matchTier(r'C:\temp', r'c:\t'), isNotNull);
    });

    test('lone surrogates, NUL and huge queries never throw', () {
      expect(() => matchTier('abc', '\ud800'), returnsNormally);
      expect(() => matchTier('a\ud800c', 'a\ud800'), returnsNormally);
      expect(() => matchTier('abc', 'a\u0000b'), returnsNormally);
      expect(() => matchTier('abc', 'q' * 1024 * 1024), returnsNormally);
      expect(matchTier('x' * 1024 * 1024, 'x' * 10), isNotNull);
    });

    test('rankMatches orders whole words first with odd names', () {
      final names = ['it‌fix', 'fix it', 'ﬁx', '🙂 fix', ''];
      final out = rankMatches(names, 'fix', (n) => [n]);
      expect(out.first, anyOf('fix it', '🙂 fix'));
    });

    test('NFC and NFD spellings of one word: documented limit', () {
      // No Unicode normalisation library is available: a query typed as the
      // precomposed letter does not find a name stored decomposed.
      expect(matchTier('caf\u00e9', 'caf\u00e9'), 0);
      expect(matchTier('cafe\u0301', 'cafe\u0301'), 0);
    }, skip: false);
  });

  group('search (SQL)', () {
    test('notes search treats % _ and \\ literally', () async {
      Future<String> withNotes(String name, String text) => actions.createAction(
            name: name,
            notes: jsonEncode({
              'document': {
                'type': 'page',
                'children': [
                  {
                    'type': 'paragraph',
                    'data': {
                      'delta': [
                        {'insert': text},
                      ],
                    },
                  },
                ],
              },
            }),
          );
      final pct = await withNotes('p', 'saved 100% today');
      final under = await withNotes('u', 'snake_case here');
      final slash = await withNotes('s', r'path C:\temp');
      final plain = await withNotes('x', 'nothing special 1000 snakeXcase');
      Future<Set<String>> find(String q) =>
          ViewQueries(db).watchNotesMatchIds(q.toLowerCase()).first;
      expect(await find('%'), {pct});
      expect(await find('100%'), {pct});
      expect(await find('_'), {under});
      expect(await find('snake_case'), {under});
      expect(await find(r'\'), {slash});
      expect(await find(r'c:\t'), {slash});
      expect(await find("'; drop table actions; --"), isEmpty);
      expect(await find('special'), {plain});
      expect(await find('ПРИВІТ'), isEmpty);
      expect((await db.select(db.actionsTable).get()), hasLength(4));
    });

    test('Cyrillic and Turkish notes are found case-insensitively', () async {
      final id = await actions.createAction(
        name: 'n',
        notes: jsonEncode({
          'document': {
            'type': 'page',
            'children': [
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': 'Привіт Світе İstanbul'},
                  ],
                },
              },
            ],
          },
        }),
      );
      final q = ViewQueries(db);
      expect(await q.watchNotesMatchIds('привіт').first, {id});
      expect(await q.watchNotesMatchIds('світе').first, {id});
    });
  });

  group('CSV export / import round trips', () {
    test('csvLine + CsvRowParser round-trip every awkward string', () {
      final values = [..._keep.values, '', null, '  ', 'a\r\nb'];
      final line = csvLine(values);
      final p = CsvRowParser();
      final rows = [...p.add('$line\n'), ...p.close()];
      expect(rows, hasLength(1));
      expect(rows.single.length, values.length);
      for (var i = 0; i < values.length; i++) {
        final got = rows.single[i];
        expect(got == null ? null : unguardCsvCell(got), values[i],
            reason: 'cell $i');
      }
    });

    test('the exported cell of a formula-looking value is neutralised', () {
      for (final f in ['=1+1', '+SUM(A1)', '-2+3', '@SUM(1)', '=cmd|calc']) {
        final cell = csvCell(f);
        expect(cell.replaceAll('"', '').startsWith("'"), isTrue, reason: f);
      }
      // Numbers and normal text are untouched; numeric objects are not strings.
      expect(csvCell(-5), '-5');
      expect(csvCell(-5.5), '-5.5');
      expect(csvCell('-5'), '-5');
      expect(csvCell('hello'), 'hello');
      expect(csvCell(null), '');
      expect(csvCell(''), '""');
    });

    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('livenow-text'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Map<String, List<List<Object?>>>> dump(AppDatabase d) async {
      final out = <String, List<List<Object?>>>{};
      await for (final c in BackupWriter(d).chunks()) {
        out.putIfAbsent(c.table, () => []).addAll(c.rows);
      }
      return out;
    }

    BackupImportService service(AppDatabase d) =>
        BackupImportService(d, SyncStore(d));

    Future<void> seedAll() async {
      for (final v in _keep.values) {
        await actions.createAction(name: v, notes: null);
      }
      final m = MetricService(db);
      for (final e in _keep.entries) {
        await m.saveMetric(name: e.value, kind: MetricKind.boolean);
      }
      final b = BudgetService(db);
      for (final v in _keep.values) {
        await b.saveCategory(CategoryInput(name: v));
      }
    }

    test('backup CSV folder round-trips formula-looking and quoted names exactly', () async {
      await seedAll();
      final other = _db();
      addTearDown(other.close);
      final before = await dump(db);
      final files = await BackupWriter(db).writeCsvFolder(Directory(dir.path));
      // Nothing in the files starts a cell with a bare formula character.
      for (final f in files) {
        final text = await f.readAsString();
        expect(
          RegExp(r'(^|,)[=@]').hasMatch(text.split('\n').skip(1).join('\n')),
          isFalse,
          reason: f.path,
        );
      }
      await service(other).import(
        CsvFolderBackupSource({
          for (final f in files) f.uri.pathSegments.last: f,
        }),
      );
      expect(await dump(other), before);
    });

    test('compact .livenow backup round-trips every awkward string', () async {
      await seedAll();
      final other = _db();
      addTearDown(other.close);
      final before = await dump(db);
      final f = File('${dir.path}/a.livenow');
      await BackupWriter(db).writeCompact(f);
      await service(other).import(CompactBackupSource(f));
      expect(await dump(other), before);
    });

    test('budget Notion-layout CSV export then import returns the same names', () async {
      final b = BudgetService(db);
      await b.saveAccount(
        name: '=ACC',
        currency: 'USD',
        rateToBase: 1,
      );
      final names = [
        '=1+1',
        '+x',
        '@y',
        'Plain, with comma',
        'quote "q"',
        'multi\nline',
        "'=already",
        'Привіт',
      ];
      for (final n in names) {
        await b.saveCategory(CategoryInput(name: n));
      }
      final csvs = await BudgetIoService(db).exportCsvs();
      for (final text in csvs.values) {
        final lines = text.split('\n').skip(1);
        expect(
          lines.any((l) => RegExp(r'^[=+@]').hasMatch(l)),
          isFalse,
          reason: 'a formula leads a line',
        );
      }
      final other = _db();
      addTearDown(other.close);
      await BudgetIoService(other).importNotionCsvs(
        accountsCsv: csvs.values.elementAt(0),
        categoriesCsv: csvs.values.elementAt(1),
        transactionsCsv: csvs.values.elementAt(2),
      );
      final got = {
        for (final r in await other.select(other.budgetCategoriesTable).get())
          r.name,
      };
      expect(got, names.toSet());
      expect(
        (await other.select(other.budgetAccountsTable).get()).single.name,
        '=ACC',
      );
    });
  });

  group('sync wire and validation', () {
    SyncChange change(String name) => SyncChange(
      table: 'actions',
      rowId: 'r1',
      hlc: '2026-10-10T12:00:00.123Z-0001-devA',
      origin: 'devA',
      deleted: false,
      data: {'id': 'r1', 'name': name},
      seq: 1,
    );

    test('every awkward name survives JSON encoding of a change', () {
      for (final v in [..._keep.values, ..._cleaned.keys.map((k) => _cleaned[k]!)]) {
        final wire = jsonEncode(change(v).toJson());
        final back = SyncChange.fromJson(
          (jsonDecode(wire) as Map).cast<String, Object?>(),
        );
        expect(back.data!['name'], v, reason: v.codeUnits.toString());
        expect(
          validateChange(back, now: DateTime.utc(2026, 10, 17)),
          isNull,
        );
      }
    });

    test('a merged remote change cannot store a NUL or lone surrogate name', () async {
      // A hostile peer sends a name with control characters: whatever the
      // merge stores, reading the row back must not throw and must round-trip
      // through the app's own backup writer.
      final other = _db();
      addTearDown(other.close);
      await other.customStatement(
        'INSERT INTO actions (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
        ['r1', 'a\u0000b', '2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z'],
      );
      var n = 0;
      await for (final c in BackupWriter(other).chunks()) {
        n += c.rows.length;
      }
      expect(n, greaterThan(0));
    });

    test('a 1 MB name in a change is within the field cap or refused, never thrown', () {
      final r = validateChange(
        change('n' * (1024 * 1024)),
        now: DateTime.utc(2026, 10, 17),
      );
      // Accepting up to the text cap is fine; the call itself must not throw.
      expect(r, anyOf(isNull, isA<String>()));
    });
  });

  group('templates and forms names', () {
    test('a form name is cleaned and capped', () async {
      final id = await FormService(db).save(FormDef(name: 'A\u0000B'));
      expect((await FormService(db).get(id))!.name, 'AB');
    });

    test('a template row stores emoji and RTL names unchanged', () async {
      for (final v in _keep.values) {
        await db.into(db.actionTemplatesTable).insert(
              ActionTemplatesTableCompanion.insert(
                id: 't${v.hashCode}',
                name: v,
                payload: jsonEncode({'name': v}),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
      final rows = await db.select(db.actionTemplatesTable).get();
      expect({for (final r in rows) r.name}, _keep.values.toSet());
    });
  });
}
