/// How long each job has waited for an unreachable local AI service (the
/// hub's OCR service or model server), counting only time the hub was running
/// and trying.
///
/// The hub retries a waiting job with a back-off of at most a few minutes, so
/// a longer gap between two reports means the hub or the PC was off or asleep:
/// such a gap counts as only [maxGap]. Kept in memory on purpose: after a hub
/// restart a job starts waiting from zero (the service is started again first).
class ServiceWaits {
  ServiceWaits({
    this.maxGap = const Duration(minutes: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration maxGap;
  final DateTime Function() _clock;
  final _last = <String, DateTime>{};
  final _waited = <String, Duration>{};

  /// Records one more failed try of [jobId]; returns its total waiting time.
  Duration report(String jobId) {
    final now = _clock();
    final last = _last[jobId];
    var total = _waited[jobId] ?? Duration.zero;
    if (last != null) {
      var gap = now.difference(last);
      if (gap.isNegative) gap = Duration.zero;
      if (gap > maxGap) gap = maxGap;
      total += gap;
    }
    _last[jobId] = now;
    _waited[jobId] = total;
    return total;
  }

  /// The job ran, failed for good or was retried: forget its waiting time.
  void clear(String jobId) {
    _last.remove(jobId);
    _waited.remove(jobId);
  }
}

/// A job could not run because a local AI service is unreachable; it was put
/// back to wait. The hub's worker reacts by starting the OCR service (when
/// [ocr]) and backing off before the next try.
class AiServiceWait implements Exception {
  const AiServiceWait({required this.ocr, required this.message});

  /// True for the OCR service, false for the model server.
  final bool ocr;
  final String message;

  @override
  String toString() =>
      'AiServiceWait: ${ocr ? 'OCR service' : 'model server'} unreachable: $message';
}
