// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager_macos/icefelix_window_manager_macos.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IcefelixWindowManagerMacos', () {
    test('registerWith sets WindowManagerPlatform.instance', () {
      IcefelixWindowManagerMacos.registerWith();
      expect(
        WindowManagerPlatform.instance,
        isA<IcefelixWindowManagerMacos>(),
      );
    });
  });
}
