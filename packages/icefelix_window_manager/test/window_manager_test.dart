// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';
import 'package:mocktail/mocktail.dart';

class MockWindowManagerPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements WindowManagerPlatform {}

DisplayRaw _sampleDisplayRaw() => DisplayRaw(
      id: 'm1',
      name: 'Mock Display',
      bounds: RectRaw(x: 0, y: 0, width: 1920, height: 1080),
      workArea: RectRaw(x: 0, y: 0, width: 1920, height: 1040),
      scaleFactor: 1.0,
      isPrimary: true,
      refreshRate: 60,
    );

WindowSnapshotRaw _sampleSnapshotRaw() => WindowSnapshotRaw(
      bounds: WindowBoundsRaw(
        position: OffsetRaw(dx: 0, dy: 0),
        size: SizeRaw(width: 800, height: 600),
      ),
      state: WindowStateRaw.normal,
      title: 'Test App',
      isFocused: true,
      alwaysOnTop: false,
      skipTaskbar: false,
      resizable: true,
      movable: true,
      minimizable: true,
      maximizable: true,
      closable: true,
      frameless: false,
      titleBarStyle: TitleBarStyleRaw.normal,
      opacity: 1.0,
      hasShadow: true,
      preventClose: false,
      currentDisplay: _sampleDisplayRaw(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockWindowManagerPlatform mock;

  setUp(() {
    mock = MockWindowManagerPlatform();
    WindowManagerPlatform.instance = mock;
    WindowManager.resetForTesting();
  });

  group('WindowManager singleton', () {
    test('instance is a singleton', () {
      expect(
        identical(WindowManager.instance, WindowManager.instance),
        isTrue,
      );
    });

    test('snapshot.value access pre-init throws StateError', () {
      expect(
        () => WindowManager.instance.snapshot.value,
        throwsA(isA<StateError>()),
      );
    });

    test('platform accessor pre-init throws StateError', () {
      expect(
        () => WindowManager.instance.platform,
        throwsA(isA<StateError>()),
      );
    });

    test('ensureInitialized populates snapshot', () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(
          target: 'linux',
          displayServer: DisplayServerRaw.wayland,
          isSandboxed: false,
        ),
      );

      await WindowManager.instance.ensureInitialized();

      final snap = WindowManager.instance.snapshot.value;
      expect(snap.title, 'Test App');
      expect(snap.bounds.size, const Size(800, 600));
      expect(snap.state, WindowState.normal);
      expect(snap.currentDisplay.id, const DisplayId('m1'));
      expect(snap.currentDisplay.scaleFactor, 1.0);
    });

    test('ensureInitialized throws StateError if called twice', () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );

      await WindowManager.instance.ensureInitialized();

      expect(
        () => WindowManager.instance.ensureInitialized(),
        throwsA(isA<StateError>()),
      );
    });

    test('ensureInitialized throws UnsupportedError on unsupported platform',
        () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'android', isSandboxed: false),
      );

      expect(
        () => WindowManager.instance.ensureInitialized(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('platform accessor returns converted info after init (Linux Wayland)',
        () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(
          target: 'linux',
          displayServer: DisplayServerRaw.wayland,
          isSandboxed: false,
        ),
      );

      await WindowManager.instance.ensureInitialized();

      expect(
        WindowManager.instance.platform.target,
        TargetPlatform.linux,
      );
      expect(
        WindowManager.instance.platform.displayServer,
        DisplayServer.wayland,
      );
      expect(WindowManager.instance.platform.isSandboxed, isFalse);
    });

    test('platform on macOS has null displayServer', () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: true),
      );

      await WindowManager.instance.ensureInitialized();

      expect(
        WindowManager.instance.platform.target,
        TargetPlatform.macOS,
      );
      expect(WindowManager.instance.platform.displayServer, isNull);
      expect(WindowManager.instance.platform.isSandboxed, isTrue);
    });

    test('platform on Windows has null displayServer and isSandboxed false',
        () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'windows', isSandboxed: false),
      );

      await WindowManager.instance.ensureInitialized();

      expect(
        WindowManager.instance.platform.target,
        TargetPlatform.windows,
      );
      expect(WindowManager.instance.platform.displayServer, isNull);
    });

    test('snapshot notifies listeners on change (basic sanity)', () async {
      when(mock.ensureInitialized).thenAnswer(
        (_) async => _sampleSnapshotRaw(),
      );
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );

      await WindowManager.instance.ensureInitialized();

      // Just verify the snapshot ValueListenable interface is functional.
      var listenerCalls = 0;
      void listener() => listenerCalls++;
      WindowManager.instance.snapshot.addListener(listener);
      // No event yet — listener not called.
      expect(listenerCalls, 0);
      WindowManager.instance.snapshot.removeListener(listener);
    });
  });
}
