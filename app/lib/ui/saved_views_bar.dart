import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/saved_view_service.dart';
import '../domain/saved_views.dart';
import 'dialog_stack.dart';
import 'providers.dart';
import 'undo.dart' show offerUndo, undoHistoryProvider;
import 'widgets/app_toast.dart';

final savedViewServiceProvider = Provider<SavedViewService>(
  (ref) => SavedViewService(ref.watch(databaseProvider)),
);

/// The views of one screen (by its [ViewScreens] id).
final savedViewsProvider = StreamProvider.autoDispose
    .family<List<SavedViewItem>, String>(
      (ref, screen) => ref.watch(savedViewServiceProvider).watch(screen),
    );

/// How a screen reads and writes its own sort / filter state. The bar stays
/// generic: each host passes closures over its providers.
class SavedViewHooks {
  const SavedViewHooks({
    required this.screen,
    this.readSort,
    this.applySort,
    this.clearSort,
    this.readFilter,
    this.applyFilter,
    this.clearFilter,
  });

  final String screen;

  /// A screen without filters (or without sort) leaves that part null.
  final Map<String, Object?> Function()? readSort;
  final void Function(Map<String, Object?>)? applySort;
  final VoidCallback? clearSort;
  final Map<String, Object?> Function()? readFilter;
  final void Function(Map<String, Object?>)? applyFilter;
  final VoidCallback? clearFilter;

  bool get hasSort => readSort != null && applySort != null;
  bool get hasFilter => readFilter != null && applyFilter != null;

  /// Applies [v]: only the parts its kind stores (and this screen has).
  void apply(SavedViewItem v) {
    if (v.kind.hasSort && hasSort) applySort!(v.sort);
    if (v.kind.hasFilter && hasFilter) applyFilter!(v.filter);
  }

  void clear() {
    if (hasSort) clearSort?.call();
    if (hasFilter) clearFilter?.call();
  }
}

/// Applies the screen's default view ONCE, the first time its views load
/// (the host stays mounted while the screen is open). Wrap the screen in it.
class SavedViewsDefaultLoader extends ConsumerStatefulWidget {
  const SavedViewsDefaultLoader({
    super.key,
    required this.hooks,
    required this.child,
  });

  final SavedViewHooks hooks;
  final Widget child;

  @override
  ConsumerState<SavedViewsDefaultLoader> createState() =>
      _SavedViewsDefaultLoaderState();
}

class _SavedViewsDefaultLoaderState
    extends ConsumerState<SavedViewsDefaultLoader> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final views = ref.watch(savedViewsProvider(widget.hooks.screen));
    if (!_done && views.hasValue) {
      _done = true;
      final def = defaultViewOf(views.requireValue);
      if (def != null) {
        // After the frame: applying changes providers the tree is watching.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.hooks.apply(def);
        });
      }
    }
    return widget.child;
  }
}

/// "Views  [Big ones *]  [Only food]  + Save view  Clear": a tap applies a view,
/// its menu renames, updates, makes it the default or deletes it. A star marks
/// the default view; an icon says what it stores (sort / filter / both).
class SavedViewsBar extends ConsumerWidget {
  const SavedViewsBar({super.key, required this.hooks});

  final SavedViewHooks hooks;

