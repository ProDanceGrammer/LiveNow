import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/ids.dart';
import '../core/settings.dart';
import '../core/text_rules.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'budget_csv.dart';
import 'budget_icons.dart';
import 'budget_rules.dart';
import 'budget_service.dart';

/// What an import did (and what it had to leave out or guess).
class BudgetImportSummary {
  const BudgetImportSummary({
    required this.accounts,
    required this.categories,
    required this.transactions,
    this.linkedToActions = 0,
    this.actionsNotFound = 0,
    this.skippedNoCategory = 0,
    this.skippedNoDate = 0,
    this.skippedGroupCategory = 0,
    this.unresolvedChildren = const [],
    this.unresolvedPercentSources = const [],
    this.currencyGuessed = const [],
    this.ratesMissing = const [],
    this.unknownAccounts = const [],
    this.suspiciousRates = const [],
  });

  final int accounts;
  final int categories;
  final int transactions;
  final int linkedToActions;

  /// Transactions that name an action no existing action matches (name +
  /// start): they keep their own date, unlinked.
  final int actionsNotFound;
  final int skippedNoCategory;
  final int skippedNoDate;
  final int skippedGroupCategory;
  final List<String> unresolvedChildren;
  final List<String> unresolvedPercentSources;

  /// Accounts whose currency is unknown (shown as XXX): edit them by hand.
  final List<String> currencyGuessed;

  /// Accounts no transaction had a rate for (rate left at 1).
  final List<String> ratesMissing;
  final List<String> unknownAccounts;

  /// Transactions with an exchange rate far from their account's current one.
  final List<String> suspiciousRates;

  bool get hasWarnings =>
      suspiciousRates.isNotEmpty ||
      skippedNoCategory + skippedNoDate + skippedGroupCategory > 0 ||
      actionsNotFound > 0 ||
      unresolvedChildren.isNotEmpty ||
      unresolvedPercentSources.isNotEmpty ||
      currencyGuessed.isNotEmpty ||
      ratesMissing.isNotEmpty ||
      unknownAccounts.isNotEmpty;
}

const budgetJsonFormat = 'livenow-budget';
const _budgetJsonVersion = 1;

/// Import / export of the whole budget. Import REPLACES all budget accounts,
/// categories and transactions (settings are kept for CSV, restored for JSON)
/// in one transaction.
class BudgetIoService {
  BudgetIoService(this.db);

  final AppDatabase db;

  /// Puts an emoji at the start of category names: a category called "Взуття"
  /// with the row `Взуття,👟` becomes "👟 Взуття" (emoji, one space, name). A
  /// name is matched without any emoji it already has, so a second import
  /// changes the icon instead of stacking another one; every category with that
  /// name gets it (names repeat in the Notion data). One transaction; the rename
  /// is an ordinary edit (`updated_at` moves, sync sees it).
  Future<CategoryIconResult> applyCategoryIcons(List<CategoryIcon> icons) {
    final byKey = {for (final i in icons) categoryNameKey(i.name): i};
    return db.transaction(() async {
      final rows = await db
          .customSelect('SELECT id, name FROM budget_categories')
          .get();
      final now = dateTimeToDb(DateTime.now().toUtc())!;
      final used = <String>{};
      var updated = 0, unchanged = 0;
      for (final r in rows) {
        final name = r.read<String>('name');
        final base = stripLeadingIcon(name);
        final key = categoryNameKey(base);
        final icon = byKey[key];
        if (icon == null) continue;
        used.add(key);
        final renamed = '${icon.icon} $base';
        if (renamed == name) {
          unchanged++;
          continue;
        }
        await db.customStatement(
          'UPDATE budget_categories SET name = ?, updated_at = ? WHERE id = ?',
          [renamed, now, r.read<String>('id')],
        );
        updated++;
      }
      return CategoryIconResult(
        updated: updated,
        unchanged: unchanged,
        notFound: [
          for (final e in byKey.entries)
            if (!used.contains(e.key)) e.value.name,
        ],
      );
    });
  }

