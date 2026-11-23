import 'package:flutter/material.dart';

import '../screens/ai_threads_screen.dart';

/// App-bar button that opens the assistant (chat list) from any section.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('ai-chat-button'),
    tooltip: 'Assistant',
    icon: const Icon(Icons.chat_bubble_outline),
    onPressed: () => AiThreadsScreen.open(context),
  );
}
