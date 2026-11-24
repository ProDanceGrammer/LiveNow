import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livenow_clipboard/livenow_clipboard.dart';
import 'package:pasteboard/pasteboard.dart';

import '../core/capped_read.dart';
import '../data/database.dart';
import '../domain/ai/ai_chat_service.dart' show AiChatService;
import '../domain/ai/ai_protocol.dart';
import '../domain/ai/photo_prep.dart';
import 'providers.dart';
import 'sync_providers.dart';

/// True on a real phone (camera available). Not the layout: a narrow Windows
/// window uses the phone layout but has no camera.
bool get aiHasCamera => Platform.isIOS || Platform.isAndroid;

/// The assistant needs a hub: this device is paired with one (a desktop
/// connected to a hub, or a phone paired with its sync partner).
final aiHubReadyProvider = Provider<bool>((ref) {
  if (ref.watch(hubConnectedProvider)) return true;
  if (aiHasCamera) {
    return ref.watch(syncClientProvider.select((s) => s.phase)) !=
        SyncPhase.unpaired;
  }
  return false;
});

/// True while the hub cannot be reached (sync offline or failed).
final aiHubUnreachableProvider = Provider<bool>((ref) {
  final phase = ref.watch(syncClientProvider.select((s) => s.phase));
  return phase == SyncPhase.offline || phase == SyncPhase.error;
});

/// How many jobs are still `queued` (the hub has not started them).
final aiQueuedJobCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.aiJobsTable,
  )..where((t) => t.state.equals(AiJobState.queued))).watch().map(
    (r) => r.length,
  );
});

/// The photos of a message in the order they were sent (thumbnail data, still
/// on this device unless the hub has stored them).
final aiBlobsOfMessageProvider = StreamProvider.autoDispose
    .family<List<AiBlob>, String>((ref, messageId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.aiBlobsTable)
            ..where((t) => t.messageId.equals(messageId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch();
    });

/// A batch row (to know whether it was undone).
final aiBatchRowProvider = StreamProvider.autoDispose.family<AiBatch?, String>((
  ref,
  batchId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.aiBatchesTable,
  )..where((t) => t.id.equals(batchId))).watchSingleOrNull();
});

enum AiPhotoSource { camera, gallery, file }

/// Asks for pictures and returns their original bytes (empty = cancelled). A
/// provider so tests replace the native dialogs. Phones: the camera (one
/// photo per tap) or the gallery (several at once); desktop: a file dialog
/// that takes several files.
final aiPhotoPickerProvider =
    Provider<Future<List<Uint8List>> Function(AiPhotoSource)>(
      (ref) => (source) async {
        final List<XFile> files;
        if (source == AiPhotoSource.file) {
          files = await openFiles(
            acceptedTypeGroups: const [
              XTypeGroup(
                label: 'Image',
                extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'heic'],
                uniformTypeIdentifiers: ['public.image'],
                mimeTypes: ['image/*'],
              ),
            ],
          );
        } else if (source == AiPhotoSource.gallery) {
          files = await ImagePicker().pickMultiImage();
        } else {
          final shot = await ImagePicker().pickImage(source: ImageSource.camera);
          files = [?shot];
        }
        return [
          for (final f in files)
            await readBytesCapped(f, maxBytes: kMaxPhotoInputBytes),
        ];
      },
    );

/// The photos on the clipboard. [has] is the cheap check for the "Paste photo"
/// menu item (on iOS it does not read the content, so no "Allow Paste"
/// prompt); [read] returns every image. Tests replace it with a fake.
class ClipboardPhotos {
  const ClipboardPhotos({required this.has, required this.read});
  final Future<bool> Function() has;
  final Future<List<Uint8List>> Function() read;
}

final aiClipboardPhotosProvider = Provider<ClipboardPhotos>(
  (ref) => const ClipboardPhotos(has: _clipboardHas, read: _clipboardRead),
);

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'};

bool _isImagePath(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 && _imageExtensions.contains(path.substring(dot).toLowerCase());
}

Future<bool> _clipboardHas() async {
  if (Platform.isIOS) {
    try {
      return await LivenowClipboard.hasImages();
    } on MissingPluginException {
      // Fall through to the single-image check.
    }
  }
  return (await _clipboardRead()).isNotEmpty;
}

