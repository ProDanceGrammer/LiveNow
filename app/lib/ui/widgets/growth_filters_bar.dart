import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/growth_rules.dart';
import '../growth_filters.dart';
import '../layout.dart';
import '../theme/glass_theme.dart';

/// The filters on one row on a desktop; on a phone the search field gets a row
/// of its own and the dropdowns share the next one. The first child must be an
/// `Expanded` (the search field); `SizedBox` children are spacers.
Widget growthFilterFlow(bool phone, List<Widget> kids) {
  if (!phone) return Row(children: kids);
  final search = (kids.first as Expanded).child;
  final rest = [
    for (final w in kids.skip(1))
      if (w is! SizedBox) w,
  ];
  return Column(
    children: [
      search,
      const SizedBox(height: 6),
      Row(
        children: [
          for (var i = 0; i < rest.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: rest[i]),
          ],
        ],
      ),
    ],
  );
}

/// The search field and the type dropdown the List and Treemap tabs share
/// ([growthSearchProvider], [growthKindProvider]). [beforeKind] are extra
/// controls placed between them (the List's sort).
class GrowthFiltersBar extends ConsumerStatefulWidget {
  const GrowthFiltersBar({super.key, this.beforeKind = const []});

  final List<Widget> beforeKind;

  @override
  ConsumerState<GrowthFiltersBar> createState() => _GrowthFiltersBarState();
}

class _GrowthFiltersBarState extends ConsumerState<GrowthFiltersBar> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    // The text outlives a tab switch: start from what the other tab typed.
    _search = TextEditingController(text: ref.read(growthSearchProvider));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(growthSearchProvider, (_, v) {
      if (_search.text != v) _search.text = v;
    });
    final kind = ref.watch(growthKindProvider);
    final phone = usePhoneLayout(context);
    return growthFilterFlow(phone, [
      Expanded(
        child: TextField(
          key: const ValueKey('growth-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => ref.read(growthSearchProvider.notifier).state = v,
        ),
      ),
      for (final w in widget.beforeKind) ...[const SizedBox(width: 12), w],
      const SizedBox(width: 12),
      DropdownButton<MetricKind?>(
        key: const ValueKey('growth-kind'),
        isExpanded: phone,
        dropdownColor: context.glass.fillDialog,
        borderRadius: BorderRadius.circular(14),
        value: kind,
        items: const [
          DropdownMenuItem(value: null, child: Text('All types')),
          DropdownMenuItem(value: MetricKind.count, child: Text('Actions')),
          DropdownMenuItem(value: MetricKind.hours, child: Text('Hours')),
          DropdownMenuItem(value: MetricKind.boolean, child: Text('Boolean')),
        ],
        onChanged: (v) => ref.read(growthKindProvider.notifier).state = v,
      ),
    ]);
  }
}
