import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/error_log.dart';
import 'dialog_back.dart';

/// Number of dialogs opened through [showStackedDialog] that are still open.
int _openDialogs = 0;

/// Visible for tests: how many stacked dialogs are currently open.
int get openStackedDialogCount => _openDialogs;

/// Visible for tests: forget dialogs whose futures never completed because
/// the widget tree was torn down mid-test.
void resetStackedDialogsForTest() {
  _openDialogs = 0;
  _saveHooks.clear();
  setDialogBackHandler(false);
}

/// "Write my form if it has unsaved, valid edits" of every open EDIT dialog, in
/// opening order (the last one is the topmost).
final List<Future<void> Function()> _saveHooks = [];

/// An edit dialog calls this in `initState` and [unregisterEditorSaveHook] in
/// `dispose`. [save] must not close the dialog and must not throw for an
/// invalid form (it just does nothing).
void registerEditorSaveHook(Future<void> Function() save) =>
    _saveHooks.add(save);

void unregisterEditorSaveHook(Future<void> Function() save) =>
    _saveHooks.remove(save);

/// True while some edit dialog is open (so an opener knows it has to await).
bool get hasOpenEditors => _saveHooks.isNotEmpty;

/// Call FIRST when another item (action, direction ...) is about to open over
/// the current dialog: the topmost edit dialog saves its whole form, so the new
/// dialog loads the saved row. Lower dialogs were saved when the one above them
/// opened. A failed save never blocks opening.
Future<void> saveOpenEditorBeforeOpening() async {
  if (_saveHooks.isEmpty) return;
  try {
    await _saveHooks.last();
  } catch (e, st) {
    ErrorLog.write(e, st, context: 'Save before opening');
  }
}

/// Like [showDialog], but only the bottom-most dialog dims the background.
/// Dialogs opened over another one get a transparent barrier (which still
/// blocks taps on the layers below), so the background keeps the same
/// darkness however many dialogs are stacked. The bottom-most dialog also
/// frosts the page behind it with ONE live blur (the only `BackdropFilter` in
/// the app: a dialog floats over real content, so the pre-rendered glass
/// background used elsewhere would not do).
Future<T?> showStackedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final isFirst = _openDialogs == 0;
  _openDialogs++;
  setDialogBackHandler(true);
  try {
    return showDialog<T>(
      context: context,
      builder: isFirst
          ? (ctx) => Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                builder(ctx),
              ],
            )
          : builder,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      // A soft navy veil instead of the default black one, so the frosted
      // page behind the dialog keeps its light colours.
      barrierColor: !isFirst
          ? Colors.transparent
          : Theme.of(context).brightness == Brightness.dark
          ? const Color(0x73050A18)
          : const Color(0x401E293B),
    ).whenComplete(() {
      if (_openDialogs > 0) _openDialogs--;
      if (_openDialogs == 0) setDialogBackHandler(false);
    });
  } catch (_) {
    _openDialogs--;
    if (_openDialogs == 0) setDialogBackHandler(false);
    rethrow;
  }
}
