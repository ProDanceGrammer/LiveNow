import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/action_import_service.dart';
import '../current_icons.dart';
import '../layout.dart';
import '../providers.dart';
import '../widgets/action_import_summary_dialog.dart';
import '../views/all_actions_view.dart';
import '../views/calendar_view.dart';
import '../views/current_actions_view.dart';
import '../widgets/glass.dart';

/// Asks the user for the Notion actions export and returns its text (null =
/// cancelled). A provider so tests can replace the native file dialog.
final actionsCsvPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    return file?.readAsString();
  },
);

final actionImportServiceProvider = Provider<ActionImportService>(
  (ref) => ActionImportService(ref.watch(databaseProvider)),
);

/// The views inside the Actions section, in switch order.
enum ActionsSub {
  current('Current Actions', 'Current Actions'),
  calendar('Calendar', 'Calendar'),
  all('All', 'All Actions');

  const ActionsSub(this.label, this.title);

  /// Tab text.
  final String label;

  /// Tab text on a phone (shorter: three tabs share the width).
  String get phoneLabel => this == current ? 'Current' : label;

  /// Page (AppBar) title while this view is shown.
  final String title;
}

/// The Actions section: a compact glass switch on top and either the Current
/// Actions board or the Calendar below it. Like the shell's sections, a
/// sub-view is built the first time it is shown and then kept alive hidden
/// (no painting, no focus). The swap is instant (no animation).
class ActionsSection extends ConsumerStatefulWidget {
  const ActionsSection({super.key, required this.sub, required this.onChanged});

  final ActionsSub sub;
  final ValueChanged<ActionsSub> onChanged;

  @override
  ConsumerState<ActionsSection> createState() => _ActionsSectionState();
}

class _ActionsSectionState extends ConsumerState<ActionsSection>
    with SingleTickerProviderStateMixin {
  final _visited = <ActionsSub>{};
  bool _calendarShown = false;
  late final TabController _tabs;

  static Widget _viewFor(ActionsSub sub) => switch (sub) {
    ActionsSub.current => const CurrentActionsView(),
    ActionsSub.calendar => const CalendarView(),
    ActionsSub.all => const AllActionsView(),
  };

  @override
  void initState() {
    super.initState();
    // Instant tab switch: zero animation duration, driven by [widget.sub].
    _tabs = TabController(
      length: ActionsSub.values.length,
      initialIndex: widget.sub.index,
      vsync: this,
      animationDuration: Duration.zero,
    )..addListener(_onTab);
  }

  void _onTab() {
    final picked = ActionsSub.values[_tabs.index];
    if (picked != widget.sub) widget.onChanged(picked);
  }

  @override
  void didUpdateWidget(ActionsSection old) {
    super.didUpdateWidget(old);
    if (_tabs.index != widget.sub.index) _tabs.index = widget.sub.index;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await ref.read(actionsCsvPickerProvider)();
    if (text == null || !mounted) return;
    try {
      final result = await ref
          .read(actionImportServiceProvider)
          .importCsv(text);
      if (!mounted) return;
      await ActionImportSummaryDialog.show(context, result);
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.sub);
    // The shell hides inactive sections with a disabled TickerMode, so this
    // is "the Actions section is on screen". Hand keyboard focus to the
    // Calendar whenever it becomes the shown view (after this frame, once
    // ExcludeFocus has been lifted from it).
    final shown =
        widget.sub == ActionsSub.calendar &&
        TickerMode.valuesOf(context).enabled;
    if (shown && !_calendarShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(calendarFocusRequestProvider.notifier).state++;
      });
    }
    _calendarShown = shown;
    final phone = usePhoneLayout(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                child: GlassSurface(
                  radius: 20,
                  shadow: false,
                  blurWindow: false,
                  child: TabBar(
                    key: const ValueKey('actions-switch'),
                    controller: _tabs,
                    splashFactory: NoSplash.splashFactory,
                    labelPadding: phone
                        ? const EdgeInsets.symmetric(horizontal: 4)
                        : null,
                    tabs: [
                      for (final s in ActionsSub.values)
                        Tab(text: phone ? s.phoneLabel : s.label),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.sub == ActionsSub.current)
              Builder(
                builder: (context) {
                  final on = ref.watch(currentIconsProvider);
                  final scheme = Theme.of(context).colorScheme;
                  return IconButton(
                    key: const ValueKey('current-icons-toggle'),
                    isSelected: on,
                    // The same icon as the 'Growth directions' rail item.
                    icon: const Icon(Icons.insights),
                    tooltip: on
                        ? 'Hide growth direction icons'
                        : 'Show growth direction icons',
                    style: IconButton.styleFrom(
                      backgroundColor: on ? scheme.primaryContainer : null,
                      foregroundColor: on ? scheme.onPrimaryContainer : null,
                    ),
                    onPressed: () =>
                        ref.read(currentIconsProvider.notifier).toggle(),
                  );
                },
              ),
            // The CSV import is a desktop job (Notion export on the PC).
            if (!phone)
              IconButton(
                key: const ValueKey('import-actions-csv'),
                icon: const Icon(Icons.upload_file),
                tooltip: 'Import actions from CSV…',
                onPressed: _importCsv,
              ),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final s in ActionsSub.values)
                if (_visited.contains(s))
                  Visibility(
                    key: ValueKey('actions-view-${s.name}'),
                    visible: s == widget.sub,
                    maintainState: true,
                    child: ExcludeFocus(
                      excluding: s != widget.sub,
                      child: _viewFor(s),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
