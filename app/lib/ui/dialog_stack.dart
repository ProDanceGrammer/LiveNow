import 'package:flutter/material.dart';

/// Number of dialogs opened through [showStackedDialog] that are still open.
int _openDialogs = 0;

/// Visible for tests: how many stacked dialogs are currently open.
int get openStackedDialogCount => _openDialogs;

/// Visible for tests: forget dialogs whose futures never completed because
/// the widget tree was torn down mid-test.
void resetStackedDialogsForTest() => _openDialogs = 0;

/// Like [showDialog], but only the bottom-most dialog dims the background.
/// Dialogs opened over another one get a transparent barrier (which still
/// blocks taps on the layers below), so the background keeps the same
/// darkness however many dialogs are stacked.
Future<T?> showStackedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final isFirst = _openDialogs == 0;
  _openDialogs++;
  try {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      barrierColor: isFirst ? null : Colors.transparent,
    ).whenComplete(() {
      if (_openDialogs > 0) _openDialogs--;
    });
  } catch (_) {
    _openDialogs--;
    rethrow;
  }
}
