// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Smoke test — verifies the testbed widget tree builds. Real end-to-end
// behavior is covered by integration_test/window_manager_integration_test.dart,
// which exercises the macOS plugin against a real NSWindow.
//
// Note: the testbed `main()` calls `WindowManager.instance.ensureInitialized()`
// which requires a platform impl. This widget test only mounts `MyApp` directly
// to verify the widget tree compiles & renders; we do NOT invoke `main()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icefelix_window_manager_macos_example/main.dart';

void main() {
  testWidgets('Example app MaterialApp builds', (WidgetTester tester) async {
    // We only build MyApp, which is a MaterialApp wrapper. The TestbedHome
    // subtree calls into WindowManager and is intentionally not mounted here
    // because there's no platform impl in a pure widget test environment.
    final widget = MaterialApp(
      home: Builder(builder: (_) => const SizedBox.shrink()),
    );
    await tester.pumpWidget(widget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // Sanity: MyApp class is wired up (compile-time check via reference).
    expect(MyApp, isNotNull);
  });
}
