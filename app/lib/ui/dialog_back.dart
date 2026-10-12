import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'root_navigator.dart';
import 'undo.dart';
import 'widgets/app_toast.dart' show rootOverlayOf;

/// The mouse's Back button closes the top dialog, like Escape. A dialog that
/// holds an unsaved form implements [DraftDialog]: closing it this way offers
/// an Undo that opens it again with exactly the edits it had (nothing is
/// offered when nothing was changed).

/// A dialog State that can close itself on Back and be reopened with its edits.
abstract class DraftDialog {
  /// Called when the Back button hits this dialog (it is the top one).
  void closeByBack();
}

final _drafts = <(Route<dynamic>, DraftDialog)>[];

/// Registers [dialog] (call from `didChangeDependencies`, once) so the Back
/// button can reach it; [unregisterDraftDialog] on dispose.
void registerDraftDialog(Route<dynamic>? route, DraftDialog dialog) {
  if (route == null) return;
  if (_drafts.any((d) => identical(d.$2, dialog))) return;
  _drafts.add((route, dialog));
}

void unregisterDraftDialog(DraftDialog dialog) =>
    _drafts.removeWhere((d) => identical(d.$2, dialog));

/// Closes the dialog of [context] and, when [draft] is not null (something was
/// changed), offers "Undo" in the undo history: it calls [reopen] with the
/// root navigator's context. Everything is read before the pop (the dialog's
/// own context is gone afterwards).
void closeDraftDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String label,
  required Object? draft,
  required void Function(BuildContext rootContext, Object draft) reopen,
}) {
  final overlay = rootOverlayOf(context);
  final history = ref.read(undoHistoryProvider.notifier);
  Navigator.of(context, rootNavigator: true).pop();
  if (draft == null) return;
  offerUndo(overlay, history, 'Closed $label', () async {
    final root = rootNavigatorKey.currentContext;
    if (root != null && root.mounted) reopen(root, draft);
  });
}

bool _handlerOn = false;

void _onPointer(PointerEvent e) {
  if (e is! PointerDownEvent ||
      e.kind != PointerDeviceKind.mouse ||
      e.buttons & kBackMouseButton == 0) {
    return;
  }
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  Route<dynamic>? top;
  nav.popUntil((r) {
    top = r;
    return true;
  });
  final route = top;
  if (route == null) return;
  for (final d in _drafts.reversed) {
    if (identical(d.$1, route)) {
      d.$2.closeByBack();
      return;
    }
  }
  // Any other dialog or menu: close it; never the page underneath.
  if (route is PopupRoute) nav.pop();
}

/// Called by `showStackedDialog` while at least one dialog is open.
void setDialogBackHandler(bool on) {
  if (on == _handlerOn) return;
  _handlerOn = on;
  final router = GestureBinding.instance.pointerRouter;
  if (on) {
    router.addGlobalRoute(_onPointer);
  } else {
    router.removeGlobalRoute(_onPointer);
  }
}
