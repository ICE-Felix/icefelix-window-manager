// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager/src/messages.g.dart';
import 'package:icefelix_window_manager/src/window_manager_platform.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockWindowManagerPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements WindowManagerPlatform {}

class _FakeWindowFlutterApi implements WindowFlutterApi {
  @override
  void onSnapshotChanged(WindowSnapshotRaw snapshot) {}
  @override
  void onDisplaysChanged(List<DisplayRaw> displays) {}
  @override
  bool onCloseRequest() => true;
}

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

  setUpAll(() {
    registerFallbackValue(SizeRaw(width: 0, height: 0));
    registerFallbackValue(OffsetRaw(dx: 0, dy: 0));
    registerFallbackValue(
      WindowBoundsRaw(
        position: null,
        size: SizeRaw(width: 0, height: 0),
      ),
    );
    registerFallbackValue(ResizeDirectionRaw.top);
    registerFallbackValue(TitleBarStyleRaw.normal);
    registerFallbackValue(_FakeWindowFlutterApi());
  });

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

  group('WindowManager bounds setters', () {
    setUp(() async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      await WindowManager.instance.ensureInitialized();
    });

    test('setSize delegates to platform', () async {
      when(() => mock.setSize(any())).thenAnswer((_) async {});
      await WindowManager.instance.setSize(const Size(1024, 768));
      final sizeMatcher = predicate<SizeRaw>(
        (s) => s.width == 1024 && s.height == 768,
      );
      verify(() => mock.setSize(any(that: sizeMatcher))).called(1);
    });

    test('setMinSize with null clears constraint', () async {
      when(() => mock.setMinSize(null)).thenAnswer((_) async {});
      await WindowManager.instance.setMinSize(null);
      verify(() => mock.setMinSize(null)).called(1);
    });

    test('setMaxSize with non-null delegates', () async {
      when(() => mock.setMaxSize(any())).thenAnswer((_) async {});
      await WindowManager.instance.setMaxSize(const Size(2000, 1500));
      final sizeMatcher = predicate<SizeRaw?>(
        (s) => s != null && s.width == 2000 && s.height == 1500,
      );
      verify(() => mock.setMaxSize(any(that: sizeMatcher))).called(1);
    });

    test('setPosition delegates with correct offset', () async {
      when(() => mock.setPosition(any())).thenAnswer((_) async {});
      await WindowManager.instance.setPosition(const Offset(100, 200));
      final offsetMatcher = predicate<OffsetRaw>(
        (o) => o.dx == 100 && o.dy == 200,
      );
      verify(() => mock.setPosition(any(that: offsetMatcher))).called(1);
    });

    test('setBounds without display passes null displayId', () async {
      when(() => mock.setBounds(any(), any())).thenAnswer((_) async {});
      await WindowManager.instance.setBounds(
        const WindowBounds(position: Offset(10, 20), size: Size(800, 600)),
      );
      verify(() => mock.setBounds(any(), null)).called(1);
    });

    test('setBounds with display passes display.value', () async {
      when(() => mock.setBounds(any(), any())).thenAnswer((_) async {});
      await WindowManager.instance.setBounds(
        const WindowBounds(size: Size(800, 600)),
        display: const DisplayId('m2'),
      );
      verify(() => mock.setBounds(any(), 'm2')).called(1);
    });

    test('setBounds with null position passes null in WindowBoundsRaw',
        () async {
      when(() => mock.setBounds(any(), any())).thenAnswer((_) async {});
      await WindowManager.instance.setBounds(
        const WindowBounds(size: Size(800, 600)),
      );
      final boundsMatcher = predicate<WindowBoundsRaw>(
        (b) => b.position == null,
      );
      verify(
        () => mock.setBounds(any(that: boundsMatcher), null),
      ).called(1);
    });

    test('center delegates to platform', () async {
      when(mock.center).thenAnswer((_) async {});
      await WindowManager.instance.center();
      verify(mock.center).called(1);
    });

    test('moveToDisplay passes display.value', () async {
      when(() => mock.moveToDisplay(any())).thenAnswer((_) async {});
      await WindowManager.instance.moveToDisplay(const DisplayId('m2'));
      verify(() => mock.moveToDisplay('m2')).called(1);
    });
  });

  group('WindowManager state setters', () {
    setUp(() async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      await WindowManager.instance.ensureInitialized();
    });

    test('all state methods delegate', () async {
      when(mock.minimize).thenAnswer((_) async {});
      when(mock.maximize).thenAnswer((_) async {});
      when(mock.unmaximize).thenAnswer((_) async {});
      when(mock.restore).thenAnswer((_) async {});
      when(mock.hide).thenAnswer((_) async {});
      when(mock.show).thenAnswer((_) async {});
      when(mock.fullscreen).thenAnswer((_) async {});
      when(mock.exitFullscreen).thenAnswer((_) async {});

      await WindowManager.instance.minimize();
      await WindowManager.instance.maximize();
      await WindowManager.instance.unmaximize();
      await WindowManager.instance.restore();
      await WindowManager.instance.hide();
      await WindowManager.instance.show();
      await WindowManager.instance.fullscreen();
      await WindowManager.instance.exitFullscreen();

      verify(mock.minimize).called(1);
      verify(mock.maximize).called(1);
      verify(mock.unmaximize).called(1);
      verify(mock.restore).called(1);
      verify(mock.hide).called(1);
      verify(mock.show).called(1);
      verify(mock.fullscreen).called(1);
      verify(mock.exitFullscreen).called(1);
    });

    test('focus + blur delegate', () async {
      when(mock.focus).thenAnswer((_) async {});
      when(mock.blur).thenAnswer((_) async {});
      await WindowManager.instance.focus();
      await WindowManager.instance.blur();
      verify(mock.focus).called(1);
      verify(mock.blur).called(1);
    });
  });

  group('WindowManager lifecycle + drag/resize', () {
    setUp(() async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      await WindowManager.instance.ensureInitialized();
    });

    test('close + destroy delegate', () async {
      when(mock.close).thenAnswer((_) async {});
      when(mock.destroy).thenAnswer((_) async {});
      await WindowManager.instance.close();
      await WindowManager.instance.destroy();
      verify(mock.close).called(1);
      verify(mock.destroy).called(1);
    });

    test('startDrag delegates', () async {
      when(mock.startDrag).thenAnswer((_) async {});
      await WindowManager.instance.startDrag();
      verify(mock.startDrag).called(1);
    });

    test('startResize maps ResizeDirection correctly for all 8 values',
        () async {
      when(() => mock.startResize(any())).thenAnswer((_) async {});

      final expectations = {
        ResizeDirection.top: ResizeDirectionRaw.top,
        ResizeDirection.bottom: ResizeDirectionRaw.bottom,
        ResizeDirection.left: ResizeDirectionRaw.left,
        ResizeDirection.right: ResizeDirectionRaw.right,
        ResizeDirection.topLeft: ResizeDirectionRaw.topLeft,
        ResizeDirection.topRight: ResizeDirectionRaw.topRight,
        ResizeDirection.bottomLeft: ResizeDirectionRaw.bottomLeft,
        ResizeDirection.bottomRight: ResizeDirectionRaw.bottomRight,
      };

      for (final entry in expectations.entries) {
        await WindowManager.instance.startResize(entry.key);
      }

      for (final raw in expectations.values) {
        verify(() => mock.startResize(raw)).called(1);
      }
    });
  });

  group('WindowManager title + props + visual', () {
    setUp(() async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      await WindowManager.instance.ensureInitialized();
    });

    test('setTitle delegates', () async {
      when(() => mock.setTitle(any())).thenAnswer((_) async {});
      await WindowManager.instance.setTitle('Hello');
      verify(() => mock.setTitle('Hello')).called(1);
    });

    test('boolean property setters delegate', () async {
      when(() => mock.setAlwaysOnTop(any())).thenAnswer((_) async {});
      when(() => mock.setSkipTaskbar(any())).thenAnswer((_) async {});
      when(() => mock.setResizable(any())).thenAnswer((_) async {});
      when(() => mock.setMovable(any())).thenAnswer((_) async {});
      when(() => mock.setMinimizable(any())).thenAnswer((_) async {});
      when(() => mock.setMaximizable(any())).thenAnswer((_) async {});
      when(() => mock.setClosable(any())).thenAnswer((_) async {});
      when(() => mock.setFrameless(any())).thenAnswer((_) async {});
      when(() => mock.setHasShadow(any())).thenAnswer((_) async {});
      when(() => mock.setPreventClose(any())).thenAnswer((_) async {});

      await WindowManager.instance.setAlwaysOnTop(true);
      await WindowManager.instance.setSkipTaskbar(false);
      await WindowManager.instance.setResizable(true);
      await WindowManager.instance.setMovable(true);
      await WindowManager.instance.setMinimizable(true);
      await WindowManager.instance.setMaximizable(false);
      await WindowManager.instance.setClosable(true);
      await WindowManager.instance.setFrameless(true);
      await WindowManager.instance.setHasShadow(false);
      await WindowManager.instance.setPreventClose(true);

      verify(() => mock.setAlwaysOnTop(true)).called(1);
      verify(() => mock.setSkipTaskbar(false)).called(1);
      verify(() => mock.setResizable(true)).called(1);
      verify(() => mock.setMovable(true)).called(1);
      verify(() => mock.setMinimizable(true)).called(1);
      verify(() => mock.setMaximizable(false)).called(1);
      verify(() => mock.setClosable(true)).called(1);
      verify(() => mock.setFrameless(true)).called(1);
      verify(() => mock.setHasShadow(false)).called(1);
      verify(() => mock.setPreventClose(true)).called(1);
    });

    test('setOpacity delegates', () async {
      when(() => mock.setOpacity(any())).thenAnswer((_) async {});
      await WindowManager.instance.setOpacity(0.5);
      verify(() => mock.setOpacity(0.5)).called(1);
    });

    test('setBackgroundColor converts Color to ARGB int', () async {
      when(() => mock.setBackgroundColor(any())).thenAnswer((_) async {});
      await WindowManager.instance.setBackgroundColor(const Color(0xFF112233));
      verify(() => mock.setBackgroundColor(0xFF112233)).called(1);
    });

    test('setIcon delegates path', () async {
      when(() => mock.setIcon(any())).thenAnswer((_) async {});
      await WindowManager.instance.setIcon('/path/to/icon.png');
      verify(() => mock.setIcon('/path/to/icon.png')).called(1);
    });

    test('setTitleBarStyle maps all 3 enum values', () async {
      when(() => mock.setTitleBarStyle(any())).thenAnswer((_) async {});

      await WindowManager.instance.setTitleBarStyle(TitleBarStyle.normal);
      await WindowManager.instance.setTitleBarStyle(TitleBarStyle.hidden);
      await WindowManager.instance.setTitleBarStyle(TitleBarStyle.hiddenInset);

      verify(() => mock.setTitleBarStyle(TitleBarStyleRaw.normal)).called(1);
      verify(() => mock.setTitleBarStyle(TitleBarStyleRaw.hidden)).called(1);
      verify(() => mock.setTitleBarStyle(TitleBarStyleRaw.hiddenInset))
          .called(1);
    });
  });

  group('WindowManager FlutterApi wiring (W1.1 patch C1)', () {
    test('ensureInitialized calls registerFlutterApi with adapter', () async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      when(() => mock.registerFlutterApi(any())).thenReturn(null);

      await WindowManager.instance.ensureInitialized();

      verify(() => mock.registerFlutterApi(any(that: isA<WindowFlutterApi>())))
          .called(1);
    });

    test('adapter forwards onSnapshotChanged to WindowManager', () async {
      when(mock.ensureInitialized)
          .thenAnswer((_) async => _sampleSnapshotRaw());
      when(mock.getPlatformInfo).thenAnswer(
        (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
      );
      WindowFlutterApi? capturedAdapter;
      when(() => mock.registerFlutterApi(any())).thenAnswer((invocation) {
        capturedAdapter = invocation.positionalArguments[0] as WindowFlutterApi;
      });

      await WindowManager.instance.ensureInitialized();
      expect(capturedAdapter, isNotNull);

      // Adapter should forward to WindowManager.onSnapshotChanged.
      final newSnap = _sampleSnapshotRaw();
      newSnap.title = 'Updated by adapter';
      capturedAdapter!.onSnapshotChanged(newSnap);
      expect(WindowManager.instance.snapshot.value.title, 'Updated by adapter');
    });
  });
}
