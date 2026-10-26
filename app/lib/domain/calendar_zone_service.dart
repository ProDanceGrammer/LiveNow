import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/text_rules.dart';
import '../core/time_codec.dart';
import '../core/zone_info.dart';
import '../data/database.dart';

/// At most this many extra timezones sit beside the calendar's hours.
const int kMaxCalendarZones = 3;

class CalendarZoneLimitException implements Exception {
  const CalendarZoneLimitException();

  @override
  String toString() => 'At most $kMaxCalendarZones extra timezones.';
}

/// The extra calendar timezones (`calendar_zones`, synced).
class CalendarZoneService {
  CalendarZoneService(this.db);

  final AppDatabase db;

  Stream<List<CalendarZone>> watch() =>
      (db.select(db.calendarZonesTable)..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
          .watch();

  /// Adds [tz] with [label] (blank = flag + city). Throws
  /// [CalendarZoneLimitException] past [kMaxCalendarZones]; a zone that is
  /// already there is not added twice (returns its id).
  Future<String> add(String tz, {String? label}) {
    return db.transaction(() async {
      final rows = await db.select(db.calendarZonesTable).get();
      final same = rows.where((r) => r.tz == tz).firstOrNull;
      if (same != null) return same.id;
      if (rows.length >= kMaxCalendarZones) {
        throw const CalendarZoneLimitException();
      }
      final id = newId();
      final now = dateTimeToDb(DateTime.now())!;
      final clean = cleanName(label ?? '', what: 'zone name');
      await db
          .into(db.calendarZonesTable)
          .insert(
            CalendarZonesTableCompanion.insert(
              id: id,
              tz: tz,
              label: Value(clean.isEmpty ? zoneDefaultLabel(tz) : clean),
              position: Value(rows.length),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    });
  }

  /// Renames a zone's column header; blank = the default (flag + city).
  Future<void> rename(String id, String label) async {
    final row = await (db.select(
      db.calendarZonesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final clean = cleanName(label, what: 'zone name');
    await (db.update(db.calendarZonesTable)..where((t) => t.id.equals(id)))
        .write(
          CalendarZonesTableCompanion(
            label: Value(clean.isEmpty ? zoneDefaultLabel(row.tz) : clean),
            updatedAt: Value(dateTimeToDb(DateTime.now())!),
          ),
        );
  }

  /// Removes a zone; returns the row so Undo can put it back with [restore].
  Future<CalendarZone?> remove(String id) async {
    final row = await (db.select(
      db.calendarZonesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(db.calendarZonesTable)..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> restore(CalendarZone row) =>
      db.into(db.calendarZonesTable).insertOnConflictUpdate(row);
}
