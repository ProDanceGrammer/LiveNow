// Errors every service can raise about the DATA (not about what was typed).

/// The row an edit or a delete was aimed at is gone (deleted on this or another
/// device while an editor was open). Nothing was written; [message] is friendly
/// enough for a toast.
class MissingRowException implements Exception {
  const MissingRowException(this.message);
  final String message;

  @override
  String toString() => message;
}
