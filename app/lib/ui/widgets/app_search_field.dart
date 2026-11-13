import 'package:flutter/material.dart';

import '../../core/platform_info.dart';

/// The one search field of the app: a [TextField] with an X at the end. The X
/// shows while there is text (always when [onClose] is set, i.e. the search
/// can be closed); a tap clears the text, reports `''` through [onChanged],
/// hides the keyboard (phones; a desktop field keeps the focus unless it
/// closes) and then calls [onClose]. [decoration] is the field's own
/// look (hint, label, prefix); only its `suffixIcon` is taken over.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.onClose,
    this.autofocus = false,
    this.style,
    this.textInputAction,
    this.clearKey,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Set when the search can be closed (a toggled search bar): the X then
  /// always shows and closes it after clearing.
  final VoidCallback? onClose;
  final bool autofocus;
  final TextStyle? style;
  final TextInputAction? textInputAction;

  /// Key of the X button (tests).
  final Key? clearKey;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    // On a phone the point is to get the keyboard out of the way; on a desktop
    // the field keeps the focus so the next search can be typed at once.
    if (!isDesktopPlatform || widget.onClose != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      style: widget.style,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: widget.decoration.copyWith(
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, v, _) => v.text.isEmpty && widget.onClose == null
              ? const SizedBox.shrink()
              : IconButton(
                  key: widget.clearKey,
                  tooltip: widget.onClose == null ? 'Clear' : 'Close search',
                  icon: const Icon(Icons.close),
                  onPressed: _clear,
                ),
        ),
      ),
    );
  }
}
