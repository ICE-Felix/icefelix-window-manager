// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';

class _FakePlatform extends WindowManagerPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowManagerPlatform', () {
    test('default instance throws UnimplementedError on any method', () {
      WindowManagerPlatform.instance = _FakePlatform();

      expect(
        () => WindowManagerPlatform.instance.ensureInitialized(),
        throwsA(isA<UnimplementedError>()),
      );
      expect(
        () => WindowManagerPlatform.instance.minimize(),
        throwsA(isA<UnimplementedError>()),
      );
      expect(
        () => WindowManagerPlatform.instance.startDrag(),
        throwsA(isA<UnimplementedError>()),
      );
      expect(
        () => WindowManagerPlatform.instance.destroy(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('instance setter accepts subclass implementations', () {
      final fake = _FakePlatform();
      WindowManagerPlatform.instance = fake;
      expect(identical(WindowManagerPlatform.instance, fake), isTrue);
    });
  });
}
