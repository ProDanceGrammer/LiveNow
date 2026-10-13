import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

// TwemojiFlags first on desktop: Segoe UI Emoji draws a flag as its two
// letters ("UA"); the font only has flag glyphs, so every other emoji falls
// through to the system's colour font.
final _kEmojiFonts = [
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android)
    'TwemojiFlags',
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

TextStyle _badgeStyle(double fontSize) => TextStyle(
  fontSize: fontSize,
  height: 1.25,
  fontFamilyFallback: _kEmojiFonts,
);

/// The chunks side by side with a thin gap (a real space is as wide as half an
/// emoji, which spread the icons far apart).
TextSpan _badgeSpan(List<String> chunks, double fontSize) => TextSpan(
  style: _badgeStyle(fontSize),
  children: [
    for (var i = 0; i < chunks.length; i++) ...[
      if (i > 0) TextSpan(text: ' ', style: TextStyle(fontSize: fontSize * 0.4)),
      TextSpan(text: chunks[i]),
    ],
  ],
);

double _badgeTextWidth(List<String> chunks, double fontSize) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: _badgeSpan(chunks, fontSize),
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

/// Right edge (x) of each chunk of [chunks] in the badge style, cached per
/// (string, font size): measuring is the only expensive part of resolving
/// "which emoji is under the pointer".
final LinkedHashMap<String, List<double>> _edgeCache = LinkedHashMap();
const _kEdgeCacheSize = 256;

List<double> _chunkEdges(String icons, double fontSize) {
  final key = '$fontSize|$icons';
  final hit = _edgeCache.remove(key);
  if (hit != null) {
    _edgeCache[key] = hit; // most recently used last
    return hit;
  }
  final chunks = icons.split(' ');
  final edges = <double>[
    for (var i = 0; i < chunks.length; i++)
      _badgeTextWidth(chunks.sublist(0, i + 1), fontSize),
  ];
  _edgeCache[key] = edges;
  if (_edgeCache.length > _kEdgeCacheSize) {
    _edgeCache.remove(_edgeCache.keys.first);
  }
  return edges;
}

final LinkedHashMap<String, String> _fitCache = LinkedHashMap();

/// [icons] ('A B C D +2') cut to what fits in [maxWidth]: the first emojis
/// that fit, then '+N' for ALL the others (hidden ones and the old '+n').
/// Returns [icons] unchanged when everything fits (or [maxWidth] is null).
String fitDirectionIcons(String icons, double? maxWidth, double fontSize) {
  if (maxWidth == null) return icons;
  final key = '$fontSize|${maxWidth.floor()}|$icons';
  final hit = _fitCache[key];
  if (hit != null) return hit;
  final chunks = icons.split(' ');
  var result = icons;
  if (_badgeTextWidth(chunks, fontSize) > maxWidth) {
    final emoji = [for (final c in chunks) if (!c.startsWith('+')) c];
    var total = emoji.length;
    for (final c in chunks) {
      if (c.startsWith('+')) total += int.tryParse(c.substring(1)) ?? 0;
    }
    result = '+$total';
    for (var k = emoji.length - 1; k >= 0; k--) {
      final cand = [...emoji.take(k), '+${total - k}'];
      if (_badgeTextWidth(cand, fontSize) <= maxWidth) {
        result = cand.join(' ');
        break;
      }
    }
  }
  _fitCache[key] = result;
  if (_fitCache.length > _kEdgeCacheSize) {
    _fitCache.remove(_fitCache.keys.first);
  }
  return result;
}

/// Width the badge for [icons] takes when it may use up to [maxWidth].
double directionBadgeWidth(String icons, double? maxWidth, double fontSize) =>
    _badgeTextWidth(
      fitDirectionIcons(icons, maxWidth, fontSize).split(' '),
      fontSize,
    );

class _Tip {
  final String text;
  final Offset pos;
  const _Tip(this.text, this.pos);
}

