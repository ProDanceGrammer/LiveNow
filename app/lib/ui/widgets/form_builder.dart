import 'emoji_picker_button.dart' show pickEmoji;
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../domain/form_outline.dart';
import '../../domain/form_service.dart';
import '../../domain/forms.dart';
import '../../domain/name_sort.dart';
import '../dialog_back.dart';
import '../dialog_stack.dart';
import '../form_providers.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import 'activity_picker_dialog.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'metric_picker.dart';
import 'section_block.dart';

/// The three emoji fields are small boxes that hold ONE emoji: almost no side
/// padding (the theme's 16 px would leave no room for it), a centred emoji and
/// a hint instead of a label (a label does not fit). Sizes: header 36 px,
/// question 36 px, answer 32 px.
const _kIconPadding = EdgeInsets.symmetric(horizontal: 2, vertical: 6);
TextStyle get _iconStyle => emojiLabelStyle.copyWith(fontSize: 18);

/// The builder is a dense editing surface: text 1.5x smaller than the app's,
/// compact density and tighter field padding, for the builder's own widgets only
/// (dialogs it opens keep the normal size).
const double _kBuilderTextShrink = 1.5;

/// A font size that renders as [effective] logical pixels INSIDE the builder
/// (its text scaler is divided by [_kBuilderTextShrink]): for the few texts that
/// must stay larger than the rest (name, description, "Adds", "Required").
double _big(double effective) => effective * _kBuilderTextShrink;

/// The size (effective px) shared by the answer text, its "Adds:" label, the
/// direction chips beside it and the activity chip: one size, regular weight.
const double _kAnswerPx = 12.5;

/// The size the "Second line (optional)" field renders at (the theme's 16 px
/// input text, scaled down like the rest of the builder, about 10.7 px): the
/// direction picker's explanation and its chips use it too, so they match it.
const TextStyle _kSecondLineText = TextStyle(fontSize: 16);

/// The three text buttons under a question ("New question below", "Add option",
/// "Paste options"): one readable size, regular weight.
final ButtonStyle _kRowButton = ButtonStyle(
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: _big(12))),
);

/// The page's action chips (Add combination / Add question / Paste outline) and
/// the Cancel / Save buttons: the primary controls, so clearly larger than the
/// rest of the dense builder (16 px text, roomy padding).
final TextStyle _kBigChipText = TextStyle(
  fontSize: _big(12.5),
  fontWeight: FontWeight.w600,
);
const EdgeInsets _kBigChipPadding = EdgeInsets.symmetric(
  horizontal: 6,
  vertical: 6,
);
const double _kBigChipIcon = 20;
final ButtonStyle _kBigButton = ButtonStyle(
  textStyle: WidgetStatePropertyAll(
    TextStyle(fontSize: _big(14), fontWeight: FontWeight.w600),
  ),
  padding: const WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 22, vertical: 11),
  ),
  minimumSize: const WidgetStatePropertyAll(Size(96, 40)),
);

Widget _compact(BuildContext context, Widget child) {
  final mq = MediaQuery.of(context);
  final theme = Theme.of(context);
  final system = mq.textScaler.scale(10) / 10;
  return MediaQuery(
    data: mq.copyWith(
      textScaler: TextScaler.linear(system / _kBuilderTextShrink),
    ),
    child: Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.compact,
        // A tooltip is built inside the widget it belongs to, so it would get the
        // builder's 1.5x smaller text (the app's 12 px became 8 px): hover text
        // is set explicitly, 15 px, with room around it.
        tooltipTheme: theme.tooltipTheme.copyWith(
          textStyle: TextStyle(color: Colors.white, fontSize: _big(15)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          waitDuration: const Duration(milliseconds: 250),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
        ),
      ),
      child: child,
    ),
  );
}

/// The form builder: name, description and emoji; questions (reorderable) with
/// their options; for every option the directions it adds (one or several, with
/// the searchable direction picker) and an optional Countable Activity. Text can
/// be pasted as an outline to create many questions / options at once.
/// Closing with the mouse Back button keeps the unsaved form as a draft that
/// Undo reopens.
class FormBuilderDialog extends ConsumerStatefulWidget {
  const FormBuilderDialog({super.key, this.existing, this.draft});

