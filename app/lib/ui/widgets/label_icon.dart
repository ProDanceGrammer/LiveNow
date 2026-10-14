import 'package:flutter/material.dart';

/// An icon that stands for a WORD: hover (Windows) or tap (touch) shows the
/// word, and screen readers read it. Used where a label would take room (the
/// Budget's Counting / Interactional / Main, Income / Expense).
class LabelIcon extends StatelessWidget {
  const LabelIcon(
    this.icon,
    this.name, {
    super.key,
    this.color,
    this.size = 18,
  });

  final IconData icon;
  final String name;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: name,
    child: Tooltip(
      message: name,
      triggerMode: TooltipTriggerMode.tap,
      child: Icon(icon, size: size, color: color),
    ),
  );
}

/// The three ways a transaction's amount is read.
enum TxValue {
  /// In the currency of the account the category counts in: cash.
  counting('Counting', Icons.payments_outlined),

  /// In the currency of the account the money moves through: a finger tapping
  /// a screen (the card / app that was used).
  interactional('Interactional', Icons.touch_app_outlined),

  /// In the main currency: a star.
  main('Main', Icons.star_rounded);

  final String label;
  final IconData icon;
  const TxValue(this.label, this.icon);
}

class TxValueIcon extends StatelessWidget {
  const TxValueIcon(this.value, {super.key, this.color, this.size = 18});

  final TxValue value;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => LabelIcon(
    value.icon,
    value.label,
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    size: size,
  );
}

/// Income = a green arrow into the pocket, Expense = a red arrow out of it: the
/// same arrows the Categories rows use. [color] overrides (on a tinted tile).
class IncomeExpenseIcon extends StatelessWidget {
  const IncomeExpenseIcon(
    this.isIncome, {
    super.key,
    this.size = 16,
    this.color,
  });

  final bool isIncome;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => LabelIcon(
    isIncome ? Icons.south_west : Icons.north_east,
    isIncome ? 'Income' : 'Expense',
    color:
        color ??
        (isIncome ? Colors.green : Theme.of(context).colorScheme.error),
    size: size,
  );
}
