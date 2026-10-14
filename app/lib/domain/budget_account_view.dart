import 'budget_rules.dart' show round2;
import 'name_sort.dart' show compareIgnoringEmoji;

/// Pure sort rules of the Budget "Accounts" list (same shape as
/// `budget_tx_view_rules.dart`; the UI only edits these values).

enum AccountSortField {
  mainBalance('Main balance'),
  balance('Balance'),
  type('Type'),
  rate('Rate'),
  name('Name');

  final String label;
  const AccountSortField(this.label);
}

/// One level of the waterfall sort.
class AccountSortKey {
  final AccountSortField field;
  final bool ascending;

  const AccountSortKey(this.field, {this.ascending = true});

  AccountSortKey toggled() => AccountSortKey(field, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is AccountSortKey &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// The default order: the biggest balance in the main currency first.
const List<AccountSortKey> kDefaultAccountSort = [
  AccountSortKey(AccountSortField.mainBalance, ascending: false),
];

/// [balance] in the main currency; null when the account has no usable rate
/// (never NaN or infinity). `rateToBase` is units of the account currency per
/// 1 main-currency unit.
double? accountMainBalance(double balance, double rateToBase) =>
    rateToBase > 0 ? round2(balance / rateToBase) : null;

/// What the sort needs from one account.
class AccountSortInput {
  final String id;
  final String name;
  final String? type;
  final double rate;
  final double balance;
  final double? mainBalance;

  const AccountSortInput({
    required this.id,
    required this.name,
    this.type,
    required this.rate,
    required this.balance,
    this.mainBalance,
  });
}

/// [items] ordered by the waterfall [keys]; a missing value (no type, no main
/// balance) always goes last whatever the direction, ties fall back to the name.
List<AccountSortInput> sortAccounts(
  Iterable<AccountSortInput> items,
  List<AccountSortKey> keys,
) {
  int cmpNullable<T extends Comparable>(T? a, T? b, bool asc) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return asc ? c : -c;
  }

  int compare(AccountSortInput a, AccountSortInput b) {
    for (final k in keys) {
      final c = switch (k.field) {
        AccountSortField.mainBalance => cmpNullable<num>(
          a.mainBalance,
          b.mainBalance,
          k.ascending,
        ),
        AccountSortField.balance => cmpNullable<num>(
          a.balance,
          b.balance,
          k.ascending,
        ),
        AccountSortField.rate => cmpNullable<num>(a.rate, b.rate, k.ascending),
        AccountSortField.type => cmpNullable<String>(
          (a.type ?? '').trim().isEmpty ? null : a.type!.toLowerCase(),
          (b.type ?? '').trim().isEmpty ? null : b.type!.toLowerCase(),
          k.ascending,
        ),
        AccountSortField.name => k.ascending
            ? compareIgnoringEmoji(a.name, b.name)
            : compareIgnoringEmoji(b.name, a.name),
      };
      if (c != 0) return c;
    }
    return compareIgnoringEmoji(a.name, b.name);
  }

  return [...items]..sort(compare);
}