  final FormItem? existing;

  /// Unsaved edits to restore (Undo after a Back-button close).
  final FormDef? draft;

  static Future<void> show(BuildContext context, {FormItem? existing}) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => FormBuilderDialog(existing: existing),
      );

  @override
  ConsumerState<FormBuilderDialog> createState() => _FormBuilderDialogState();
}

class _FormBuilderDialogState extends ConsumerState<FormBuilderDialog>
    implements DraftDialog {
  late FormDef _form;
  late final String _baseSignature;
  bool _nameMissing = false;

  static String _sig(FormDef f) => '${f.name}|${encodeFormPayload(f)}';

  @override
  void initState() {
    super.initState();
    final base = widget.existing?.def ?? const FormDef(name: '');
    _baseSignature = _sig(base);
    _form = widget.draft ?? base;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registerDraftDialog(ModalRoute.of(context), this);
  }

  @override
  void dispose() {
    unregisterDraftDialog(this);
    super.dispose();
  }

  bool get _isDirty => _sig(_form) != _baseSignature;

  @override
  void closeByBack() {
    final shown = _form.name.trim();
    final existing = widget.existing;
    closeDraftDialog(
      context: context,
      ref: ref,
      label: shown.isEmpty ? 'form' : '"$shown"',
      draft: _isDirty ? _form : null,
      reopen: (root, d) => showStackedDialog<void>(
        context: root,
        builder: (_) => FormBuilderDialog(existing: existing, draft: d as FormDef),
      ),
    );
  }

  // ---- edits ----------------------------------------------------------------

  /// Typing changes the data without rebuilding the page (a form can have a
  /// hundred text fields); structural changes pass [rebuild].
  void _setQuestion(int i, FormQuestion q, {bool rebuild = false}) {
    final qs = [..._form.questions]..[i] = q;
    _form = _form.copyWith(questions: qs);
    if (rebuild) setState(() {});
  }

  void _setOption(int qi, int oi, FormOption o, {bool rebuild = false}) {
    final q = _form.questions[qi];
    final opts = [...q.options]..[oi] = o;
    _setQuestion(qi, q.copyWith(options: opts), rebuild: rebuild);
  }

  /// The question whose title takes the keyboard focus once built (the one that
  /// "New question below" just made).
  String? _autofocusQuestionId;

  FormQuestion _blankQuestion(String kind) => FormQuestion(
    id: newId(),
    title: '',
    kindName: kind,
    options: kind == 'checkboxes'
        ? [FormOption(id: newId(), label: '')]
        : const [],
  );

  void _addQuestion(String kind) {
    setState(() {
      _form = _form.copyWith(
        questions: [..._form.questions, _blankQuestion(kind)],
      );
    });
  }

  /// A new, empty checkbox question right below question [i]; its title field
  /// gets the focus.
  void _addQuestionBelow(int i) => setState(() {
    final q = _blankQuestion('checkboxes');
    _autofocusQuestionId = q.id;
    _form = _form.copyWith(
      questions: [..._form.questions]..insert(i + 1, q),
    );
  });

  /// A copy of question [i] right below it (new ids for it and its answers).
  void _duplicateQuestion(int i) => setState(() {
    final qs = [..._form.questions]..insert(i + 1, _form.questions[i].duplicated());
    _form = _form.copyWith(questions: qs);
  });

  void _removeQuestion(int i) => setState(() {
    _form = _form
        .copyWith(questions: [..._form.questions]..removeAt(i))
        .withoutDeadCombos();
  });

  void _addOption(int qi) {
    final q = _form.questions[qi];
    _setQuestion(
      qi,
      q.copyWith(options: [...q.options, FormOption(id: newId(), label: '')]),
      rebuild: true,
    );
  }

  void _removeOption(int qi, int oi) {
    final q = _form.questions[qi];
    _setQuestion(
      qi,
      q.copyWith(options: [...q.options]..removeAt(oi)),
    );
    // A rule that used the answer goes with it.
    setState(() => _form = _form.withoutDeadCombos());
  }

  void _moveOption(int qi, int oi, int delta) {
    final q = _form.questions[qi];
    final to = oi + delta;
    if (to < 0 || to >= q.options.length) return;
    final opts = [...q.options];
    final o = opts.removeAt(oi);
    opts.insert(to, o);
    _setQuestion(qi, q.copyWith(options: opts), rebuild: true);
  }

  Future<void> _pasteOutline() async {
    final text = await _askText(
      context,
      title: 'Paste an outline',
      help:
          'A line starts a question, the lines under it (with - or a number, '
          'or indented) are its options. A leading emoji becomes the icon.',
      fieldKey: 'form-outline-field',
      okKey: 'form-outline-add',
      ok: 'Add questions',
    );
    if (text == null || !mounted) return;
    final qs = parseOutline(text);
    if (qs.isEmpty) return;
    setState(() {
      _form = _form.copyWith(questions: [..._form.questions, ...qs]);
    });
  }

  Future<void> _pasteOptions(int qi) async {
    final text = await _askText(
      context,
      title: 'Paste options',
      help: 'One option per line. A leading emoji becomes the option\'s icon.',
      fieldKey: 'form-options-field',
      okKey: 'form-options-add',
      ok: 'Add options',
    );
    if (text == null || !mounted) return;
    final opts = parseOptionLines(text);
    if (opts.isEmpty) return;
    final q = _form.questions[qi];
    // An empty placeholder option left by "Add question" makes way for them.
    final keep = [
      for (final o in q.options)
        if (o.label.trim().isNotEmpty || o.metricIds.isNotEmpty) o,
    ];
    _setQuestion(qi, q.copyWith(options: [...keep, ...opts]), rebuild: true);
  }

  /// The Countable Activity chooser shared by an answer and a combination:
  /// null = cancelled (change nothing), `(name: null)` = "None" (clear it),
  /// otherwise the chosen / typed activity name.
  Future<({String? name})?> _chooseActivity() async {
    // Nothing listens to the auto-dispose stream providers here: read once.
    final db = ref.read(databaseProvider);
    final activities = await (db.select(
      db.countableActivitiesTable,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    final templates = [...await db.select(db.actionTemplatesTable).get()]
      ..sort((a, b) => compareIgnoringEmoji(a.name, b.name));
    if (!mounted) return null;
    final pick = await ActivityPickerDialog.show(
      context,
      activities: activities,
      templates: templates,
    );
    if (pick == null || !mounted) return null;
    switch (pick) {
      case ActivityPickNone():
        return (name: null);
      case ActivityPickExisting(:final id):
        final name = activities.where((a) => a.id == id).firstOrNull?.name;
        return name == null ? null : (name: name);
      case ActivityPickTemplate(:final name):
        return (name: name);
      case ActivityPickNew():
        final name = await _askText(
          context,
          title: 'New activity',
          help: 'It is created when a form sets it for the first time.',
          fieldKey: 'form-activity-field',
          okKey: 'form-activity-ok',
          ok: 'Use',
          lines: 1,
        );
        if (name == null || name.trim().isEmpty || !mounted) return null;
        return (name: name.trim());
    }
  }

  Future<void> _pickActivity(int qi, int oi) async {
    final r = await _chooseActivity();
    if (r == null || !mounted) return;
    final o = _form.questions[qi].options[oi];
    _setOption(
      qi,
      oi,
      r.name == null
          ? o.copyWith(clearActivity: true)
          : o.copyWith(activityName: r.name),
      rebuild: true,
    );
  }

  /// The activity a combination sets (see `computeEffects`: it wins over the
  /// activities of the single answers).
  Future<void> _pickComboActivity(int ci) async {
    final r = await _chooseActivity();
    if (r == null || !mounted) return;
    final c = _form.combos[ci];
    _setCombo(
      ci,
      r.name == null
          ? c.copyWith(clearActivity: true)
          : c.copyWith(activityName: r.name),
    );
  }

  Future<void> _save() async {
    if (_form.name.trim().isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    // Empty placeholders (a blank option, a question without a title) are not
    // worth keeping.
    final cleaned = _form.copyWith(
      questions: [
        for (final q in _form.questions)
          if (q.title.trim().isNotEmpty || q.options.any((o) => o.label.isNotEmpty))
            q.copyWith(
              options: [
                for (final o in q.options)
                  if (o.label.trim().isNotEmpty) o,
              ],
            ),
      ],
    ).withoutDeadCombos();
    final navigator = Navigator.of(context);
    await ref
        .read(formServiceProvider)
        .save(cleaned, id: widget.existing?.id);
    if (mounted) navigator.pop();
  }

  // ---- combinations ---------------------------------------------------------

  void _addCombo() => setState(() {
    _form = _form.copyWith(
      combos: [..._form.combos, FormCombo(id: newId())],
    );
  });

  void _setCombo(int i, FormCombo c) => setState(() {
    _form = _form.copyWith(combos: [..._form.combos]..[i] = c);
  });

  /// A copy of combination [i] right below it.
  void _duplicateCombo(int i) => setState(() {
    final cs = [..._form.combos]..insert(i + 1, _form.combos[i].duplicated());
    _form = _form.copyWith(combos: cs);
  });

  void _removeCombo(int i) => setState(() {
    _form = _form.copyWith(combos: [..._form.combos]..removeAt(i));
  });

  /// `Question · Answer` for a pick (a blank title or answer gets a name).
  String _pickLabel(FormPick p) {
    final qi = _form.questions.indexWhere((q) => q.id == p.questionId);
    if (qi < 0) return '?';
    final q = _form.questions[qi];
    final o = q.options.where((o) => o.id == p.optionId).firstOrNull;
    // The question's emoji belongs in the label too (only the answer's showed).
    final qt = q.title.trim().isEmpty
        ? '${q.icon == null || q.icon!.isEmpty ? '' : '${q.icon} '}'
              'Question ${qi + 1}'
        : q.display;
    final ot = o == null || o.label.trim().isEmpty ? '(blank)' : o.display;
    return '$qt · $ot';
  }

  /// Every answer of every checkbox question, to tick the ones of a rule.
  Future<void> _pickComboAnswers(int ci) async {
    final combo = _form.combos[ci];
    final chosen = {...combo.picks};
    final result = await showStackedDialog<Set<FormPick>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Answers that must ALL be ticked'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var qi = 0; qi < _form.questions.length; qi++)
                    if (_form.questions[qi].kind ==
                            FormQuestionKind.checkboxes &&
                        _form.questions[qi].options.any(
                          (o) => o.label.trim().isNotEmpty,
                        )) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Text(
                          _form.questions[qi].title.trim().isEmpty
                              ? 'Question ${qi + 1}'
                              : _form.questions[qi].display,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      for (final o in _form.questions[qi].options)
                        if (o.label.trim().isNotEmpty)
                          CheckboxListTile(
                            key: ValueKey(
                              'combo-pick-${_form.questions[qi].id}-${o.id}',
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(o.display, style: emojiLabelStyle),
                            value: chosen.contains(
                              FormPick(_form.questions[qi].id, o.id),
                            ),
                            onChanged: (on) => setLocal(() {
                              final p = FormPick(_form.questions[qi].id, o.id);
                              on == true ? chosen.add(p) : chosen.remove(p);
                            }),
                          ),
                    ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('combo-picks-ok'),
              onPressed: () => Navigator.of(dialogContext).pop(chosen),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    // Keep the order the answers have in the form.
    final ordered = [
      for (final q in _form.questions)
        for (final o in q.options)
          if (result.contains(FormPick(q.id, o.id))) FormPick(q.id, o.id),
    ];
    _setCombo(ci, _form.combos[ci].copyWith(picks: ordered));
  }

  /// The "Combinations" block: rules that add directions ON TOP when several
  /// answers are ticked together. Nothing is shown until a rule exists.
  List<Widget> _combosBlock(BuildContext context) {
    if (_form.combos.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Text(
          'Combinations',
          style: theme.textTheme.titleSmall?.copyWith(
            fontSize: _big(17),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Text(
        'When ALL the chosen answers are ticked together, these directions '
        'are added as well (on top of what each answer adds by itself).',
        style: theme.textTheme.bodySmall?.copyWith(fontSize: _big(13)),
      ),
      const SizedBox(height: 6),
      for (var ci = 0; ci < _form.combos.length; ci++)
        Padding(
          key: ValueKey('combo-${_form.combos[ci].id}'),
          padding: const EdgeInsets.only(bottom: 4),
          child: SectionBlock(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final p in _form.combos[ci].picks)
                            InputChip(
                              label: Text(
                                _pickLabel(p),
                                style: emojiLabelStyle.copyWith(
                                  fontSize: _big(14),
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                              onDeleted: () => _setCombo(
                                ci,
                                _form.combos[ci].copyWith(
                                  picks: [
                                    for (final x in _form.combos[ci].picks)
                                      if (x != p) x,
                                  ],
                                ),
                              ),
                            ),
                          ActionChip(
                            key: ValueKey(
                              'combo-picks-${_form.combos[ci].id}',
                            ),
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(
                              _form.combos[ci].picks.isEmpty
                                  ? 'Choose answers'
                                  : 'Answers',
                              style: TextStyle(fontSize: _big(14)),
                            ),
                            onPressed: () => _pickComboAnswers(ci),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Also adds:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: _big(12),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          MetricPicker(
                            key: ValueKey(
                              'combo-metrics-${_form.combos[ci].id}',
                            ),
                            label: '',
                            showNone: false,
                            textStyle: TextStyle(fontSize: _big(14)),
                            selectedIds: _form.combos[ci].metricIds.toSet(),
                            onChanged: (ids) => _setCombo(
                              ci,
                              _form.combos[ci].copyWith(
                                metricIds: ids.toList(),
                              ),
                            ),
                          ),
                          if (_form.combos[ci].activityName == null)
                            ActionChip(
                              key: ValueKey(
                                'combo-activity-${_form.combos[ci].id}',
                              ),
                              avatar: const Icon(Icons.track_changes, size: 16),
                              label: Text(
                                'Activity',
                                style: TextStyle(fontSize: _big(14)),
                              ),
                              onPressed: () => _pickComboActivity(ci),
                            )
                          else
                            InputChip(
                              key: ValueKey(
                                'combo-activity-${_form.combos[ci].id}',
                              ),
                              avatar: const Icon(Icons.track_changes, size: 16),
                              label: Text(
                                'Activity: ${_form.combos[ci].activityName}',
                                style: TextStyle(fontSize: _big(14)),
                              ),
                              onPressed: () => _pickComboActivity(ci),
                              onDeleted: () => _setCombo(
                                ci,
                                _form.combos[ci].copyWith(clearActivity: true),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('combo-dup-${_form.combos[ci].id}'),
                  tooltip: 'Duplicate the combination',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _duplicateCombo(ci),
                ),
                IconButton(
                  key: ValueKey('combo-delete-${_form.combos[ci].id}'),
                  tooltip: 'Delete the combination',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeCombo(ci),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 4),
    ];
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final phone = usePhoneLayout(context);
    final size = MediaQuery.sizeOf(context);
    final body = _compact(
      context,
      Material(
      color: context.glass.fillDialog,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              // ONE scroll view for the whole page, with the questions as a
              // sliver reorderable list: the page itself scrolls while a card is
              // dragged near the edge (a list nested in another scroll view could
              // not, which is what made dragging feel stuck and jumpy).
              child: CustomScrollView(
                key: const ValueKey('form-builder-scroll'),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: phone ? 12 : 24,
                      vertical: 14,
                    ),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [_header(context), const SizedBox(height: 8)],
                          ),
                        ),
                        SliverReorderableList(
                          itemCount: _form.questions.length,
                          proxyDecorator: _dragProxy,
                          onReorderItem: (from, to) => setState(() {
                            final qs = [..._form.questions];
                            final q = qs.removeAt(from);
                            qs.insert(to, q);
                            _form = _form.copyWith(questions: qs);
                          }),
                          itemBuilder: (context, i) => _questionCard(context, i),
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                    const SizedBox(height: 8),
                    ..._combosBlock(context),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          key: const ValueKey('form-add-combo'),
                          avatar: const Icon(Icons.join_inner, size: _kBigChipIcon),
                          label: Text('Add combination', style: _kBigChipText),
                          padding: _kBigChipPadding,
                          onPressed: _addCombo,
                        ),
                        PopupMenuButton<String>(
                          key: const ValueKey('form-add-question'),
                          tooltip: 'Add a question',
                          onSelected: _addQuestion,
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'checkboxes',
                              child: Text('Checkbox list'),
                            ),
                            PopupMenuItem(
                              value: 'directions',
                              child: Text('Direction picker'),
                            ),
                            PopupMenuItem(
                              enabled: false,
                              value: 'people',
                              child: Text('People picker (coming later)'),
                            ),
                          ],
                          child: IgnorePointer(
                            child: Chip(
                              avatar: const Icon(Icons.add, size: _kBigChipIcon),
                              label: Text('Add question', style: _kBigChipText),
                              padding: _kBigChipPadding,
                            ),
                          ),
                        ),
                        ActionChip(
                          key: const ValueKey('form-paste-outline'),
                          avatar: const Icon(Icons.content_paste, size: _kBigChipIcon),
                          label: Text('Paste outline', style: _kBigChipText),
                          padding: _kBigChipPadding,
                          onPressed: _pasteOutline,
                        ),
                      ],
                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('form-builder-cancel'),
                    style: _kBigButton,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const ValueKey('form-save'),
                    style: _kBigButton,
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
    if (phone) return Dialog.fullscreen(child: body);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth(context, 860),
        height: size.height * 0.92,
        child: body,
      ),
    );
  }

  /// The card under the finger while a question is dragged: a light lift (a
  /// soft shadow and a hair of scale) instead of the default opaque, heavily
  /// elevated Material, which looked jumpy against the glass panel.
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, c) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.015 * t,
          child: Material(
            type: MaterialType.transparency,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18 * t),
                    blurRadius: 14 * t,
                    offset: Offset(0, 4 * t),
                  ),
                ],
              ),
              child: c,
            ),
          ),
        );
      },
      child: child,
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.existing == null ? 'New form' : 'Edit form',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: 'Icon (an emoji)',
              child: _FormIconField(
                fieldKey: const ValueKey('form-icon'),
                initial: _form.icon ?? '',
                width: 36,
                onChanged: (v) => _form = v.trim().isEmpty
                    ? _form.copyWith(clearIcon: true)
                    : _form.copyWith(icon: v.trim()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: const ValueKey('form-name'),
                initialValue: _form.name,
                style: TextStyle(fontSize: _big(18), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Form name',
                  labelStyle: TextStyle(fontSize: _big(13)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  errorText: _nameMissing ? 'Give the form a name' : null,
                ),
                onChanged: (v) {
                  _form = _form.copyWith(name: v);
                  if (_nameMissing && v.trim().isNotEmpty) {
                    setState(() => _nameMissing = false);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('form-description'),
          initialValue: _form.description,
          minLines: 1,
          maxLines: 3,
          style: TextStyle(fontSize: _big(16)),
          decoration: InputDecoration(
            labelText: 'Description (shown on top of the form)',
            labelStyle: TextStyle(fontSize: _big(13)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          onChanged: (v) => _form = _form.copyWith(description: v),
        ),
      ],
    );
  }

  Widget _questionCard(BuildContext context, int i) {
    final q = _form.questions[i];
    final theme = Theme.of(context);
    final isChecks = q.kind == FormQuestionKind.checkboxes;
    final newBelow = TextButton.icon(
      key: ValueKey('form-q-below-${q.id}'),
      style: _kRowButton,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('New question below'),
      onPressed: () => _addQuestionBelow(i),
    );
    return Padding(
      key: ValueKey(q.id),
      padding: const EdgeInsets.only(bottom: 4),
      child: SectionBlock(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(2, 6, 6, 6),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Icon (an emoji)',
                  child: _FormIconField(
                    fieldKey: ValueKey('form-q-icon-${q.id}'),
                    initial: q.icon ?? '',
                    width: 36,
                    onChanged: (v) => _setQuestion(
                      i,
                      v.trim().isEmpty
                          ? _form.questions[i].copyWith(clearIcon: true)
                          : _form.questions[i].copyWith(icon: v.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('form-q-title-${q.id}'),
                    initialValue: q.title,
                    autofocus: q.id == _autofocusQuestionId,
                    decoration: InputDecoration(
                      labelText: 'Question',
                      labelStyle: TextStyle(fontSize: _big(12)),
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: _big(14),
                      fontWeight: FontWeight.w700,
                    ),
                    onChanged: (v) =>
                        _setQuestion(i, _form.questions[i].copyWith(title: v)),
                  ),
                ),
                IconButton(
                  key: ValueKey('form-q-dup-${q.id}'),
                  tooltip: 'Duplicate the question',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _duplicateQuestion(i),
                ),
                IconButton(
                  key: ValueKey('form-q-delete-${q.id}'),
                  tooltip: 'Delete the question',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeQuestion(i),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('form-q-hint-${q.id}'),
                    initialValue: q.hint,
                    style: _kSecondLineText,
                    decoration: const InputDecoration(
                      labelText: 'Second line (optional)',
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        _setQuestion(i, _form.questions[i].copyWith(hint: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Required',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: _big(14),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  key: ValueKey('form-q-required-${q.id}'),
                  value: q.required,
                  onChanged: (v) => _setQuestion(
                    i,
                    _form.questions[i].copyWith(required: v),
                    rebuild: true,
                  ),
                ),
              ],
            ),
            if (!isChecks) ...[
              const SizedBox(height: 6),
              Text(
                q.kind == FormQuestionKind.directions
                    ? 'Direction picker: the chosen directions are added as '
                          'they are. Pick the directions to choose from '
                          '(none = any).'
                    : 'This kind of question is not supported yet; it is kept '
                          'but not shown.',
                // The size of the "Second line (optional)" field above.
                style: theme.textTheme.bodySmall?.merge(_kSecondLineText),
              ),
              if (q.kind == FormQuestionKind.directions)
                MetricPicker(
                  key: ValueKey('form-q-pool-${q.id}'),
                  label: '',
                  textStyle: _kSecondLineText,
                  selectedIds: q.metricIds.toSet(),
                  onChanged: (ids) => _setQuestion(
                    i,
                    _form.questions[i].copyWith(metricIds: ids.toList()),
                    rebuild: true,
                  ),
                ),
              Wrap(spacing: 8, children: [newBelow]),
            ] else ...[
              const SizedBox(height: 4),
              for (var oi = 0; oi < q.options.length; oi++)
                _optionRow(context, i, oi),
              Wrap(
                spacing: 8,
                children: [
                  // To the LEFT of "Add option".
                  newBelow,
                  TextButton.icon(
                    key: ValueKey('form-add-option-${q.id}'),
                    style: _kRowButton,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add option'),
                    onPressed: () => _addOption(i),
                  ),
                  TextButton.icon(
                    key: ValueKey('form-paste-options-${q.id}'),
                    style: _kRowButton,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Paste options'),
                    onPressed: () => _pasteOptions(i),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _optionRow(BuildContext context, int qi, int oi) {
    final o = _form.questions[qi].options[oi];
    final theme = Theme.of(context);
    final phone = usePhoneLayout(context);
    // The directions (and activity) the answer adds: RIGHT of the answer text on
    // a wide window, under it on a phone (no room beside it there).
    final adds = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Adds:',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: _big(_kAnswerPx),
            fontWeight: FontWeight.w400,
          ),
        ),
        MetricPicker(
          key: ValueKey('form-opt-metrics-${o.id}'),
          label: '',
          showNone: false,
          textStyle: TextStyle(fontSize: _big(_kAnswerPx)),
          selectedIds: o.metricIds.toSet(),
          onChanged: (ids) => _setOption(
            qi,
            oi,
            _form.questions[qi].options[oi].copyWith(metricIds: ids.toList()),
            rebuild: true,
          ),
        ),
        if (o.activityName == null)
          ActionChip(
            key: ValueKey('form-opt-activity-${o.id}'),
            avatar: const Icon(Icons.track_changes, size: 16),
            label: Text(
              'Activity',
              style: TextStyle(fontSize: _big(_kAnswerPx)),
            ),
            onPressed: () => _pickActivity(qi, oi),
          )
        else
          InputChip(
            key: ValueKey('form-opt-activity-${o.id}'),
            avatar: const Icon(Icons.track_changes, size: 16),
            label: Text(
              'Activity: ${o.activityName}',
              style: TextStyle(fontSize: _big(_kAnswerPx)),
            ),
            onPressed: () => _pickActivity(qi, oi),
            onDeleted: () => _setOption(
              qi,
              oi,
              _form.questions[qi].options[oi].copyWith(clearActivity: true),
              rebuild: true,
            ),
          ),
      ],
    );
    return Padding(
      key: ValueKey('form-opt-${o.id}'),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 30),
              Tooltip(
                message: 'Icon (an emoji)',
                child: _FormIconField(
                  fieldKey: ValueKey('form-opt-icon-${o.id}'),
                  initial: o.icon ?? '',
                  width: 32,
                  onChanged: (v) => _setOption(
                    qi,
                    oi,
                    v.trim().isEmpty
                        ? _form.questions[qi].options[oi].copyWith(clearIcon: true)
                        : _form.questions[qi].options[oi].copyWith(icon: v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: phone ? 1 : 5,
                child: TextFormField(
                  key: ValueKey('form-opt-label-${o.id}'),
                  initialValue: o.label,
                  style: TextStyle(fontSize: _big(_kAnswerPx)),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Answer',
                    hintStyle: TextStyle(fontSize: _big(_kAnswerPx)),
                  ),
                  onChanged: (v) => _setOption(
                    qi,
                    oi,
                    _form.questions[qi].options[oi].copyWith(label: v),
                  ),
                ),
              ),
              if (!phone) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: adds,
                  ),
                ),
              ],
              IconButton(
                key: ValueKey('form-opt-up-${o.id}'),
                tooltip: 'Move up',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: () => _moveOption(qi, oi, -1),
              ),
              IconButton(
                key: ValueKey('form-opt-down-${o.id}'),
                tooltip: 'Move down',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: () => _moveOption(qi, oi, 1),
              ),
              IconButton(
                key: ValueKey('form-opt-delete-${o.id}'),
                tooltip: 'Delete the answer',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeOption(qi, oi),
              ),
            ],
          ),
          if (phone)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: adds,
            ),
          const Divider(height: 10),
        ],
      ),
    );
  }
}