  Future<bool> hasData() async {
    final row = await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM budget_accounts) + '
          '(SELECT COUNT(*) FROM budget_categories) + '
          '(SELECT COUNT(*) FROM budget_transactions) AS n',
        )
        .getSingle();
    return row.read<int>('n') > 0;
  }

  Future<void> _clear() async {
    await db.delete(db.budgetTransactionsTable).go();
    await db.delete(db.budgetCategoriesTable).go();
    await db.delete(db.budgetAccountsTable).go();
  }

  // ---- Notion CSV import ----------------------------------------------------

  /// Imports the Notion exports (any subset of the three, but transactions
  /// need categories). Throws [FormatException] before touching the data when
  /// a file is unreadable.
  Future<BudgetImportSummary> importNotionCsvs({
    String? accountsCsv,
    String? categoriesCsv,
    String? transactionsCsv,
  }) async {
    final parsed = parseBudgetCsvs(
      accountsCsv: accountsCsv,
      categoriesCsv: categoriesCsv,
      transactionsCsv: transactionsCsv,
    );
    final nowText = dateTimeToDb(DateTime.now())!;

    return db.transaction(() async {
      await _clear();

      final accountIds = <String, String>{};
      final rates = <String, double>{};
      for (final a in parsed.accounts) {
        final id = newId();
        accountIds[a.name] = id;
        rates[a.name] = a.rateToBase;
        await db
            .into(db.budgetAccountsTable)
            .insert(
              BudgetAccountsTableCompanion.insert(
                id: id,
                name: a.name,
                type: Value(a.type),
                currency: a.currency,
                rateToBase: Value(a.rateToBase),
                openingBalance: Value(a.openingBalance),
                createdAt: nowText,
                updatedAt: nowText,
              ),
            );
      }

      final categoryIds = [for (final _ in parsed.categories) newId()];
      for (var i = 0; i < parsed.categories.length; i++) {
        final c = parsed.categories[i];
        await db
            .into(db.budgetCategoriesTable)
            .insert(
              BudgetCategoriesTableCompanion.insert(
                id: categoryIds[i],
                name: c.name,
                isIncome: Value(c.isIncome),
                oneTime: Value(c.oneTime),
                unit: Value(c.unit.db),
                endDate: Value(dateTimeToDb(c.endDate)),
                price: Value(c.price),
                percent: Value(c.percent),
                frequencyMonths: Value(c.frequencyMonths),
                unitsPerMonth: Value(c.unitsPerMonth),
                accountCountId: Value(accountIds[c.accountCountName]),
                accountUseId: Value(accountIds[c.accountUseName]),
                createdAt: nowText,
                updatedAt: nowText,
              ),
            );
      }
      // Links last: a parent row may come after its children in the file.
      for (var i = 0; i < parsed.categories.length; i++) {
        final c = parsed.categories[i];
        if (c.parentIndex == null && c.percentSourceIndex == null) continue;
        await (db.update(
          db.budgetCategoriesTable,
        )..where((t) => t.id.equals(categoryIds[i]))).write(
          BudgetCategoriesTableCompanion(
            parentId: Value(
              c.parentIndex == null ? null : categoryIds[c.parentIndex!],
            ),
            countPercentOfId: Value(
              c.percentSourceIndex == null
                  ? null
                  : categoryIds[c.percentSourceIndex!],
            ),
          ),
        );
      }

      // Existing actions, matched by name + start (to the minute).
      String minuteKey(String name, DateTime start) {
        final s = dateTimeToDb(start)!;
        return '$name|${s.substring(0, 16)}';
      }

      final actionByKey = <String, String>{};
      final actionRows = await db
          .customSelect(
            'SELECT id, name, start_at FROM actions WHERE start_at IS NOT NULL',
          )
          .get();
      for (final r in actionRows) {
        final start = dateTimeFromDb(r.read<String>('start_at'))!;
        actionByKey.putIfAbsent(
          minuteKey(r.read<String>('name'), start),
          () => r.read<String>('id'),
        );
      }

      var linked = 0, notFound = 0;
      for (final t in parsed.transactions) {
        final c = parsed.categories[t.categoryIndex];
        final isAmount = c.unit == BudgetUnit.percentPerMonth;
        final useName = t.accountUseName ?? c.accountUseName;
        final countName = t.accountCountName ?? c.accountCountName;
        String? actionId;
        if (t.actionName != null) {
          actionId = actionByKey[minuteKey(t.actionName!, t.date)];
          if (actionId == null) {
            notFound++;
          } else {
            linked++;
          }
        }
        await db
            .into(db.budgetTransactionsTable)
            .insert(
              BudgetTransactionsTableCompanion.insert(
                id: newId(),
                name: Value(t.name),
                categoryId: Value(categoryIds[t.categoryIndex]),
                actionId: Value(actionId),
                occurredAt: dateTimeToDb(t.date)!,
                quantity: Value(t.quantity),
                unitPrice: Value(isAmount ? 0 : (t.price ?? c.price ?? 0)),
                isIncome: Value(c.isIncome),
                isAmount: Value(isAmount),
                accountCountId: Value(accountIds[countName]),
                accountUseId: Value(accountIds[useName]),
                rateCount: Value(t.rateCount ?? rates[countName]),
                rateInteract: Value(t.rateInteract ?? rates[useName]),
                createdAt: nowText,
                updatedAt: nowText,
              ),
            );
      }

      return BudgetImportSummary(
        accounts: parsed.accounts.length,
        categories: parsed.categories.length,
        transactions: parsed.transactions.length,
        linkedToActions: linked,
        actionsNotFound: notFound,
        skippedNoCategory: parsed.skippedNoCategory,
        skippedNoDate: parsed.skippedNoDate,
        skippedGroupCategory: parsed.skippedGroupCategory,
        unresolvedChildren: parsed.unresolvedChildren,
        unresolvedPercentSources: parsed.unresolvedPercentSources,
        currencyGuessed: [
          for (final a in parsed.accounts)
            if (a.currencyGuessed) a.name,
        ],
        ratesMissing: [
          for (final a in parsed.accounts)
            if (!a.rateFound) a.name,
        ],
        unknownAccounts: parsed.unknownAccounts,
        suspiciousRates: parsed.suspiciousRates,
      );
    });
  }

  // ---- JSON backup ----------------------------------------------------------

  /// The transactions with their EFFECTIVE date written into `occurred_at`
  /// (the linked action's start, if any), so a restore on another database
  /// keeps every date even where the action ids do not exist.
  Future<List<BudgetTransaction>> _transactionsWithEffectiveDate() async {
    final rows = await db
        .customSelect(
          'SELECT t.*, a.start_at AS action_start FROM budget_transactions t '
          'LEFT JOIN actions a ON a.id = t.action_id '
          'ORDER BY COALESCE(a.start_at, t.occurred_at), t.id',
          readsFrom: {db.budgetTransactionsTable, db.actionsTable},
        )
        .get();
    return [
      for (final r in rows)
        db.budgetTransactionsTable
            .map(r.data)
            .copyWith(
              occurredAt:
                  r.read<String?>('action_start') ??
                  r.read<String>('occurred_at'),
            ),
    ];
  }

  Future<String> exportJson() async {
    final settings = await BudgetService(db).settings();
    final accounts = await db.select(db.budgetAccountsTable).get();
    final categories = await db.select(db.budgetCategoriesTable).get();
    final transactions = await _transactionsWithEffectiveDate();
    return const JsonEncoder.withIndent('  ').convert({
      'format': budgetJsonFormat,
      'version': _budgetJsonVersion,
      'exportedAt': dateTimeToDb(DateTime.now()),
      'settings': {
        'base_currency': settings.baseCurrency,
        'period_months': settings.periodMonths,
        'tolerance': settings.tolerance,
      },
      'accounts': [for (final a in accounts) a.toJson()],
      'categories': [for (final c in categories) c.toJson()],
      'transactions': [for (final t in transactions) t.toJson()],
    });
  }

  /// True when [text] is a budget JSON backup.
  static bool looksLikeBackup(String text) {
    try {
      final data = jsonDecode(text);
      return data is Map && data['format'] == budgetJsonFormat;
    } on FormatException {
      return false;
    }
  }

  /// Restores a backup written by [exportJson], replacing all budget data and
  /// the budget settings. Throws [FormatException] for anything else.
  Future<BudgetImportSummary> importJson(String text) async {
    final Object? data;
    try {
      data = jsonDecode(text);
    } on FormatException {
      throw const FormatException('That file is not valid JSON.');
    }
    if (data is! Map || data['format'] != budgetJsonFormat) {
      throw const FormatException('That is not a LiveNow budget backup.');
    }
    final version = data['version'];
    if (version is! num) {
      throw const FormatException('That is not a LiveNow budget backup.');
    }
    if (version > _budgetJsonVersion) {
      throw const FormatException(
        'The backup comes from a newer version of the app.',
      );
    }
    final List<BudgetAccount> accounts;
    final List<BudgetCategory> categories;
    final List<BudgetTransaction> transactions;
    final BudgetSettings settings;
    try {
      final root = Map<String, dynamic>.from(data);
      List<T> list<T>(String key, T Function(Map<String, dynamic>) from) => [
        for (final e in (root[key] as List? ?? const []))
          from(Map<String, dynamic>.from(e as Map)),
      ];
      accounts = list('accounts', BudgetAccount.fromJson);
      categories = list('categories', BudgetCategory.fromJson);
      transactions = list('transactions', BudgetTransaction.fromJson);
      settings = BudgetService.settingsFromMap({
        for (final e in ((root['settings'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      });
    } on FormatException {
      rethrow;
    } on Object {
      // A wrong type or a missing field inside an otherwise valid JSON.
      throw const FormatException('That backup file is damaged.');
    }

    return db.transaction(() async {
      await _clear();
      for (final a in accounts) {
        await db.into(db.budgetAccountsTable).insert(a);
      }
      // Categories without their links first (a parent may follow its child).
      for (final c in categories) {
        await db
            .into(db.budgetCategoriesTable)
            .insert(
              c.copyWith(
                parentId: const Value(null),
                countPercentOfId: const Value(null),
              ),
            );
      }
      final ids = {for (final c in categories) c.id};
      for (final c in categories) {
        final parent = ids.contains(c.parentId) ? c.parentId : null;
        final source = ids.contains(c.countPercentOfId)
            ? c.countPercentOfId
            : null;
        if (parent == null && source == null) continue;
        await (db.update(
          db.budgetCategoriesTable,
        )..where((t) => t.id.equals(c.id))).write(
          BudgetCategoriesTableCompanion(
            parentId: Value(parent),
            countPercentOfId: Value(source),
          ),
        );
      }
      final existingActions =
          (await db.customSelect('SELECT id FROM actions').get())
              .map((r) => r.read<String>('id'))
              .toSet();
      var linked = 0;
      for (final t in transactions) {
        final keepAction = existingActions.contains(t.actionId);
        if (keepAction) linked++;
        await db
            .into(db.budgetTransactionsTable)
            .insert(
              t.copyWith(
                actionId: Value(keepAction ? t.actionId : null),
                categoryId: Value(
                  ids.contains(t.categoryId) ? t.categoryId : null,
                ),
              ),
            );
      }
      await BudgetService(db).saveSettings(settings);
      return BudgetImportSummary(
        accounts: accounts.length,
        categories: categories.length,
        transactions: transactions.length,
        linkedToActions: linked,
      );
    });
  }

  // ---- CSV export (the Notion layout) ---------------------------------------

  static String _csvCell(String raw) {
    final v = guardCsvCell(raw);
    return v.contains(RegExp(r'[",\n\r]'))
        ? '"${v.replaceAll('"', '""')}"'
        : v;
  }

  static String _csv(List<List<String>> rows) =>
      '${rows.map((r) => r.map(_csvCell).join(',')).join('\n')}\n';

  static String _num(double? v) {
    if (v == null) return '';
    final s = v.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
    return s.isEmpty ? '0' : s;
  }

  /// The calculated "Total Income (Interactional Account)": the signed amount
  /// in the interacting account's currency, with a COMMA as decimal separator
  /// (two decimals for fiat, full precision for crypto-like currencies); empty
  /// when it cannot be converted. The importer ignores this column.
  static String _interactTotal(
    BudgetTransaction t,
    Map<String, BudgetAcct> accountsById,
  ) {
    final amount = transactionInteractAmount(
      BudgetTx(
        id: t.id,
        date: dateTimeFromDb(t.occurredAt) ?? DateTime.utc(1970),
        quantity: t.quantity,
        unitPrice: t.unitPrice,
        isIncome: t.isIncome,
        isAmount: t.isAmount,
        accountCountId: t.accountCountId,
        accountUseId: t.accountUseId,
        rateCount: t.rateCount,
        rateInteract: t.rateInteract,
      ),
      accountsById,
    );
    if (amount == null) return '';
    final fiat = (accountsById[t.accountUseId]?.rateToBase ?? 1) > 0.5;
    final text = fiat
        ? amount.toStringAsFixed(2)
        : amount.toStringAsFixed(10).replaceFirst(RegExp(r'\.?0+$'), '');
    return text.replaceAll('.', ',');
  }

  static String _day(DateTime utc) {
    final l = tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(l.day)}/${p(l.month)}/${l.year}';
  }

  static String _dayTime(DateTime utc) {
    final l = tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));
    return '${_day(utc)} ${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  /// The three CSVs in the layout of the Notion exports, so they work as
  /// import templates (accounts gain Currency / Rate / Opening balance
  /// columns the Notion export lacks; transactions gain the calculated Total
  /// Income (Interactional Account)). File name -> text.
  Future<Map<String, String>> exportCsvs() async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    final categories = await db.select(db.budgetCategoriesTable).get();
    final accountName = {for (final a in accounts) a.id: a.name};
    final accountsById = {
      for (final a in accounts)
        a.id: BudgetAcct(
          id: a.id,
          currency: a.currency,
          rateToBase: a.rateToBase,
          openingBalance: a.openingBalance,
        ),
    };
    final categoryName = {for (final c in categories) c.id: c.name};
    final childrenOf = <String, List<String>>{};
    for (final c in categories) {
      final parent = c.parentId;
      if (parent != null) (childrenOf[parent] ??= []).add(c.name);
    }

    final accountsCsv = _csv([
      ['Name', 'Type', 'Currency', 'Rate to base', 'Opening balance'],
      for (final a in accounts)
        [
          a.name,
          a.type ?? '',
          a.currency,
          _num(a.rateToBase),
          _num(a.openingBalance),
        ],
    ]);

    final categoriesCsv = _csv([
      [
        'Category name',
        'Unit of measure',
        '👛 Account to use',
        '👛 Account to count',
        'Count percent of (text)',
        'Consists of (text)',
        'Price per Unit',
        'Frequency',
        'Units per Month (Plan)',
        'End Date',
        'One-time',
        'Income',
      ],
      for (final c in categories)
        () {
          final children = childrenOf[c.id] ?? const <String>[];
          final unit = BudgetUnit.fromDb(c.unit);
          final end = dateTimeFromDb(c.endDate);
          return [
            c.name,
            switch (unit) {
              BudgetUnit.piece => 'Piece',
              BudgetUnit.kilogram => 'Kilogram',
              BudgetUnit.month => 'Month',
              BudgetUnit.percentPerMonth => 'Percent per Month',
            },
            accountName[c.accountUseId] ?? '',
            accountName[c.accountCountId] ?? '',
            categoryName[c.countPercentOfId] ?? '',
            children.join(','),
            children.isNotEmpty
                ? '-1'
                : _num(
                    unit == BudgetUnit.percentPerMonth ? c.percent : c.price,
                  ),
            _num(c.frequencyMonths),
            _num(c.unitsPerMonth),
            end == null ? '' : _day(end),
            c.oneTime ? 'Yes' : 'No',
            c.isIncome ? 'Yes' : 'No',
          ];
        }(),
    ]);

    final actionNames = {
      for (final r
          in await db.customSelect('SELECT id, name FROM actions').get())
        r.read<String>('id'): r.read<String>('name'),
    };
    final transactions = await _transactionsWithEffectiveDate();
    final transactionsCsv = _csv([
      [
        'Currency to interact',
        'Currency to count',
        'Category',
        'Action',
        'Transaction Name',
        'Quantity',
        'Price',
        'Date',
        'Euo Rate (Count)',
        'Euo Rate (Interact)',
        'Total Income (Interactional Account)',
      ],
      for (final t in transactions)
        [
          accountName[t.accountUseId] ?? '',
          accountName[t.accountCountId] ?? '',
          categoryName[t.categoryId] ?? '',
          actionNames[t.actionId] ?? '',
          t.name,
          _num(t.quantity),
          t.isAmount ? '' : _num(t.unitPrice),
          _dayTime(dateTimeFromDb(t.occurredAt) ?? DateTime.utc(1970)),
          _num(t.rateCount),
          _num(t.rateInteract),
          _interactTotal(t, accountsById),
        ],
    ]);

    return {
      'Budget - Accounts.csv': accountsCsv,
      'Budget - Categories.csv': categoriesCsv,
      'Budget - Transactions.csv': transactionsCsv,
    };
  }
}
