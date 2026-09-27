import 'package:flutter/material.dart';

import '../providers.dart';
import '../widgets/action_list_view.dart';

class OperationalView extends StatelessWidget {
  const OperationalView({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionListView(
      provider: operationalProvider,
      emptyMessage: 'Nothing scheduled for today.',
    );
  }
}
