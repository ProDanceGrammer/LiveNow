// Rules for the free text a person types as a NAME (action, direction,
// category, template, form ...), applied at the service boundary so that no
// path (editor, import, plan, sync-independent code) stores a name the rest of
// the app cannot handle.

/// The longest name, counted in characters (code points).
const int kMaxNameLength = 500;

/// A name the app refuses. [message] is friendly enough to show in a toast.
class InvalidNameException implements Exception {
  const InvalidNameException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// [s] without NUL and the other C0 control characters (tabs and line breaks
/// stay), DEL, and without lone UTF-16 surrogates (they cannot be encoded as
/// UTF-8 and would come back as U+FFFD). Valid surrogate PAIRS (emoji) stay.
String stripUnsafeText(String s) {
  var clean = true;
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (_isBadUnit(u) || _isSurrogate(u)) {
      clean = false;
      break;
    }
  }
  if (clean) return s;
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (_isBadUnit(u)) continue;
    if (_isHigh(u)) {
      if (i + 1 < s.length && _isLow(s.codeUnitAt(i + 1))) {
        out.writeCharCode(u);
        out.writeCharCode(s.codeUnitAt(i + 1));
        i++;
      }
      continue; // a lone high surrogate
    }
    if (_isLow(u)) continue; // a lone low surrogate
    out.writeCharCode(u);
  }
  return out.toString();
}

/// A name ready to store: unsafe characters removed, trimmed. Throws
/// [InvalidNameException] when it is longer than [kMaxNameLength] characters.
/// An empty result is returned as '' (callers decide whether that is allowed).
String cleanName(String raw, {String what = 'name'}) {
  final s = stripUnsafeText(raw).trim();
  // Fast path: UTF-16 length is never smaller than the character count.
  if (s.length > kMaxNameLength && s.runes.length > kMaxNameLength) {
    throw InvalidNameException(
      'That $what is too long (more than $kMaxNameLength characters).',
    );
  }
  return s;
}

/// A form-field validator for a name: null = fine, else the message to show.
String? nameFieldError(String? v, {String required = 'Required'}) {
  final s = v ?? '';
  if (s.trim().isEmpty) return required;
  if (s.length > kMaxNameLength && s.runes.length > kMaxNameLength) {
    return 'Too long (at most $kMaxNameLength characters)';
  }
  return null;
}

/// Like [cleanName] but an empty result is refused too.
String requireName(String raw, {String what = 'name'}) {
  final s = cleanName(raw, what: what);
  if (s.isEmpty) throw InvalidNameException('The $what cannot be empty.');
  return s;
}

bool _isBadUnit(int u) =>
    u == 0x7f || (u < 0x20 && u != 0x09 && u != 0x0a && u != 0x0d);
bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;
bool _isSurrogate(int u) => u >= 0xD800 && u <= 0xDFFF;

// ---- spreadsheet formula guard (CSV export) ---------------------------------

const _formulaStarts = '=+-@\t\r';

/// True when a spreadsheet would read [s] as a formula: it starts (after any
/// leading apostrophes) with `= + - @`, a tab or a CR, and is not simply a
/// number.
bool csvNeedsGuard(String s) {
  var i = 0;
  while (i < s.length && s[i] == "'") {
    i++;
  }
  if (i >= s.length) return false;
  if (!_formulaStarts.contains(s[i])) return false;
  return !_plainNumber.hasMatch(s.substring(i));
}

/// A number as spreadsheets and our exports write it: sign, digits, `.` `,`
/// and spaces as separators, optional exponent ("-10,00", "+1 000,50").
final _plainNumber = RegExp(r'^[+-]?[\d.,\s]*\d(?:[eE][+-]?\d+)?$');

/// The text to WRITE into an exported CSV cell: a formula-looking value gets a
/// leading apostrophe (the spreadsheet then shows it as plain text).
String guardCsvCell(String s) => csvNeedsGuard(s) ? "'$s" : s;

/// The reverse, applied to cells READ from a CSV: exactly undoes
/// [guardCsvCell], so an export followed by an import returns the same text.
String unguardCsvCell(String s) =>
    s.startsWith("'") && csvNeedsGuard(s.substring(1)) ? s.substring(1) : s;
