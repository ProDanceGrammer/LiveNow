import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

const _kEmojiFonts = [
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

/// Right edge (x) of each space-separated chunk of [icons] when painted in
/// the badge style, cached per (string, font size): measuring is the only
/// expensive part of resolving "which emoji is under the pointer".
final LinkedHashMap<String, List<double>> _edgeCache = LinkedHashMap();
const _kEdgeCacheSize = 256;

List<double> _chunkEdges(String icons, double fontSize, TextStyle style) {
  final key = '$fontSize|$icons';
  final hit = _edgeCache.remove(key);
  if (hit != null) {
    _edgeCache[key] = hit; // most recently used last
    return hit;
  }
  final chunks = icons.split(' ');
  final edges = <double>[];
  final painter = TextPainter(textDirection: TextDirection.ltr);
  var prefix = '';
  for (var i = 0; i < chunks.length; i++) {
    prefix = i == 0 ? chunks[0] : '$prefix ${chunks[i]}';
    painter.text = TextSpan(text: prefix, style: style);
    painter.layout();
    edges.add(painter.width);
  }
  painter.dispose();
  _edgeCache[key] = edges;
  if (_edgeCache.length > _kEdgeCacheSize) {
    _edgeCache.remove(_edgeCache.keys.first);
  }
  return edges;
}

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

  const DirectionBadge({
    super.key,
    required this.actionId,
    required this.icons,
    this.fontSize = 11,
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

  TextStyle get _style => TextStyle(
    fontSize: widget.fontSize,
    height: 1.25,
    fontFamilyFallback: _kEmojiFonts,
  );

  _Tip? _resolve() {
    final names = ref.read(actionDirectionNamesProvider)[widget.actionId];
    final chunks = widget.icons.split(' ');
    if (names == null || names.length != chunks.length) return null;
    final edges = _chunkEdges(widget.icons, widget.fontSize, _style);
    var i = edges.indexWhere((e) => _local.dx < e);
    if (i < 0) i = edges.length - 1;
    return _Tip(names[i], _global);
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
      child: Text(
        widget.icons,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        strutStyle: _strut,
        style: _style,
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
