/// Turns the printed names of a receipt (Turkish capitals, abbreviations, OCR
/// slips) into a Ukrainian name and a category SUGGESTION per line, with one
/// batched model call for the translation and a few for the decisions. The model
/// only chooses among options the program found in the real category tree (a key
/// it invents is dropped), and "new" can only go under a group that exists, so a
/// bad answer costs a question, never a wrong write. Reads the database, writes
/// nothing.
library;

import '../../data/ai/llm_client.dart';
import '../../data/database.dart';
import 'category_resolver.dart';
import 'model_prompts.dart';

/// What the assistant proposes for one receipt line.
class LineSuggestion {
  const LineSuggestion({
    required this.uaName,
    this.categoryId,
    this.groupId,
    this.confidence = 0,
    this.grams,
  });

  /// The product in the user's language (the printed name when not translated).
  final String uaName;

  /// An existing category that fits.
  final String? categoryId;

  /// For a NEW category: the existing group it goes under (named [uaName]).
  final String? groupId;
  final double confidence;

  /// The model's estimate of the weight of one pack, in grams (a guess).
  final double? grams;

  bool get isNew => categoryId == null && groupId != null;
  bool get hasPick => categoryId != null || groupId != null;

  Map<String, dynamic> toJson() => {
    'ua': uaName,
    'category_id': categoryId,
    'group_id': groupId,
    'confidence': confidence,
    'grams': grams,
  };

  factory LineSuggestion.fromJson(Map<String, dynamic> j) => LineSuggestion(
    uaName: (j['ua'] ?? '').toString(),
    categoryId: j['category_id']?.toString(),
    groupId: j['group_id']?.toString(),
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
    grams: (j['grams'] as num?)?.toDouble(),
  );
}

final _cyrillic = RegExp(r'[Ѐ-ӿ]');

class ItemSuggester {
  ItemSuggester({required this.llm, required this.resolver, this.chunk = 8});

  final LlmClient llm;
  final CategoryResolver resolver;

  /// Items per decision call: small enough for a 7B model on a CPU.
  final int chunk;

  /// [items] are (line index, printed name). Throws when the model cannot be
  /// reached, so the caller can fall back to asking and not retry on every rebuild.
  Future<Map<int, LineSuggestion>> suggest({
    required List<({int index, String printed})> items,
    required List<BudgetCategory> cats,
    String? merchant,
  }) async {
    if (items.isEmpty) return const {};

    // 1. One call: printed names -> Ukrainian names. A name already written in
    // Cyrillic (a typed message) is the user's own word and is never translated.
    final foreign = [
      for (var i = 0; i < items.length; i++)
        if (!_cyrillic.hasMatch(items[i].printed)) i,
    ];
    final ua = <int, String>{};
    if (foreign.isNotEmpty) {
      final reply = await llm.runPrompt(
        translateItemsPrompt(
          items: [for (final i in foreign) (n: i + 1, name: items[i].printed)],
          merchant: merchant,
        ),
      );
      ua.addAll(parseTranslatedItems(reply));
    }

    // 2. The existing categories that may fit each translation.
    final byId = {for (final c in cats) c.id: c};
    final children = <String, List<BudgetCategory>>{};
    for (final c in cats) {
      final p = c.parentId;
      if (p != null && byId.containsKey(p)) (children[p] ??= []).add(c);
    }
    bool isWrapper(BudgetCategory c) {
      final key = CategoryResolver.nameKey(c.name);
      return (children[c.id] ?? const []).any(
        (k) => CategoryResolver.nameKey(k.name) == key,
      );
    }

    final groups = <CandidateCategory>[
      for (final c
          in ([
            for (final c in cats)
              if (children.containsKey(c.id) && !isWrapper(c)) c,
          ]..sort((a, b) {
            final byKids = children[b.id]!.length.compareTo(children[a.id]!.length);
            return byKids != 0 ? byKids : a.name.compareTo(b.name);
          })))
        CandidateCategory(id: c.id, name: c.name),
    ];

    final decide = <SuggestItem>[];
    for (var i = 0; i < items.length; i++) {
      final name = ua[i + 1] ?? items[i].printed;
      final seen = <String>{};
      final options = <CandidateCategory>[];
      for (final r in [
        await resolver.resolve(name, limit: 6),
        await resolver.resolve(items[i].printed, limit: 3),
      ]) {
        for (final c in r.candidates) {
          final cat = byId[c.id];
          if (cat == null || !seen.add(c.id)) continue;
          if (c.isAggregate && !isWrapper(cat)) continue; // a group is not a product
          options.add(CandidateCategory(id: c.id, name: c.name));
        }
      }
      decide.add(
        SuggestItem(
          n: i + 1,
          printed: items[i].printed,
          ua: name,
          options: options.take(6).toList(),
        ),
      );
    }

    // 3. A few calls: pick an option or "new" under a group.
    final picks = <int, CategorySuggestion>{};
    for (var s = 0; s < decide.length; s += chunk) {
      final part = decide.sublist(s, (s + chunk).clamp(0, decide.length));
      final r = await llm.runPrompt(
        suggestCategoriesPrompt(items: part, groups: groups, merchant: merchant),
      );
      picks.addAll(parseCategorySuggestions(r, part, groups));
    }

    final out = <int, LineSuggestion>{};
    for (var i = 0; i < items.length; i++) {
      final d = decide[i];
      final p = picks[d.n];
      if (p == null || (p.option == null && p.group == null)) {
        out[items[i].index] = LineSuggestion(uaName: d.ua);
      } else if (p.option != null) {
        out[items[i].index] = LineSuggestion(
          uaName: d.ua,
          categoryId: p.option!.id,
          confidence: p.confidence,
          grams: p.grams,
        );
      } else {
        out[items[i].index] = LineSuggestion(
          uaName: p.newName ?? d.ua,
          groupId: p.group!.id,
          confidence: p.confidence,
          grams: p.grams,
        );
      }
    }
    return out;
  }
}
