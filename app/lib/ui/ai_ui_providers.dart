import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/capped_read.dart';
import '../data/database.dart';
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

/// The photo blob of a message (thumbnail data), if it is still on this device.
final aiBlobOfMessageProvider = StreamProvider.autoDispose
    .family<AiBlob?, String>((ref, messageId) {
      final db = ref.watch(databaseProvider);
      return (db.select(db.aiBlobsTable)
            ..where((t) => t.messageId.equals(messageId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(1))
          .watchSingleOrNull();
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

/// Asks for a picture and returns its original bytes (null = cancelled). A
/// provider so tests replace the native dialogs. Phones: camera or gallery;
/// desktop: a file dialog.
final aiPhotoPickerProvider =
    Provider<Future<Uint8List?> Function(AiPhotoSource)>(
      (ref) => (source) async {
        if (source == AiPhotoSource.file) {
          final file = await openFile(
            acceptedTypeGroups: const [
              XTypeGroup(
                label: 'Image',
                extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'heic'],
                uniformTypeIdentifiers: ['public.image'],
                mimeTypes: ['image/*'],
              ),
            ],
          );
          return file == null
              ? null
              : readBytesCapped(file, maxBytes: kMaxPhotoInputBytes);
        }
        final picked = await ImagePicker().pickImage(
          source: source == AiPhotoSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
        );
        return picked == null
            ? null
            : readBytesCapped(picked, maxBytes: kMaxPhotoInputBytes);
      },
    );

/// Resizes a picked photo (CPU heavy, so off the UI isolate by default). Tests
/// replace it with a synchronous function.
final aiPhotoPrepProvider =
    Provider<Future<PreparedPhoto> Function(Uint8List)>(
      (ref) =>
          (bytes) => compute<Uint8List, PreparedPhoto>(_prep, bytes),
    );

PreparedPhoto _prep(Uint8List b) => prepareReceiptPhoto(b);