/// iOS: every copied photo. Desktop: image FILES copied in Explorer/Finder
/// (several pictures copy as files), else the one bitmap. Android: one image.
Future<List<Uint8List>> _clipboardRead() async {
  if (Platform.isIOS) {
    try {
      final all = await LivenowClipboard.images();
      if (all.isNotEmpty) return all;
    } on MissingPluginException {
      // An older build without the plugin: one image below.
    }
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final paths = (await Pasteboard.files()).where(_isImagePath).toList();
    if (paths.isNotEmpty) {
      return [
        for (final p in paths)
          await readBytesCapped(XFile(p), maxBytes: kMaxPhotoInputBytes),
      ];
    }
  }
  final one = await Pasteboard.image;
  return one == null ? const [] : [one];
}

// ---- statement files (CSV / XLSX / XLS) ------------------------------------

/// A statement file picked, pasted or opened from another app.
typedef StatementPick = ({String name, Uint8List bytes});

/// Asks for ONE statement file (null = cancelled). A provider so tests replace
/// the native dialog.
final aiStatementPickerProvider =
    Provider<Future<StatementPick?> Function()>((ref) => () async {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Bank statement',
            extensions: ['csv', 'xlsx', 'xls'],
            uniformTypeIdentifiers: [
              'public.comma-separated-values-text',
              'org.openxmlformats.spreadsheetml.sheet',
              'com.microsoft.excel.xls',
            ],
          ),
        ],
      );
      if (file == null) return null;
      return (
        name: file.name,
        bytes: await readBytesCapped(
          file,
          maxBytes: AiChatService.maxStatementBytes,
        ),
      );
    });

/// A statement file on the clipboard. [has] is the cheap check for the "Paste
/// file" menu item; [read] returns the file (null = none). Tests replace it.
class ClipboardStatement {
  const ClipboardStatement({required this.has, required this.read});
  final Future<bool> Function() has;
  final Future<StatementPick?> Function() read;
}

final aiClipboardStatementProvider = Provider<ClipboardStatement>(
  (ref) => const ClipboardStatement(
    has: _clipboardHasStatement,
    read: _clipboardReadStatement,
  ),
);

bool isStatementPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return const {'.csv', '.xlsx', '.xls'}.contains(
    path.substring(dot).toLowerCase(),
  );
}

Future<bool> _clipboardHasStatement() async {
  if (Platform.isIOS) {
    try {
      return await LivenowClipboard.hasFiles();
    } on MissingPluginException {
      return false;
    }
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return (await Pasteboard.files()).any(isStatementPath);
  }
  return false;
}

Future<StatementPick?> _clipboardReadStatement() async {
  if (Platform.isIOS) {
    try {
      final all = await LivenowClipboard.files();
      return all.isEmpty ? null : all.first;
    } on MissingPluginException {
      return null;
    }
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final paths = (await Pasteboard.files()).where(isStatementPath).toList();
    if (paths.isEmpty) return null;
    final file = XFile(paths.first);
    return (
      name: file.name,
      bytes: await readBytesCapped(
        file,
        maxBytes: AiChatService.maxStatementBytes,
      ),
    );
  }
  return null;
}

/// Files another app opens in LiveNow (iOS share sheet / "Open in"): one event
/// per file. On start the file that launched the app is fetched once. Other
/// platforms never emit. Tests override this provider with their own stream.
final incomingStatementProvider = StreamProvider<StatementPick>((ref) {
  if (!Platform.isIOS) return const Stream<StatementPick>.empty();
  final out = StreamController<StatementPick>();
  Future<void> take() async {
    try {
      final f = await LivenowClipboard.takeIncomingFile();
      if (f != null && !out.isClosed) out.add(f);
    } catch (_) {}
  }

  StreamSubscription<void>? sub;
  try {
    sub = LivenowClipboard.onIncomingFile.listen((_) => take());
  } catch (_) {}
  take();
  ref.onDispose(() {
    sub?.cancel();
    out.close();
  });
  return out.stream;
});

/// Resizes a picked photo (CPU heavy, so off the UI isolate by default). Tests
/// replace it with a synchronous function.
final aiPhotoPrepProvider =
    Provider<Future<PreparedPhoto> Function(Uint8List)>(
      (ref) =>
          (bytes) => compute<Uint8List, PreparedPhoto>(_prep, bytes),
    );

PreparedPhoto _prep(Uint8List b) => prepareReceiptPhoto(b);
