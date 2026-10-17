import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/link_safety.dart';

void main() {
  group('safeLinkTarget', () {
    test('opens web, mail and phone links', () {
      expect(safeLinkTarget('https://example.com/a?b=1')?.host, 'example.com');
      expect(safeLinkTarget('http://example.com')?.scheme, 'http');
      expect(safeLinkTarget('HTTPS://Example.com')?.scheme, 'https');
      expect(safeLinkTarget('mailto:me@example.com')?.scheme, 'mailto');
      expect(safeLinkTarget('tel:+905551112233')?.scheme, 'tel');
      expect(safeLinkTarget('  https://example.com  ')?.host, 'example.com');
    });

    test('a link without a scheme is a web address', () {
      expect(safeLinkTarget('youtube.com/watch?v=x')?.toString(),
          'https://youtube.com/watch?v=x');
      expect(safeLinkTarget('www.example.com')?.host, 'www.example.com');
    });

    test('refuses files, programs, scripts and app-specific schemes', () {
      for (final h in [
        'file:///C:/Windows/System32/calc.exe',
        'file://attacker/share/x.lnk',
        'javascript:alert(1)',
        'data:text/html,<script>1</script>',
        'ms-msdt:/id PCWDiagnostic',
        'search-ms:query=x&crumb=location:\\\\evil\\share',
        'ftp://example.com/x',
        'obsidian://open?vault=x',
        'vbscript:msgbox(1)',
      ]) {
        expect(safeLinkTarget(h), isNull, reason: h);
      }
    });

    test('refuses empty, control-character, hostless and oversized input', () {
      expect(safeLinkTarget(null), isNull);
      expect(safeLinkTarget(''), isNull);
      expect(safeLinkTarget('   '), isNull);
      expect(safeLinkTarget('https://exa\nmple.com'), isNull);
      expect(safeLinkTarget('https:///nohost'), isNull);
      expect(safeLinkTarget('//evil.com/x'), isNull);
      expect(safeLinkTarget('https://example.com/${'a' * 5000}'), isNull);
    });
  });
}
