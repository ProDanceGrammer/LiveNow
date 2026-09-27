import 'package:flutter/material.dart';

import '../providers.dart';
import '../widgets/action_list_view.dart';

class MostImportantView extends StatelessWidget {
  const MostImportantView({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionListView(
      provider: mostImportantProvider,
      emptyMessage: 'Nothing ready to schedule right now.',
    );
  }
}
