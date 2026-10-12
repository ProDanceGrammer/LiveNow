// ignore_for_file: implementation_imports
import 'package:appflowy_editor/src/extensions/url_launcher_extension.dart'
    as editor_links;
import 'package:url_launcher/url_launcher.dart';

/// Opens a link tapped in the Notes editor. On a phone the app that owns the
/// link (YouTube, Instagram...) opens directly; when none does, the system
/// browser is used - never an in-app browser. Returns false when nothing could
/// open it.
Future<bool> openNotesLink(String? href) async {
  if (href == null || href.trim().isEmpty) return false;
  final raw = href.trim();
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  // A link without a scheme ("youtube.com/x") is a web address.
  final target = uri.scheme.isEmpty ? Uri.parse('https://$raw') : uri;
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

/// Routes the editor's link taps through [openNotesLink].
void installNotesLinkLauncher() {
  editor_links.editorLaunchUrl = openNotesLink;
}