/// A small dialog with a text box; returns the text, or null when cancelled.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String help,
  required String fieldKey,
  required String okKey,
  required String ok,
  int lines = 10,
}) {
  final controller = TextEditingController();
  return showStackedDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(help, style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(
              key: ValueKey(fieldKey),
              controller: controller,
              autofocus: true,
              minLines: lines == 1 ? 1 : 6,
              maxLines: lines,
              style: emojiLabelStyle,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey(okKey),
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(ok),
        ),
      ],
    ),
  ).whenComplete(() {
    // The closing animation still builds the field: dispose a frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  });
}

/// The small icon box of a form, question or option, with a button that opens
/// the emoji / flag chooser (typing an emoji still works).
class _FormIconField extends StatefulWidget {
  const _FormIconField({
    required this.fieldKey,
    required this.initial,
    required this.width,
    required this.onChanged,
  });

  final Key fieldKey;
  final String initial;
  final double width;
  final ValueChanged<String> onChanged;

  @override
  State<_FormIconField> createState() => _FormIconFieldState();
}

class _FormIconFieldState extends State<_FormIconField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final emoji = await pickEmoji(context);
    if (emoji == null) return;
    _controller.text = emoji;
    widget.onChanged(emoji);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: widget.width,
        child: TextFormField(
          key: widget.fieldKey,
          controller: _controller,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: '🙂',
            isDense: true,
            contentPadding: _kIconPadding,
          ),
          style: _iconStyle,
          onChanged: widget.onChanged,
        ),
      ),
      InkResponse(
        key: ValueKey('${widget.fieldKey}-pick'),
        onTap: _pick,
        radius: 14,
        child: const Padding(
          padding: EdgeInsets.all(3),
          child: Icon(Icons.emoji_emotions_outlined, size: 15),
        ),
      ),
    ],
  );
}
