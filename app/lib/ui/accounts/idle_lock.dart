import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Minutes of inactivity before an account WITH a password signs itself out
/// (0 = never). The choice lives in the account's own profile folder.
const List<int> kIdleLockOptions = [0, 5, 15, 30, 60];
const int kIdleLockDefaultMinutes = 30;

const String _fileName = 'idle_lock.json';

String _path(Directory dir) => '${dir.path}${Platform.pathSeparator}$_fileName';

/// The saved choice; a missing, damaged or unknown value reads as the default.
Future<int> loadIdleLockMinutes(Directory profileDir) async {
  try {
    final j = jsonDecode(await File(_path(profileDir)).readAsString());
    final m = j is Map ? j['minutes'] : null;
    return m is int && kIdleLockOptions.contains(m)
        ? m
        : kIdleLockDefaultMinutes;
  } on Object {
    return kIdleLockDefaultMinutes;
  }
}

/// Best effort: a failed write never throws into the UI.
Future<void> saveIdleLockMinutes(Directory profileDir, int minutes) async {
  try {
    await profileDir.create(recursive: true);
    await File(_path(profileDir)).writeAsString(jsonEncode({'minutes': minutes}));
  } on Object {
    // The in-memory choice still applies until the app closes.
  }
}

/// Signs the account out ([onLock]) after [timeout] without a pointer or key
/// event. [timeout] null (Off, or an account without a password) never locks.
class IdleLock extends StatefulWidget {
  const IdleLock({
    super.key,
    required this.timeout,
    required this.onLock,
    required this.child,
  });

  final Duration? timeout;
  final VoidCallback onLock;
  final Widget child;

  @override
  State<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<IdleLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  @override
  void didUpdateWidget(IdleLock old) {
    super.didUpdateWidget(old);
    if (old.timeout != widget.timeout) _arm();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _arm();
    return false; // never consumes the key
  }

  void _arm() {
    _timer?.cancel();
    final t = widget.timeout;
    _timer = t == null || t <= Duration.zero
        ? null
        : Timer(t, () {
            _timer = null;
            if (mounted) widget.onLock();
          });
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _arm(),
    onPointerMove: (_) => _arm(),
    onPointerHover: (_) => _arm(),
    onPointerSignal: (_) => _arm(),
    child: widget.child,
  );
}
