import 'package:flutter/material.dart';

/// A small round check indicator: a circle outlined in [color], filled with a
/// check mark (drawn in [checkColor]) when [value] is true. The tappable area
/// is an opaque [hit]-sized box around the [size] circle. Cheap on purpose:
/// one DecoratedBox and at most one Icon, no ink or theme lookups.
class RoundCheck extends StatelessWidget {
  final bool value;
  final Color color;
  final Color checkColor;
  final VoidCallback onTap;
  final double size;
  final double hit;

  const RoundCheck({
    super.key,
    required this.value,
    required this.color,
    required this.checkColor,
    required this.onTap,
    this.size = 14,
    this.hit = 18,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? color : null,
              border: Border.all(color: color, width: 1.5),
            ),
            child: SizedBox(
              width: size,
              height: size,
              child: value
                  ? Icon(Icons.check, size: size - 4, color: checkColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
