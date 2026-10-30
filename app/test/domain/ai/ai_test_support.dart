import 'package:drift/native.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';

AppDatabase memoryDb() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

/// Small helpers to build a budget tree in tests.
class Seed {
  Seed(this.db) : budget = BudgetService(db);
  final AppDatabase db;
  final BudgetService budget;

  Future<String> account(String name, {String currency = 'TRY'}) =>
      budget.saveAccount(name: name, currency: currency, rateToBase: 40);

  Future<String> group(String name, {String? parentId}) =>
      budget.saveCategory(CategoryInput(name: name, parentId: parentId));

  Future<String> leaf(
    String name, {
    required double price,
    String? parentId,
    BudgetUnit unit = BudgetUnit.kilogram,
    String? count,
    String? use,
  }) => budget.saveCategory(
    CategoryInput(
      name: name,
      unit: unit,
      price: price,
      parentId: parentId,
      accountCountId: count,
      accountUseId: use,
    ),
  );

  Future<BudgetCategory> cat(String id) => (db.select(
    db.budgetCategoriesTable,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<List<BudgetCategory>> children(String id) => (db.select(
    db.budgetCategoriesTable,
  )..where((t) => t.parentId.equals(id))).get();
}
