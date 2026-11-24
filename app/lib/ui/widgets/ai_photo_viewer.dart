import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_history_loader.dart' show aiBlobFetcherProvider;
import '../dialog_stack.dart';

/// One photo of a message: its bytes when they are still on this device, else
/// the blob id to fetch from the hub when its page is first shown.
class AiPhotoRef {
  const AiPhotoRef.local(Uint8List this.bytes) : blobId = null;
  const AiPhotoRef.hub(String this.blobId) : bytes = null;

  final Uint8List? bytes;
  final String? blobId;
}

/// Opens the full-screen photo viewer at [initialIndex].
Future<void> showAiPhotoViewer(
  BuildContext context,
  List<AiPhotoRef> photos,
  int initialIndex,
) {
  return showStackedDialog<void>(
    context: context,
    builder: (_) => AiPhotoViewer(photos: photos, initialIndex: initialIndex),
  );
}

enum _Load { loading, done, missing }

/// Full-screen photos: swipe, < > buttons or arrow keys to change, pinch to
/// zoom (swiping is off while zoomed), x or Esc to close.
class AiPhotoViewer extends ConsumerStatefulWidget {
  const AiPhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  final List<AiPhotoRef> photos;
  final int initialIndex;

  @override
  ConsumerState<AiPhotoViewer> createState() => _AiPhotoViewerState();
}

class _AiPhotoViewerState extends ConsumerState<AiPhotoViewer> {
  late final PageController _pages;
  late int _index;
  bool _zoomed = false;
  final _controllers = <int, TransformationController>{};
  final _bytes = <int, Uint8List>{};
  final _state = <int, _Load>{};

  int get _count => widget.photos.length;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _count == 0 ? 0 : _count - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _controllerOf(int i) {
    return _controllers.putIfAbsent(i, () {
      final c = TransformationController();
      c.addListener(() {
        if (i != _index) return;
        final zoomed = c.value.storage[0] > 1.01;
        if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
      });
      return c;
    });
  }

  void _ensureLoaded(int i) {
    if (_state.containsKey(i)) return;
    final photo = widget.photos[i];
    if (photo.bytes != null) {
      _bytes[i] = photo.bytes!;
      _state[i] = _Load.done;
      return;
    }
    _state[i] = _Load.loading;
    final fetch = ref.read(aiBlobFetcherProvider);
    () async {
      Uint8List? got;
      try {
        got = await fetch(photo.blobId!);
      } catch (_) {
        got = null;
      }
      if (!mounted) return;
      setState(() {
        if (got == null) {
          _state[i] = _Load.missing;
        } else {
          _bytes[i] = got;
          _state[i] = _Load.done;
        }
      });
    }();
  }

  void _onPage(int i) {
    // Leaving a page resets its zoom.
    _controllers[_index]?.value = Matrix4.identity();
    setState(() {
      _index = i;
      _zoomed = false;
    });
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= _count) return;
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _close() => Navigator.of(context).pop();

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _page(int i) {
    _ensureLoaded(i);
    final state = _state[i]!;
    Widget child;
    switch (state) {
      case _Load.loading:
        child = const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      case _Load.missing:
        child = const Center(
          child: Text(
            'The original is not available from the hub',
            style: TextStyle(color: Colors.white70),
          ),
        );
      case _Load.done:
        child = InteractiveViewer(
          transformationController: _controllerOf(i),
          maxScale: 6,
          child: Center(
            child: Image.memory(
              _bytes[i]!,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Colors.white70,
              ),
            ),
          ),
        );
    }
    return KeyedSubtree(key: ValueKey('ai-photo-page-$i'), child: child);
  }

  Widget _navButton(Key key, IconData icon, int delta, {required bool left}) {
    return Positioned(
      left: left ? 8 : null,
      right: left ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: IconButton(
          key: key,
          icon: Icon(icon, size: 36),
          color: Colors.white,
          style: IconButton.styleFrom(backgroundColor: Colors.black54),
          onPressed: () => _go(delta),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final several = _count > 1;
    return Dialog.fullscreen(
      key: const ValueKey('ai-photo-viewer'),
      backgroundColor: Colors.black,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: _count,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: _onPage,
                itemBuilder: (_, i) => _page(i),
              ),
              if (several && _index > 0)
                _navButton(
                  const ValueKey('ai-photo-prev'),
                  Icons.chevron_left,
                  -1,
                  left: true,
                ),
              if (several && _index < _count - 1)
                _navButton(
                  const ValueKey('ai-photo-next'),
                  Icons.chevron_right,
                  1,
                  left: false,
                ),
              if (several)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        '${_index + 1} / $_count',
                        key: const ValueKey('ai-photo-counter'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  key: const ValueKey('ai-photo-close'),
                  icon: const Icon(Icons.close, size: 28),
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: _close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
