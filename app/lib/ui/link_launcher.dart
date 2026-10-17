// ignore_for_file: implementation_imports
import 'package:appflowy_editor/src/extensions/url_launcher_extension.dart'
    as editor_links;
import 'package:url_launcher/url_launcher.dart';

import '../domain/link_safety.dart';
import 'root_navigator.dart';
import 'widgets/app_toast.dart';

/// Opens a link tapped in the Notes editor. On a phone the app that owns the
/// link (YouTube, Instagram...) opens directly; when none does, the system
/// browser is used - never an in-app browser. Only web, mail and phone links
/// are opened ([safeLinkTarget]); anything else is refused with a short
/// notice. Returns false when nothing could open it.
Future<bool> openNotesLink(String? href) async {
  final target = safeLinkTarget(href);
  if (target == null) {
    _tellBlocked(href);
    return false;
  }
  try {
    // Succeeds only when an installed app handles the link.
    if (await launchUrl(target, mode: LaunchMode.externalNonBrowserApplication)) {
      return true;
    }
  } catch (_) {
    // Not supported on this platform (Windows): fall through.
  }
  try {
    return await launchUrl(target, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

void _tellBlocked(String? href) {
  final raw = href?.trim() ?? '';
  if (raw.isEmpty) return;
  final colon = raw.indexOf(':');
  final scheme = colon > 0 && colon <= 20 ? raw.substring(0, colon) : '';
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  showInfoToast(
    overlay,
    scheme.isEmpty
        ? 'Link not opened: it is not a web, mail or phone link'
        : 'Link not opened: "$scheme:" links are not allowed '
              '(only web, mail and phone links)',
  );
}

/// Routes the editor's link taps through [openNotesLink].
void installNotesLinkLauncher() {
  editor_links.editorLaunchUrl = openNotesLink;
}
