import 'package:flutter/material.dart';

import '../providers.dart';
import '../widgets/action_list_view.dart';

class TodoView extends StatelessWidget {
  const TodoView({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionListView(
      provider: todoProvider,
      emptyMessage: 'No unscheduled tasks ready to plan.',
    );
  }
}
