import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../domain/form_apply_service.dart';
import '../domain/form_service.dart';
import 'providers.dart';

final formServiceProvider = Provider<FormService>(
  (ref) => FormService(ref.watch(databaseProvider)),
);

final formApplyServiceProvider = Provider<FormApplyService>(
  (ref) => FormApplyService(ref.watch(databaseProvider)),
);

/// Every form, by name, live.
final formsProvider = StreamProvider.autoDispose<List<FormItem>>(
  (ref) => ref.watch(formServiceProvider).watch(),
);

/// The form used last (the picker offers it first, and skips itself when there
/// is only one form).
final lastFormIdProvider = StateProvider<String?>((ref) => null);