/// The direction emojis of an action ('A B +2') in a small colour-emoji font.
///
/// It is always a single [Text] inside a cheap [MouseRegion]. The direction's
/// name appears in ONE lightweight overlay entry (inserted on the first hover
/// after a ~150 ms delay, removed on exit/dispose) for the emoji under the
/// pointer, resolved from the pointer's x against cached chunk widths (the
/// '+n' chunk lists the hidden names). Names are read from
/// [actionDirectionNamesProvider] only while hovering.
class DirectionBadge extends ConsumerStatefulWidget {
  final String actionId;

  /// [actionDirectionIconsProvider]'s string for this action.
  final String icons;
  final double fontSize;

  /// The badge shows only the emojis that fit in this width, then '+N' for the
  /// rest (null = show them all).
  final double? maxWidth;

  const DirectionBadge({
    super.key,
    required this.actionId,
    required this.icons,
    this.fontSize = 11,
    this.maxWidth,
  });

  @override
  ConsumerState<DirectionBadge> createState() => _DirectionBadgeState();
}

class _DirectionBadgeState extends ConsumerState<DirectionBadge> {
  static const _delay = Duration(milliseconds: 150);

  final _tip = ValueNotifier<_Tip?>(null);
  OverlayEntry? _entry;
  Timer? _timer;
  Offset _local = Offset.zero;
  Offset _global = Offset.zero;

  StrutStyle get _strut => StrutStyle(
    fontSize: widget.fontSize,
    height: 1.25,
    forceStrutHeight: true,
  );

  String get _shown =>
      fitDirectionIcons(widget.icons, widget.maxWidth, widget.fontSize);

  _Tip? _resolve() {
    final names = ref.read(actionDirectionNamesProvider)[widget.actionId];
    final original = widget.icons.split(' ');
    if (names == null || names.length != original.length) return null;
    final shown = _shown.split(' ');
    final edges = _chunkEdges(_shown, widget.fontSize);
    var i = edges.indexWhere((e) => _local.dx < e);
    if (i < 0) i = edges.length - 1;
    final isMore = shown[i].startsWith('+');
    // '+N' lists every name that is not drawn.
    return _Tip(isMore ? names.sublist(i).join(', ') : names[i], _global);
  }

  void _refresh() {
    final tip = _resolve();
    if (tip == null) {
      _hide();
    } else {
      _show(tip);
    }
  }

  void _show(_Tip tip) {
    _tip.value = tip;
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: ValueListenableBuilder<_Tip?>(
          valueListenable: _tip,
          builder: (context, tip, _) => tip == null
              ? const SizedBox.shrink()
              : CustomSingleChildLayout(
                  delegate: _TipLayout(tip.pos),
                  child: _TipBox(text: tip.text),
                ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _enter(PointerEnterEvent e) {
    _local = e.localPosition;
    _global = e.position;
    _timer?.cancel();
    _timer = Timer(_delay, () {
      _timer = null;
      if (mounted) _refresh();
    });
  }

  void _hover(PointerHoverEvent e) {
    _local = e.localPosition;
    _global = e.position;
    if (_entry != null) _refresh();
  }

  @override
  void dispose() {
    _hide();
    _tip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _enter,
      onHover: _hover,
      onExit: (_) => _hide(),
      child: Text.rich(
        _badgeSpan(_shown.split(' '), widget.fontSize),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        strutStyle: _strut,
        style: _badgeStyle(widget.fontSize),
      ),
    );
  }
}

class _TipBox extends StatelessWidget {
  final String text;
  const _TipBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(6),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: scheme.onInverseSurface),
        ),
      ),
    );
  }
}

/// Puts the tip just below-right of the pointer, kept inside the overlay.
class _TipLayout extends SingleChildLayoutDelegate {
  final Offset pointer;
  const _TipLayout(this.pointer);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = math.max(
      0.0,
      math.min(pointer.dx + 12, size.width - childSize.width),
    );
    final y = math.max(
      0.0,
      math.min(pointer.dy + 18, size.height - childSize.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TipLayout old) => old.pointer != pointer;
}
