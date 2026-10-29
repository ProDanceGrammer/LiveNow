import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/dependency_service.dart';
import '../../domain/diary_transfer.dart';
import '../../domain/done_rule.dart';
import '../providers.dart';
import '../undo.dart';
import '../work_hours.dart';
import 'app_toast.dart';
import 'notes_editor.dart';

/// The "What is done?" control in an action's Notes toolbar: a small "Blocks"
/// field (codes found in action names, e.g. `KBT, Target:Jeremy`; empty = every
/// tagged action) and the button that
///  - finds the finished actions of the previous working day carrying those
///    tags,
///  - appends them to the Notes as a "What is done?" checklist grouped by tag,
///  - and makes every one of them a Previous action of this action.
/// The codes are saved on the action (`result_note`, a column nothing else uses).
class WhatIsDoneControl extends ConsumerStatefulWidget {
  const WhatIsDoneControl({
    super.key,
    required this.actionId,
    required this.notesKey,
    this.initialBlocks,
  });

  final String actionId;
  final GlobalKey<NotesEditorState> notesKey;

  /// The saved codes. When the parent passes a NEW value (the row was changed
  /// elsewhere, e.g. by another dialog of the same action) the field follows it,
  /// unless the user has typed something of their own.
  final String? initialBlocks;

  @override
  ConsumerState<WhatIsDoneControl> createState() => WhatIsDoneControlState();
}

class WhatIsDoneControlState extends ConsumerState<WhatIsDoneControl> {
  late final TextEditingController _blocks = TextEditingController(
    text: widget.initialBlocks ?? '',
  );

  /// What the database holds, as far as this control knows (trimmed).
  late String _saved;

  @override
  void initState() {
    super.initState();
    _saved = (widget.initialBlocks ?? '').trim();
  }

  /// True when the field holds codes that are not written yet.
  bool get isDirty => _blocks.text.trim() != _saved;

  @override
  void didUpdateWidget(WhatIsDoneControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.initialBlocks ?? '').trim();
    if (next == (oldWidget.initialBlocks ?? '').trim()) return;
    // Untouched field: show the new value; a typed one is kept.
    if (!isDirty && _blocks.text != next) _blocks.text = next;
    _saved = next;
  }

  @override
  void dispose() {
    _blocks.dispose();
    super.dispose();
  }

  /// Writes the codes when they changed (also part of the action form's Save).
  Future<void> saveBlocks() => isDirty ? _saveBlocks() : Future.value();

  Future<void> _saveBlocks() {
    final db = ref.read(databaseProvider);
    final text = _blocks.text.trim();
    _saved = text;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(widget.actionId))).write(
      ActionsTableCompanion(resultNote: Value(text.isEmpty ? null : text)),
    );
  }

  Future<void> _run() async {
    // Everything that needs `context`/`ref` is read before the first await.
    final overlay = rootOverlayOf(context);
    final db = ref.read(databaseProvider);
    final deps = ref.read(dependencyServiceProvider);
    final history = ref.read(undoHistoryProvider.notifier);
    final weekdays = ref.read(workHoursProvider).workingWeekdays;
    final notes = widget.notesKey.currentState;
    final codes = parseBlockCodes(_blocks.text);
    final location = tz.getLocation(AppSettings.timeZoneName);
    if (notes == null) return;

    await _saveBlocks();
    final self = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(widget.actionId))).getSingleOrNull();
    if (self == null) return;
    final reference = dateTimeFromDb(self.startAt) ?? DateTime.now().toUtc();
    final range = previousWorkingDay(reference, weekdays, location);
    if (range == null) {
      showInfoToast(overlay, 'Pick at least one working day in Settings.');
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final rows =
        await (db.select(db.actionsTable)..where(
              (t) =>
                  t.isAllDay.equals(false) &
                  t.id.isNotValue(widget.actionId) &
                  t.startAt.isBiggerOrEqualValue(
                    dateTimeToDb(range.startUtc)!,
                  ) &
                  t.startAt.isSmallerThanValue(dateTimeToDb(range.endUtc)!),
            ))
            .get();
    final candidates = <DiaryAction>[
      for (final r in rows)
        if (isDoneBefore(
          startAt: dateTimeFromDb(r.startAt),
          endAt: dateTimeFromDb(r.endAt),
          isAllDay: r.isAllDay,
          done: r.done,
          nowUtc: nowUtc,
        ))
          DiaryAction(
            id: r.id,
            name: r.name,
            startAt: dateTimeFromDb(r.startAt)!,
          ),
    ];
    final diary = buildDiary(candidates, codes);
    final day = tz.TZDateTime.from(range.startUtc, location);
    final label = '${day.day}.${day.month}.${day.year}';
    if (diary.isEmpty) {
      showInfoToast(
        overlay,
        codes.isEmpty
            ? 'No finished tagged actions on $label.'
            : 'No finished actions with these blocks on $label.',
      );
      return;
    }

    await notes.appendChecklistSection('What is done?', [
      for (final g in diary.groups) (g.tag, [for (final i in g.items) i.text]),
    ]);

    // Previous actions: only the links that are new can be undone.
    final existing = {
      for (final d in await (db.select(
        db.actionDependenciesTable,
      )..where((t) => t.successorId.equals(widget.actionId))).get())
        d.predecessorId,
    };
    final added = <String>[];
    for (final id in diary.matchedIds) {
      if (existing.contains(id)) continue;
      try {
        await deps.addDependency(
          predecessorId: id,
          successorId: widget.actionId,
        );
        added.add(id);
      } on DependencyCycleException {
        // Would close a loop: that action simply is not linked.
      }
    }

    offerUndo(overlay, history, 'Added "What is done?" for $label', () async {
      notes.undoLastEdit();
      for (final id in added) {
        await deps.removeDependency(
          predecessorId: id,
          successorId: widget.actionId,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('diary-blocks'),
              controller: _blocks,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText:
                    'Blocks, e.g. KBT, Target:Jeremy (empty = all tagged)',
                hintStyle: TextStyle(fontSize: 12),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _saveBlocks(),
              onTapOutside: (_) => _saveBlocks(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const ValueKey('diary-transfer'),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
            tooltip: 'List what was done during previous working day',
            onPressed: _run,
            icon: Image.asset(
              'assets/icons/what_is_done.png',
              width: 20,
              height: 20,
              // The glyph is black on transparent: tint it like any icon.
              color: IconTheme.of(context).color,
              semanticLabel: 'What is done?',
            ),
          ),
        ],
      ),
    );
  }
}
