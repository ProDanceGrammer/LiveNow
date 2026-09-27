import 'package:flutter/material.dart';

import '../providers.dart';
import '../widgets/action_list_view.dart';

/// Every action regardless of status (open, done, or cancelled) — the one
/// place to see everything, most recently updated first.
class AllActionsView extends StatelessWidget {
  const AllActionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionListView(
      provider: allActionsProvider,
      emptyMessage: 'No actions yet.',
    );
  }
}
