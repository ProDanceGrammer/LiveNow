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
import 'tr_glossary.dart';

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

  /// Why a model call of the last [suggest] gave nothing (a bad reply: no JSON, an
  /// HTTP error), or null. The names and picks of the other calls are kept.
  String? lastError;

  /// The server itself is not answering (unreachable, an HTTP error): the other
  /// calls would fail the same way, so the whole stage is given up. A reply that
  /// arrives but holds no usable JSON only costs its own call.
  static bool _serverDown(Object e) =>
      e is AiUnreachableException ||
      e is AiCancelledException ||
      (e is AiBadResponseException && e.status != null);

  void _failed(Object e) {
    final text = '${e.runtimeType}: $e';
    lastError = text.length <= 200 ? text : '${text.substring(0, 200)}...';
  }

  /// [items] are (line index, printed name). Throws only when the model cannot be
  /// reached at all (the caller then asks instead and does not retry on every
  /// rebuild). A model that answers badly costs its own call, never the names the
  /// code-side glossary already gave, nor the other calls.
  Future<Map<int, LineSuggestion>> suggest({
    required List<({int index, String printed})> items,
    required List<BudgetCategory> cats,
    String? merchant,
  }) async {
    lastError = null;
    if (items.isEmpty) return const {};

    // 1. One call: printed names -> Ukrainian names. A name already written in
    // Cyrillic (a typed message) is the user's own word and is never translated.
    final foreign = [
      for (var i = 0; i < items.length; i++)
        if (!_cyrillic.hasMatch(items[i].printed)) i,
    ];
    final ua = <int, String>{};
    // What the code-side glossary knows is never asked of the model: a 3B model
    // turned potatoes into bread and put Greek letters into water.
    final unknown = <int>[];
    for (final i in foreign) {
      final known = translateKnown(items[i].printed);
      if (known != null) {
        ua[i + 1] = known;
      } else {
        unknown.add(i);
      }
    }
    if (unknown.isNotEmpty) {
      try {
        final reply = await llm.runPrompt(
          translateItemsPrompt(
            items: [for (final i in unknown) (n: i + 1, name: items[i].printed)],
            merchant: merchant,
          ),
        );
        // Only the names that were asked. Given ONE name, a 3B model answered with a
        // list of ten (its own glossary, in order) and the numbers overwrote the
        // glossary translations of the other lines: a reply with a number nobody
        // asked about is not a translation at all, so none of it is used.
        final asked = {for (final i in unknown) i + 1};
        final got = parseTranslatedItems(reply);
        if (got.keys.every(asked.contains)) ua.addAll(got);
      } on Object catch (e) {
        if (_serverDown(e)) rethrow;
        _failed(e); // the printed names stay; the glossary's names are kept
      }
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
      final gloss = glossaryQuery(items[i].printed);
      for (final r in [
        await resolver.resolve(name, limit: 6),
        if (gloss != null && gloss != name) await resolver.resolve(gloss, limit: 4),
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
      try {
        final r = await llm.runPrompt(
          suggestCategoriesPrompt(items: part, groups: groups, merchant: merchant),
        );
        picks.addAll(parseCategorySuggestions(r, part, groups));
      } on Object catch (e) {
        if (_serverDown(e)) rethrow;
        _failed(e); // no picks for this chunk: those lines are asked, with their names
      }
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
