// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Session 1 integration tests for icefelix_window_manager_windows.
// Subset of the 9 macOS tests — covers the bounds vertical that was
// implemented in session 1. The remaining tests (state machine, title,
// alwaysOnTop, minimize/restore round-trip) come back in session 2 when
// those methods are wired.
//
// Run from `example/`:
//
//     flutter test integration_test/ -d windows
//
// These open a real HWND. Fine for dev machines.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_windows/icefelix_window_manager_windows.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    IcefelixWindowManagerWindows.registerWith();
    await WindowManager.instance.ensureInitialized();
    runApp(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
  });

  /// Polls until [predicate] returns true on the current snapshot, or fails
  /// after [timeout]. Native events are coalesced (~10ms via SetTimer +
  /// WM_TIMER) and dispatched asynchronously from the C++ side.
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

  testWidgets('platform.target == TargetPlatform.windows', (tester) async {
    expect(WindowManager.instance.platform.target, TargetPlatform.windows);
    // displayServer is Linux-only; null on Windows.
    expect(WindowManager.instance.platform.displayServer, isNull);
  });

  testWidgets('displays.list returns at least one Display with primary', (
    tester,
  ) async {
    final displays = await WindowManager.instance.displays.list();
    expect(displays.length, greaterThanOrEqualTo(1));
    expect(displays.any((d) => d.isPrimary), isTrue);
  });

  testWidgets('setSize updates snapshot bounds within 2s', (tester) async {
    await WindowManager.instance.setSize(const Size(900, 700));
    await waitForSnapshot(
      // Allow 1-pixel slop from logical→physical→logical rounding (e.g.
      // 900 * 1.25 scale = 1125 physical, ÷ 1.25 = exactly 900; but
      // 700 * 1.5 = 1050, ÷ 1.5 = 700 — clean. We use a tolerance because
      // some scales like 1.75 do round-trip with a 1px residual.
      (s) =>
          (s.bounds.size.width - 900).abs() <= 1 &&
          (s.bounds.size.height - 700).abs() <= 1,
    );
  });

  // The whole point of session 1's bounds vertical: enforce setMaxSize via
  // WM_GETMINMAXINFO's ptMaxSize so ShowWindow(SW_MAXIMIZE) doesn't
  // overshoot. Same class of bug as macOS contentMaxSize vs frame.
  testWidgets('setMaxSize is honored by maximize() in frame coords', (
    tester,
  ) async {
    await WindowManager.instance.setMaxSize(null);
    await WindowManager.instance.setMinSize(null);
    await WindowManager.instance.setMaxSize(const Size(1200, 900));
    await WindowManager.instance.maximize();
    await waitForSnapshot((s) => s.state == WindowState.maximized);
    final snap = WindowManager.instance.snapshot.value;
    expect(
      snap.bounds.size.width,
      lessThanOrEqualTo(1201),
      reason: 'maximize() must not exceed setMaxSize width '
          '(1px slop for DPI rounding)',
    );
    expect(
      snap.bounds.size.height,
      lessThanOrEqualTo(901),
      reason: 'maximize() must not exceed setMaxSize height',
    );
    await WindowManager.instance.unmaximize();
    await waitForSnapshot((s) => s.state == WindowState.normal);
    await WindowManager.instance.setMaxSize(null);
  });

  testWidgets('setMinSize clamps subsequent setSize in frame coords', (
    tester,
  ) async {
    await WindowManager.instance.setMinSize(const Size(800, 600));
    await WindowManager.instance.setSize(const Size(400, 300));
    // Snapshot.bounds.size (frame) must be at least minSize (also frame).
    await waitForSnapshot(
      (s) => s.bounds.size.width >= 800 - 1 && s.bounds.size.height >= 600 - 1,
    );
    await WindowManager.instance.setMinSize(null);
  });

  testWidgets('setTitle updates snapshot.title', (tester) async {
    await WindowManager.instance.setTitle('Integration Test');
    await waitForSnapshot((s) => s.title == 'Integration Test');
  });

  testWidgets('setAlwaysOnTop updates snapshot.alwaysOnTop', (tester) async {
    await WindowManager.instance.setAlwaysOnTop(true);
    await waitForSnapshot((s) => s.alwaysOnTop == true);
    await WindowManager.instance.setAlwaysOnTop(false);
    await waitForSnapshot((s) => s.alwaysOnTop == false);
  });

  testWidgets('minimize then restore round-trip', (tester) async {
    await WindowManager.instance.minimize();
    await waitForSnapshot((s) => s.state == WindowState.minimized);
    await WindowManager.instance.restore();
    await waitForSnapshot((s) => s.state == WindowState.normal);
  });

  // Windows-specific: confirm the Per-Monitor v2 DPI is reported in the
  // current display's scaleFactor. Hard to programmatically trigger
  // WM_DPICHANGED without moving the window across monitors, so we just
  // verify the read path returns a plausible value.
  testWidgets('current display scaleFactor matches Per-Monitor v2 DPI', (
    tester,
  ) async {
    final disp = await WindowManager.instance.displays.getCurrent();
    expect(disp.scaleFactor, greaterThan(0));
    // Reasonable bounds: 1.0 (96 DPI) to 4.0 (384 DPI / hi-DPI).
    expect(disp.scaleFactor, lessThanOrEqualTo(4.0));
  });

  // Windows-specific: setSkipTaskbar toggles WS_EX_TOOLWINDOW which also
  // hides the window from Alt+Tab (documented Win32 side effect). Verify
  // the snapshot reflects the flag round-trip.
  testWidgets('setSkipTaskbar round-trip via snapshot.skipTaskbar', (
    tester,
  ) async {
    await WindowManager.instance.setSkipTaskbar(true);
    await waitForSnapshot((s) => s.skipTaskbar == true);
    await WindowManager.instance.setSkipTaskbar(false);
    await waitForSnapshot((s) => s.skipTaskbar == false);
  });
}
