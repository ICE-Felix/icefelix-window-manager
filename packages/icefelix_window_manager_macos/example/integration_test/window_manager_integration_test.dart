// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Integration tests for icefelix_window_manager_macos.
//
// Run from `example/`:
//
//     flutter test integration_test/ -d macos
//
// These open a real NSWindow on the host. Fine for dev machines.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_macos/icefelix_window_manager_macos.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    IcefelixWindowManagerMacos.registerWith();
    await WindowManager.instance.ensureInitialized();
    // Tiny shell so the engine has a widget tree to render.
    runApp(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
  });

  /// Polls until [predicate] returns true on the current snapshot, or fails
  /// after [timeout]. Necessary because native events are coalesced (~10ms)
  /// and dispatched asynchronously from the Swift side.
  Future<void> waitForSnapshot(
    bool Function(WindowSnapshot) predicate, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (predicate(WindowManager.instance.snapshot.value)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail(
      'Snapshot predicate not satisfied within $timeout. '
      'Final snapshot: ${WindowManager.instance.snapshot.value}',
    );
  }

  testWidgets('ensureInitialized returns valid snapshot', (tester) async {
    final snap = WindowManager.instance.snapshot.value;
    expect(snap.bounds.size.width, greaterThan(0));
    expect(snap.bounds.size.height, greaterThan(0));
    expect(snap.currentDisplay.scaleFactor, greaterThan(0));
  });

  testWidgets('setSize updates snapshot bounds within 2s', (tester) async {
    await WindowManager.instance.setSize(const Size(900, 700));
    await waitForSnapshot(
      (s) => s.bounds.size.width == 900 && s.bounds.size.height == 700,
    );
  });

  // NOTE on snapshot reactivity vs. setters:
  //   The macOS Swift impl emits `onSnapshotChanged` only when an NSWindow
  //   notification fires (didResize / didMove / didBecomeKey / didMiniaturize
  //   / didEnterFullScreen / didChangeScreen). Pure-property setters like
  //   setTitle / setAlwaysOnTop / setResizable mutate window state without
  //   triggering any of those notifications, so the Dart-side snapshot never
  //   refreshes from those calls alone (the next snapshot emit will reflect
  //   them once a tracked notification fires for any reason).
  //   Tracked as a follow-up; W2.5 tests only assert that the call completes
  //   without throwing for those setters.
  testWidgets('setTitle completes without throwing', (tester) async {
    await WindowManager.instance.setTitle('Integration Test');
    // No snapshot assertion — see note above.
  });

  testWidgets('setAlwaysOnTop true/false completes without throwing', (
    tester,
  ) async {
    await WindowManager.instance.setAlwaysOnTop(true);
    await WindowManager.instance.setAlwaysOnTop(false);
    // No snapshot assertion — see note above.
  });

  testWidgets('platform.target == TargetPlatform.macOS', (tester) async {
    expect(WindowManager.instance.platform.target, TargetPlatform.macOS);
    // displayServer is Linux-only; null on macOS.
    expect(WindowManager.instance.platform.displayServer, isNull);
  });

  testWidgets('displays.list returns at least one Display with primary', (
    tester,
  ) async {
    final displays = await WindowManager.instance.displays.list();
    expect(displays.length, greaterThanOrEqualTo(1));
    expect(displays.any((d) => d.isPrimary), isTrue);
  });

  testWidgets('minimize then restore round-trip', (tester) async {
    await WindowManager.instance.minimize();
    await waitForSnapshot((s) => s.state == WindowState.minimized);
    await WindowManager.instance.restore();
    await waitForSnapshot((s) => s.state == WindowState.normal);
  });
}