  static IconData _kindIcon(SavedViewKind k) => switch (k) {
    SavedViewKind.sort => Icons.swap_vert,
    SavedViewKind.filter => Icons.filter_alt_outlined,
    SavedViewKind.both => Icons.tune,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views =
        ref.watch(savedViewsProvider(hooks.screen)).value ?? const [];
    final service = ref.read(savedViewServiceProvider);
    final theme = Theme.of(context);

    Future<void> menu(BuildContext chipContext, SavedViewItem v) async {
      final box = chipContext.findRenderObject() as RenderBox;
      final overlay =
          Overlay.of(chipContext).context.findRenderObject() as RenderBox;
      final pos = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      );
      final choice = await showMenu<String>(
        context: chipContext,
        position: pos,
        items: [
          const PopupMenuItem(value: 'update', child: Text('Update with the current settings')),
          const PopupMenuItem(value: 'rename', child: Text('Rename…')),
          PopupMenuItem(
            value: 'default',
            child: Text(v.isDefault ? 'Stop using by default' : 'Use by default'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
      if (choice == null || !chipContext.mounted) return;
      switch (choice) {
        case 'update':
          await service.save(
            screen: hooks.screen,
            name: v.name,
            kind: v.kind,
            sort: hooks.readSort?.call() ?? const {},
            filter: hooks.readFilter?.call() ?? const {},
          );
        case 'rename':
          final name = await _askName(chipContext, v.name, 'Rename view');
          if (name == null) return;
          if (!await service.rename(v.id, name) && chipContext.mounted) {
            showInfoToast(rootOverlayOf(chipContext), 'A view named "$name" already exists.');
          }
        case 'default':
          await service.setDefault(v.id, on: !v.isDefault);
        case 'delete':
          final overlayEntry = rootOverlayOf(chipContext);
          final history = ref.read(undoHistoryProvider.notifier);
          final row = await service.delete(v.id);
          if (row != null) {
            offerUndo(
              overlayEntry,
              history,
              'Deleted view "${v.name}"',
              () => service.undoDelete(row),
            );
          }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Views', style: theme.textTheme.titleSmall),
        for (final v in views)
          Builder(
            builder: (chipContext) => InputChip(
              key: ValueKey('view-chip-${v.id}'),
              avatar: Icon(_kindIcon(v.kind), size: 16),
              label: Text(v.isDefault ? '★ ${v.name}' : v.name),
              tooltip: v.isDefault ? 'Default view' : null,
              deleteIcon: const Icon(Icons.more_vert, size: 16),
              deleteButtonTooltipMessage: 'Edit view',
              onDeleted: () => menu(chipContext, v),
              onPressed: () => hooks.apply(v),
            ),
          ),
        ActionChip(
          key: const ValueKey('views-save'),
          avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: const Text('Save view'),
          onPressed: () => _save(context, ref, views),
        ),
        ActionChip(
          key: const ValueKey('views-clear'),
          avatar: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Clear'),
          tooltip: 'Back to the plain sort and no filters',
          onPressed: hooks.clear,
        ),
      ],
    );
  }

  Future<String?> _askName(BuildContext context, String initial, String title) {
    final c = TextEditingController(text: initial);
    return showStackedDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('views-rename-field'),
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((v) => v == null || v.isEmpty ? null : v);
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    List<SavedViewItem> views,
  ) async {
    final service = ref.read(savedViewServiceProvider);
    final result = await showStackedDialog<_SaveChoice>(
      context: context,
      builder: (_) => _SaveViewDialog(
        hasSort: hooks.hasSort,
        hasFilter: hooks.hasFilter,
        names: {for (final v in views) v.name.trim().toLowerCase()},
      ),
    );
    if (result == null) return;
    final id = await service.save(
      screen: hooks.screen,
      name: result.name,
      kind: result.kind,
      sort: hooks.readSort?.call() ?? const {},
      filter: hooks.readFilter?.call() ?? const {},
    );
    if (result.makeDefault) await service.setDefault(id);
  }
}

class _SaveChoice {
  const _SaveChoice(this.name, this.kind, this.makeDefault);

  final String name;
  final SavedViewKind kind;
  final bool makeDefault;
}

/// Name + what to store (sort, filters or both) + "use by default".
class _SaveViewDialog extends StatefulWidget {
  const _SaveViewDialog({
    required this.hasSort,
    required this.hasFilter,
    required this.names,
  });

  final bool hasSort;
  final bool hasFilter;
  final Set<String> names;

  @override
  State<_SaveViewDialog> createState() => _SaveViewDialogState();
}

class _SaveViewDialogState extends State<_SaveViewDialog> {
  final _name = TextEditingController();
  late bool _sort = widget.hasSort;
  late bool _filter = widget.hasFilter;
  bool _default = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && (_sort || _filter);

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(
      _SaveChoice(
        _name.text.trim(),
        SavedViewKind.of(sort: _sort, filter: _filter),
        _default,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final replaces = widget.names.contains(_name.text.trim().toLowerCase());
    return AlertDialog(
      title: const Text('Save view'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('views-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            if (widget.hasSort)
              CheckboxListTile(
                key: const ValueKey('views-keep-sort'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Remember the sort'),
                value: _sort,
                onChanged: widget.hasFilter
                    ? (v) => setState(() => _sort = v ?? false)
                    : null,
              ),
            if (widget.hasFilter)
              CheckboxListTile(
                key: const ValueKey('views-keep-filter'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Remember the filters'),
                value: _filter,
                onChanged: widget.hasSort
                    ? (v) => setState(() => _filter = v ?? false)
                    : null,
              ),
            CheckboxListTile(
              key: const ValueKey('views-make-default'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Use by default when this screen opens'),
              value: _default,
              onChanged: (v) => setState(() => _default = v ?? false),
            ),
            if (replaces)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'A view with this name exists and will be replaced.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('views-save-confirm'),
          onPressed: _valid ? _submit : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
