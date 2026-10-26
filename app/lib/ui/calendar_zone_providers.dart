import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/calendar_zone_service.dart';
import 'providers.dart';

final calendarZoneServiceProvider = Provider<CalendarZoneService>(
  (ref) => CalendarZoneService(ref.watch(databaseProvider)),
);

/// The extra timezones beside the calendar's hours, in order, live.
final calendarZonesProvider = StreamProvider<List<CalendarZone>>(
  (ref) => ref.watch(calendarZoneServiceProvider).watch(),
);
