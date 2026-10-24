// Limits for the numbers a person types (prices, quantities, rates, targets),
// applied at the service boundary: a value that is NaN, infinite or so large
// that sums and products overflow would poison every total it touches.

/// The largest magnitude accepted for a typed amount. Far above any real
/// price, small enough that price x quantity and sums of thousands of them
/// stay exact to the cent.
const double kMaxNumber = 1e12;

/// The longest manual duration (10 years), in minutes.
const int kMaxEstimatedMinutes = 60 * 24 * 365 * 10;

/// A number the app refuses. It IS an [ArgumentError] (older callers expect
/// one) whose text is friendly enough for a toast.
class InvalidNumberException extends ArgumentError {
  InvalidNumberException(super.message);

  String get text => message as String;

  @override
  String toString() => text;
}

/// [v] when it is a usable number, with `-0` normalised to `0`; else throws
/// [InvalidNumberException] naming [what]. [positive] demands `> 0`,
/// [nonZero] demands `!= 0` (a negative value stays allowed, e.g. a refund).
double checkNumber(
  double v,
  String what, {
  bool positive = false,
  bool nonZero = false,
  double min = -kMaxNumber,
  double max = kMaxNumber,
}) {
  if (v.isNaN || v.isInfinite) {
    throw InvalidNumberException('The $what is not a valid number.');
  }
  if (positive && !(v > 0)) {
    throw InvalidNumberException('The $what must be above 0.');
  }
  if (nonZero && v == 0) {
    throw InvalidNumberException('The $what cannot be 0.');
  }
  if (v < min || v > max) {
    throw InvalidNumberException('The $what is out of range.');
  }
  return v == 0 ? 0.0 : v;
}

/// [checkNumber] for an optional value.
double? checkNumberOrNull(
  double? v,
  String what, {
  bool positive = false,
  bool nonZero = false,
  double min = -kMaxNumber,
  double max = kMaxNumber,
}) => v == null
    ? null
    : checkNumber(
        v,
        what,
        positive: positive,
        nonZero: nonZero,
        min: min,
        max: max,
      );
