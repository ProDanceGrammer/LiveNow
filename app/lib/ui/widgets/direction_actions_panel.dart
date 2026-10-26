import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart' show ActionRow;
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../time_format.dart';
import '../undo.dart';
import '../urgency_colors.dart';
import 'action_editor.dart';
import 'action_picker_dialog.dart';
import 'app_toast.dart' show rootOverlayOf;

/// Linked actions ordered by pure distance from now (|start - now|, past and
/// future interleaved); actions without a start come last, then by name.
List<ActionRow> sortLinkedActionsByDistance(
  List<ActionRow> actions,
  DateTime nowUtc,
) {
  final keyed = [
    for (final a in actions)
      (a, dateTimeFromDb(a.startAt)?.difference(nowUtc).abs()),
  ];
  keyed.sort((x, y) {
    final dx = x.$2, dy = y.$2;
    if (dx != null && dy != null) {
      final c = dx.compareTo(dy);
      if (c != 0) return c;
    } else if (dx != null) {
      return -1;
    } else if (dy != null) {
      return 1;
    }
    return x.$1.name.toLowerCase().compareTo(y.$1.name.toLowerCase());
  });
  return [for (final k in keyed) k.$1];
}

/// The actions linked to one growth direction, nearest in time first: a bordered
/// list shown beside the direction's settings in its edit dialog (the same
/// layout as a category's transactions); a tap opens the action, the cross
/// unlinks it, `+` links another one and the second button creates a new action
/// already linked to this direction.
///
/// [scrollable] false (a phone, where the dialog scrolls as a whole) lists the
/// nearest [kPanelPhoneLimit] rows without an own scroll view.
class DirectionActionsPanel extends ConsumerWidget {
  const DirectionActionsPanel({
    super.key,
    required this.metricId,
    this.scrollable = true,
  });

  final String metricId;
  final bool scrollable;

  static const kPanelPhoneLimit = 30;

  Future<void> _link(BuildContext context, WidgetRef ref, Set<String> ids) async {
    final service = ref.read(metricServiceProvider);
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final picked = await ActionPickerDialog.show(context, excludeIds: ids);
    if (picked == null) return;
    await service.linkAction(picked.id, metricId);
    offerUndo(
      overlay,
      history,
      'Linked "${picked.name}"',
      () => service.unlinkAction(picked.id, metricId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final nowUtc = DateTime.now().toUtc();
    final sorted = sortLinkedActionsByDistance([
      for (final (id, action)
          in ref.watch(metricLinkedActionsProvider).value ??
              const <(String, ActionRow)>[])
        if (id == metricId) action,
    ], nowUtc);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Linked actions (${sorted.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const ValueKey('direction-link-action'),
            icon: const Icon(Icons.add),
            tooltip: 'Link an action',
            visualDensity: VisualDensity.compact,
            onPressed: () => _link(context, ref, {for (final a in sorted) a.id}),
          ),
          // A brand-new action already linked to this direction. Not when
          // dialogs are stacked three deep (action -> direction -> action ->
          // ... must end somewhere).
          if (openStackedDialogCount < 3)
            IconButton(
              key: const ValueKey('direction-new-action'),
              icon: const Icon(Icons.playlist_add),
              tooltip: 'New action for this direction',
              visualDensity: VisualDensity.compact,
              onPressed: () => ActionEditorDialog.show(
                context,
                initialMetricIds: {metricId},
              ),
            ),
        ],
      ),
    );

    Widget tile(ActionRow a) => _LinkedActionTile(
      key: ValueKey('linked-action-${a.id}'),
      action: a,
      metricId: metricId,
      nowUtc: nowUtc,
    );

    final Widget body = sorted.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No linked actions yet.'),
          )
        : scrollable
        ? ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: sorted.length,
            itemBuilder: (_, i) => tile(sorted[i]),
          )
        : Column(
            children: [
              for (var i = 0; i < sorted.length && i < kPanelPhoneLimit; i++)
                tile(sorted[i]),
              if (sorted.length > kPanelPhoneLimit)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('… and ${sorted.length - kPanelPhoneLimit} more'),
                ),
              const SizedBox(height: 6),
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, if (scrollable) Expanded(child: body) else body],
        ),
      ),
    );
  }
}

/// One linked action: name, short schedule, unlink. Tinted by the action's
/// urgency like the lists (muted when done). A plain `InkWell` row, not a dense
/// `ListTile` (its fixed minimum height overflowed in narrow panels).
class _LinkedActionTile extends ConsumerWidget {
  const _LinkedActionTile({
    super.key,
    required this.action,
    required this.metricId,
    required this.nowUtc,
  });

  final ActionRow action;
  final String metricId;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = action;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final urgency = ref.watch(
      actionUrgencyProvider.select((m) => m[a.id]),
    );
    final tint = urgency == null
        ? null
        : (a.done
              ? urgencyColorsMuted(urgency, dark: dark)
              : urgencyColors(urgency, dark: dark));
    final fg = tint?.fg;
    final schedule = formatShortSchedule(
      dateTimeFromDb(a.startAt),
      dateTimeFromDb(a.endAt),
      isAllDay: a.isAllDay,
      nowUtc: nowUtc,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: tint?.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openActionById(context, ref, a.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg),
                    ),
                    if (schedule != null)
                      Text(
                        schedule,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              (fg ?? Theme.of(context).colorScheme.onSurface)
                                  .withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('unlink-action-${a.id}'),
                icon: Icon(Icons.close, size: 16, color: fg),
                tooltip: 'Unlink',
                visualDensity: VisualDensity.compact,
                onPressed: () => ref
                    .read(metricServiceProvider)
                    .unlinkAction(a.id, metricId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
