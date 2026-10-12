import 'package:flutter/material.dart';

import '../account_icon_codec.dart';
import 'param_icons.dart';

/// An account's picture (the uploaded square image, rounded) or, when it has
/// none, the purse icon - so an account is recognisable in every list where
/// its name appears.
class AccountIcon extends StatelessWidget {
  const AccountIcon({super.key, this.icon, this.size = 24});

  /// The stored base64 PNG (`BudgetAccount.icon`), or null.
  final String? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeAccountIcon(icon);
    if (bytes == null) {
      return ParamIcon(Param.accounts, size: size, tooltip: false);
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Decode at the shown size (device pixels), not the stored 96.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              ParamIcon(Param.accounts, size: size, tooltip: false),
        ),
      ),
    );
  }
}
