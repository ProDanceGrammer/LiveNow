import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows only: brings this app's window to the front (restoring it when it
/// is minimized). A tapped notification must make the app visible, not just
/// open an editor in a window nobody can see. `SetForegroundWindow` alone is
/// often refused for a background process, so the thread input of the current
/// foreground window is attached for a moment, and as a last resort the window
/// is flipped topmost and back. Never throws; false = nothing could be done.
///
/// Only the window of process [pid] (default: this process) is touched, so a
/// second running copy of the app is never raised by mistake.
bool bringWindowToFront({int? pid}) {
  if (!Platform.isWindows) return false;
  final className = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    final wanted = pid ?? GetCurrentProcessId();
    var hwnd = 0;
    var previous = 0;
    while (true) {
      previous = FindWindowEx(0, previous, className, nullptr);
      if (previous == 0) break;
      GetWindowThreadProcessId(previous, owner);
      if (owner.value == wanted) {
        hwnd = previous;
        break;
      }
    }
    if (hwnd == 0) return false;

    if (IsIconic(hwnd) != 0) ShowWindow(hwnd, SW_RESTORE);

    final foreground = GetForegroundWindow();
    var attached = false;
    final me = GetCurrentThreadId();
    int? other;
    if (foreground != 0 && foreground != hwnd) {
      other = GetWindowThreadProcessId(foreground, nullptr);
      if (other != 0 && other != me) {
        attached = AttachThreadInput(me, other, TRUE) != 0;
      }
    }
    try {
      BringWindowToTop(hwnd);
      SetForegroundWindow(hwnd);
    } finally {
      if (attached) AttachThreadInput(me, other!, FALSE);
    }

    if (GetForegroundWindow() != hwnd) {
      // Flip topmost and back: raises the window above the others.
      const flags = SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW;
      SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags);
      SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, flags);
    }
    return true;
  } catch (_) {
    return false;
  } finally {
    calloc.free(className);
    calloc.free(owner);
  }
}
