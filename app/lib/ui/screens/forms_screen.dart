import '../search_targets.dart';
import '../../domain/search_match.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/form_service.dart';
import '../form_providers.dart';
import '../undo.dart';
import '../widgets/app_toast.dart';
import '../widgets/direction_badge.dart' show emojiLabelStyle;
import '../widgets/form_builder.dart';
import '../widgets/glass.dart';
import '../widgets/glass_icon_tile.dart';

/// The Forms tab of the Actions section: the forms that set growth directions
/// on selected actions (fill one from the All list or the Calendar selection,
/// or from an action's edit window). Create, edit, copy and delete here.
class FormsScreen extends ConsumerStatefulWidget {
  const FormsScreen({super.key});

  /// "New form" (the shell's round button opens it on the Forms tab).
  static Future<void> showNewForm(BuildContext context) =>
      FormBuilderDialog.show(context);

  @override
  ConsumerState<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends ConsumerState<FormsScreen>
    with SearchTargetState<FormsScreen> {
  String _query = '';
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    registerSearchTarget();
  }

  // Ctrl+F: focus the search field and select its text.
  @override
  void openSearch() => focusSearchField(_searchFocus, _searchText);

  @override
  void dispose() {
    unregisterSearchTarget();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _delete(BuildContext context, FormItem f) async {
    // Everything needing ref / context is read before the await.
    final service = ref.read(formServiceProvider);
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final row = await service.delete(f.id);
    if (row == null) return;
    offerUndo(
      overlay,
      history,
      'Deleted form "${f.name}"',
      () => service.undoDelete(row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final forms = ref.watch(formsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TextField(
              key: const ValueKey('forms-search'),
              controller: _searchText,
              focusNode: _searchFocus,
              decoration: const InputDecoration(
                hintText: 'Search forms',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: forms.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                if (all.isEmpty) {
                  return const Center(
                    child: Text(
                      'No forms yet. Press + to make one.',
                      key: ValueKey('forms-empty'),
                    ),
                  );
                }
                // Whole-word matches of the name first, then the rest (a hit in
                // a question title counts after the name).
                final shown = rankMatches(all, _query, (f) => [
                  f.name,
                  for (final q in f.def.questions) q.title,
                ]);
                if (shown.isEmpty) return const Center(child: Text('No matches'));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final f = shown[i];
                    final q = f.def.activeQuestions.length;
                    final o = f.def.optionCount;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: GlassSurface(
                        radius: 16,
                        shadow: false,
                        blurWindow: false,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            key: ValueKey('form-${f.id}'),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Text(
                              f.def.display,
                              style: emojiLabelStyle.copyWith(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            // The description gets its own, larger line (up to
                            // two lines); the counts sit under it.
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (f.def.description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      f.def.description,
                                      key: ValueKey('form-desc-${f.id}'),
                                      style: const TextStyle(fontSize: 15),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '$q question${q == 1 ? '' : 's'} · '
                                    '$o answer${o == 1 ? '' : 's'}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () =>
                                FormBuilderDialog.show(context, existing: f),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GlassIconTile(
                                  key: ValueKey('form-copy-${f.id}'),
                                  icon: Icons.copy_rounded,
                                  hue: GlassHue.blue,
                                  tooltip: 'Make a copy',
                                  size: 32,
                                  iconSize: 18,
                                  onTap: () => ref
                                      .read(formServiceProvider)
                                      .duplicate(f.id),
                                ),
                                const SizedBox(width: 4),
                                GlassIconTile(
                                  key: ValueKey('form-delete-${f.id}'),
                                  icon: Icons.delete_outline_rounded,
                                  hue: GlassHue.error,
                                  tooltip: 'Delete',
                                  size: 32,
                                  iconSize: 20,
                                  onTap: () => _delete(context, f),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
