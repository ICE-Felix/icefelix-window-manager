// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Integration tests for icefelix_window_manager — run against a real
// native window on macOS, Windows, or Linux. Drive with:
//
//     flutter test integration_test/ -d <macos|windows|linux>
//
// Linux note: requires a running window manager. Under headless CI use
// scripts/xvfb-with-wm.sh (Xvfb + openbox). Without a WM, GTK resize
// requests are silent no-ops and most tests time out at 2s.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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

  testWidgets('platform.target matches host', (tester) async {
    final target = WindowManager.instance.platform.target;
    expect(
      target,
      isIn(
          [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]),
      reason: 'plugin only supports desktop targets',
    );
    final displayServer = WindowManager.instance.platform.displayServer;
    if (target == TargetPlatform.linux) {
      expect(displayServer, isNotNull);
      expect(displayServer, isIn([DisplayServer.x11, DisplayServer.wayland]));
    } else {
      expect(displayServer, isNull);
    }
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

  // Contract: setSize, setMinSize, setMaxSize, and snapshot.bounds.size all
  // operate on the same coordinate space (frame, including titlebar). Before
  // the alignment fix, setMin/MaxSize used contentMin/MaxSize while setSize
  // and snapshot used frame — causing maximize() to overshoot by ~28px.
  testWidgets('setMaxSize is honored by maximize() in frame coords', (
    tester,
  ) async {
    await WindowManager.instance.setMaxSize(null); // clear residual constraint
    await WindowManager.instance.setMinSize(null);
    await WindowManager.instance.setMaxSize(const Size(1200, 900));
    await WindowManager.instance.maximize();
    await waitForSnapshot((s) => s.state == WindowState.maximized);
    final snap = WindowManager.instance.snapshot.value;
    expect(
      snap.bounds.size.width,
      lessThanOrEqualTo(1200),
      reason: 'maximize() must not exceed setMaxSize width',
    );
    expect(
      snap.bounds.size.height,
      lessThanOrEqualTo(900),
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
      (s) => s.bounds.size.width >= 800 && s.bounds.size.height >= 600,
    );
    await WindowManager.instance.setMinSize(null);
  });

  // Regression: preventClose=true + a listener calling event.preventDefault()
  // must block the close. The bug existed silently on macOS too: the
  // WindowManager._events stream was async-broadcast, so the Pigeon-generated
  // synchronous onCloseRequest read _closeRequestBlocked before any queued
  // listener microtask could vote — preventDefault() was a no-op end-to-end.
  // Surfaced first on Windows (integration test added there); backported here
  // so the macOS side can't silently regress if the fix ever gets reverted.
  // The fix lives in the shared app-facing package: _events is now sync:true.
  // Uses the public debugSimulateCloseRequest hook to drive the close path
  // without actually closing the test runner window.
  testWidgets('preventClose: synchronous preventDefault blocks close', (
    tester,
  ) async {
    await WindowManager.instance.setPreventClose(true);
    final sub = WindowManager.instance.events.listen((event) {
      if (event is WindowCloseRequestEvent) {
        event.preventDefault();
      }
    });
    final allowed = await WindowManager.instance.debugSimulateCloseRequest();
    await sub.cancel();
    await WindowManager.instance.setPreventClose(false);
    expect(
      allowed,
      isFalse,
      reason: 'preventDefault() in a listener should set the verdict to deny, '
          'even though listeners are async-scheduled in some Dart stream '
          'configurations. Fix: WindowManager._events is sync:true.',
    );
  });

  // ─── Linux-specific tests ───────────────────────────────────────────────

  testWidgets('linux x11: snapshot.bounds.position is non-null',
      (tester) async {
    if (WindowManager.instance.platform.target != TargetPlatform.linux) return;
    if (WindowManager.instance.platform.displayServer != DisplayServer.x11) {
      return;
    }
    final snap = WindowManager.instance.snapshot.value;
    expect(snap.bounds.position, isNotNull,
        reason: 'X11 exposes window position; position must be non-null');
  });

  testWidgets('linux wayland: snapshot.bounds.position is null',
      (tester) async {
    if (WindowManager.instance.platform.target != TargetPlatform.linux) return;
    if (WindowManager.instance.platform.displayServer != DisplayServer.wayland) {
      return;
    }
    final snap = WindowManager.instance.snapshot.value;
    expect(snap.bounds.position, isNull,
        reason: 'Wayland does not expose window position; must be null');
  });

  testWidgets('linux x11: setPosition then snapshot reflects it',
      (tester) async {
    if (WindowManager.instance.platform.target != TargetPlatform.linux) return;
    if (WindowManager.instance.platform.displayServer != DisplayServer.x11) {
      return;
    }
    await WindowManager.instance.setPosition(const Offset(120, 80));
    await waitForSnapshot((s) =>
        s.bounds.position != null &&
        s.bounds.position!.dx == 120 &&
        s.bounds.position!.dy == 80);
  });

  testWidgets('linux wayland: setPosition is silently no-op', (tester) async {
    if (WindowManager.instance.platform.target != TargetPlatform.linux) return;
    if (WindowManager.instance.platform.displayServer != DisplayServer.wayland) {
      return;
    }
    await WindowManager.instance.setPosition(const Offset(100, 100));
    final snap = WindowManager.instance.snapshot.value;
    expect(snap.bounds.position, isNull);
  });
}
