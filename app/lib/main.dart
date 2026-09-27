import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/postpone_rules.dart';
import 'ui/screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initPostponeTimeZoneData();
  runApp(const ProviderScope(child: LiveNowApp()));
}

class LiveNowApp extends StatelessWidget {
  const LiveNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveNow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
