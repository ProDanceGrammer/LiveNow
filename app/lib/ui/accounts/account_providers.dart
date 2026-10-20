import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the open account may sync with the hub (QR pairing). True by default
/// (tests, and an app without the gate); the account gate overrides it per
/// account: only the main account, the one that adopted the original data,
/// syncs until the hub has accounts of its own. For any other account sync never
/// starts (no PC server, no phone client) and its UI is replaced by a note.
final syncAllowedProvider = Provider<bool>((ref) => true);
