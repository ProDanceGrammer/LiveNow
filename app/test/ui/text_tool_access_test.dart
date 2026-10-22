import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/text_tool_access.dart';

void main() {
  // (The test binding keeps semantics on by itself, so the handle is what is
  // asserted, not the global flag.)
  test('the handle is held only while the switch is on, once', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final access = TextToolAccess();
    expect(access.isOn, isFalse);

    access.apply(true);
    access.apply(true); // idempotent: still one handle
    expect(access.isOn, isTrue);

    access.apply(false);
    expect(access.isOn, isFalse);

    access.apply(true);
    access.dispose();
    expect(access.isOn, isFalse);
  });
}
