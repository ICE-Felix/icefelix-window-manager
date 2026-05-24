// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Integration tests for icefelix_window_manager — run against a real
// native window on macOS, Windows, or Linux. Drive with:
//
//     flutter test integration_test/ -d <macos|windows|linux>
//
// Linux note: `flutter test -d linux` uses a headless backend that does
// NOT create a real GtkWindow. Tests that depend on GTK window state
// (title, size, position, minimize) are auto-skipped in that mode.
// For full coverage, use `flutter run -d linux` on a real GNOME session.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool hasRealWindow;

  setUpAll(() async {
    await WindowManager.instance.ensureInitialized();
    runApp(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));

    // Detect headless Linux: flutter test -d linux doesn't create a real
    // GtkWindow, so GTK-dependent operations are no-ops. Probe by setting
    // the title and checking if it persists via refreshSnapshot.
    if (defaultTargetPlatform == TargetPlatform.linux) {
      await WindowManager.instance.setTitle('_probe_');
      await WindowManager.instance.refreshSnapshot();
      hasRealWindow =
          WindowManager.instance.snapshot.value.title == '_probe_';
      if (!hasRealWindow) {
        debugPrint('No real GtkWindow detected (flutter test headless). '
            'GTK-dependent tests will be skipped.');
      }
      await WindowManager.instance.setTitle('');
    } else {
      hasRealWindow = true;
    }
  });

  /// Polls until [predicate] returns true on the current snapshot, or fails
  /// after [timeout]. Uses refreshSnapshot() to pull fresh state from native
  /// on each tick (works around flutter_linux's headless test binding not
  /// delivering FlutterApi push events during testWidgets).
  Future<void> waitForSnapshot(
    bool Function(WindowSnapshot) predicate, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await WindowManager.instance.refreshSnapshot();
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
    if (!hasRealWindow) return;
    await WindowManager.instance.setSize(const Size(900, 700));
    await waitForSnapshot(
      (s) => s.bounds.size.width == 900 && s.bounds.size.height == 700,
    );
  });

  testWidgets('setTitle updates snapshot.title', (tester) async {
    if (!hasRealWindow) return;
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
    if (!hasRealWindow) return;
    await WindowManager.instance.minimize();
    await waitForSnapshot((s) => s.state == WindowState.minimized);
    await WindowManager.instance.restore();
    await waitForSnapshot((s) => s.state == WindowState.normal);
  });

  testWidgets('setMaxSize is honored by maximize() in frame coords', (
    tester,
  ) async {
    if (!hasRealWindow) return;
    await WindowManager.instance.setMaxSize(null);
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
    if (!hasRealWindow) return;
    await WindowManager.instance.setMinSize(const Size(800, 600));
    await WindowManager.instance.setSize(const Size(400, 300));
    await waitForSnapshot(
      (s) => s.bounds.size.width >= 800 && s.bounds.size.height >= 600,
    );
    await WindowManager.instance.setMinSize(null);
  });

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
    if (!hasRealWindow) return;
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
    if (!hasRealWindow) return;
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
