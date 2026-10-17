/// Which links a tapped note may open. A note can arrive from a sync, a backup
/// or a CSV, so its links are untrusted: opening `file:` (a program, or an SMB
/// share that leaks the Windows password hash) or an app-specific scheme
/// (`ms-msdt:`, `search-ms:`...) must never be one tap away.
const allowedLinkSchemes = {'http', 'https', 'mailto', 'tel'};

/// The address to open for [href], or null when it must not be opened. A link
/// without a scheme ("youtube.com/x") is a web address and gets `https://`.
Uri? safeLinkTarget(String? href) {
  final raw = href?.trim() ?? '';
  if (raw.isEmpty || raw.length > 4096) return null;
  if (raw.codeUnits.any((u) => u < 0x20 || u == 0x7f)) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme.isEmpty) {
    // "host:8080/x" and "C:\x" parse WITH a scheme above, so an empty scheme
    // here is a plain relative text: treat it as a web address.
    final web = Uri.tryParse('https://$raw');
    return web != null && web.host.isNotEmpty ? web : null;
  }
  if (!allowedLinkSchemes.contains(uri.scheme.toLowerCase())) return null;
  if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isEmpty) {
    return null;
  }
  return uri;
}
