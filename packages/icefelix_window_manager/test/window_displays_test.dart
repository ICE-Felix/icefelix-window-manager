// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';
import 'package:mocktail/mocktail.dart';

class MockWindowManagerPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements WindowManagerPlatform {}

DisplayRaw _displayA() => DisplayRaw(
      id: 'm1',
      name: 'A',
      bounds: RectRaw(x: 0, y: 0, width: 1920, height: 1080),
      workArea: RectRaw(x: 0, y: 0, width: 1920, height: 1040),
      scaleFactor: 1.0,
      isPrimary: true,
      refreshRate: 60,
    );

DisplayRaw _displayB() => DisplayRaw(
      id: 'm2',
      name: 'B',
      bounds: RectRaw(x: 1920, y: 0, width: 2560, height: 1440),
      workArea: RectRaw(x: 1920, y: 0, width: 2560, height: 1400),
      scaleFactor: 1.5,
      isPrimary: false,
      refreshRate: 120,
    );

WindowSnapshotRaw _snapshotRaw({
  double width = 800,
  double height = 600,
  String title = 'Test',
  bool preventClose = false,
  WindowStateRaw state = WindowStateRaw.normal,
  bool isFocused = true,
  DisplayRaw? display,
}) =>
    WindowSnapshotRaw(
      bounds: WindowBoundsRaw(
        position: OffsetRaw(dx: 0, dy: 0),
        size: SizeRaw(width: width, height: height),
      ),
      state: state,
      title: title,
      isFocused: isFocused,
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
      preventClose: preventClose,
      currentDisplay: display ?? _displayA(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockWindowManagerPlatform mock;

  setUpAll(() {
    registerFallbackValue(SizeRaw(width: 0, height: 0));
    registerFallbackValue(OffsetRaw(dx: 0, dy: 0));
  });

  setUp(() async {
    mock = MockWindowManagerPlatform();
    WindowManagerPlatform.instance = mock;
    WindowManager.resetForTesting();
    when(mock.ensureInitialized).thenAnswer((_) async => _snapshotRaw());
    when(mock.getPlatformInfo).thenAnswer(
      (_) async => PlatformInfoRaw(target: 'macos', isSandboxed: false),
    );
    await WindowManager.instance.ensureInitialized();
  });

  group('WindowDisplays', () {
    test('list returns converted displays', () async {
      when(mock.listDisplays)
          .thenAnswer((_) async => [_displayA(), _displayB()]);
      final displays = await WindowManager.instance.displays.list();
      expect(displays.length, 2);
      expect(displays[0].id, const DisplayId('m1'));
      expect(displays[0].isPrimary, isTrue);
      expect(displays[1].id, const DisplayId('m2'));
      expect(displays[1].scaleFactor, 1.5);
    });

    test('getCurrent returns converted display', () async {
      when(mock.getCurrentDisplay).thenAnswer((_) async => _displayA());
      final current = await WindowManager.instance.displays.getCurrent();
      expect(current.id, const DisplayId('m1'));
    });

    test('getPrimary returns converted display', () async {
      when(mock.getPrimaryDisplay).thenAnswer((_) async => _displayA());
      final primary = await WindowManager.instance.displays.getPrimary();
      expect(primary.isPrimary, isTrue);
    });

    test('events stream is broadcast (multi-listener)', () {
      final stream = WindowManager.instance.displays.events;
      final sub1 = stream.listen((_) {});
      final sub2 = stream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('handleDisplaysChanged emits Added when new display appears',
        () async {
      final events = <DisplayEvent>[];
      final sub = WindowManager.instance.displays.events.listen(events.add);

      // Initial: only displayA known (set during ensureInitialized via snapshot.currentDisplay).
      // Actually, WindowDisplays starts empty until first onDisplaysChanged.
      WindowManager.instance.debugSimulateDisplaysChanged([_displayA()]);
      await Future<void>.delayed(Duration.zero);

      // First call: all are "added" since lastKnown was empty.
      expect(events.whereType<DisplayAddedEvent>().length, 1);

      events.clear();
      WindowManager.instance
          .debugSimulateDisplaysChanged([_displayA(), _displayB()]);
      await Future<void>.delayed(Duration.zero);

      // Second call: m2 is new.
      expect(events.length, 1);
      expect(events.first, isA<DisplayAddedEvent>());
      expect(
        (events.first as DisplayAddedEvent).display.id,
        const DisplayId('m2'),
      );

      await sub.cancel();
    });

    test('handleDisplaysChanged emits Removed when display disappears',
        () async {
      WindowManager.instance
          .debugSimulateDisplaysChanged([_displayA(), _displayB()]);

      final events = <DisplayEvent>[];
      final sub = WindowManager.instance.displays.events.listen(events.add);

      WindowManager.instance.debugSimulateDisplaysChanged([_displayA()]);
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 1);
      expect(events.first, isA<DisplayRemovedEvent>());
      expect((events.first as DisplayRemovedEvent).id, const DisplayId('m2'));

      await sub.cancel();
    });

    test('handleDisplaysChanged emits Changed when display config changes',
        () async {
      WindowManager.instance.debugSimulateDisplaysChanged([_displayA()]);

      final events = <DisplayEvent>[];
      final sub = WindowManager.instance.displays.events.listen(events.add);

      // Change scaleFactor on m1.
      final modified = DisplayRaw(
        id: 'm1',
        name: 'A',
        bounds: RectRaw(x: 0, y: 0, width: 1920, height: 1080),
        workArea: RectRaw(x: 0, y: 0, width: 1920, height: 1040),
        scaleFactor: 2.0,
        isPrimary: true,
        refreshRate: 60,
      );
      WindowManager.instance.debugSimulateDisplaysChanged([modified]);
      await Future<void>.delayed(Duration.zero);

      expect(events.length, 1);
      expect(events.first, isA<DisplayChangedEvent>());
      final changed = events.first as DisplayChangedEvent;
      expect(changed.oldConfig.scaleFactor, 1.0);
      expect(changed.newConfig.scaleFactor, 2.0);

      await sub.cancel();
    });
  });

  group('WindowManager events stream', () {
    test('events stream is broadcast', () {
      final stream = WindowManager.instance.events;
      final sub1 = stream.listen((_) {});
      final sub2 = stream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('onSnapshotChanged emits WindowResizeEvent on size change', () async {
      final events = <WindowEvent>[];
      final sub = WindowManager.instance.events.listen(events.add);

      WindowManager.instance
          .debugSimulateSnapshotChange(_snapshotRaw(width: 1000, height: 700));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<WindowResizeEvent>().length, 1);
      final resize = events.whereType<WindowResizeEvent>().first;
      expect(resize.oldSize, const Size(800, 600));
      expect(resize.newSize, const Size(1000, 700));

      await sub.cancel();
    });

    test('onSnapshotChanged emits WindowFocusEvent on focus change', () async {
      final events = <WindowEvent>[];
      final sub = WindowManager.instance.events.listen(events.add);

      WindowManager.instance
          .debugSimulateSnapshotChange(_snapshotRaw(isFocused: false));
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<WindowFocusEvent>().length, 1);
      expect(events.whereType<WindowFocusEvent>().first.focused, isFalse);

      await sub.cancel();
    });

    test('onSnapshotChanged emits WindowStateChangeEvent on state change',
        () async {
      final events = <WindowEvent>[];
      final sub = WindowManager.instance.events.listen(events.add);

      WindowManager.instance.debugSimulateSnapshotChange(
        _snapshotRaw(state: WindowStateRaw.maximized),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<WindowStateChangeEvent>().length, 1);
      final stateChange = events.whereType<WindowStateChangeEvent>().first;
      expect(stateChange.oldState, WindowState.normal);
      expect(stateChange.newState, WindowState.maximized);

      await sub.cancel();
    });

    test('onSnapshotChanged updates snapshot value', () async {
      WindowManager.instance
          .debugSimulateSnapshotChange(_snapshotRaw(title: 'Updated'));
      await Future<void>.delayed(Duration.zero);

      expect(WindowManager.instance.snapshot.value.title, 'Updated');
    });

    test('onCloseRequest fires WindowCloseRequestEvent; preventDefault blocks',
        () async {
      // Set preventClose state via snapshot update.
      WindowManager.instance
          .debugSimulateSnapshotChange(_snapshotRaw(preventClose: true));

      var blocked = false;
      final sub = WindowManager.instance.events.listen((e) {
        if (e is WindowCloseRequestEvent) {
          e.preventDefault();
          blocked = true;
        }
      });

      final shouldClose =
          await WindowManager.instance.debugSimulateCloseRequest();

      expect(blocked, isTrue);
      expect(shouldClose, isFalse); // preventDefault → block

      await sub.cancel();
    });

    test('onCloseRequest without preventDefault returns true (allow close)',
        () async {
      WindowManager.instance
          .debugSimulateSnapshotChange(_snapshotRaw(preventClose: true));

      final sub = WindowManager.instance.events.listen((_) {
        // Don't call preventDefault.
      });

      final shouldClose =
          await WindowManager.instance.debugSimulateCloseRequest();

      expect(shouldClose, isTrue); // no preventDefault → allow

      await sub.cancel();
    });
  });
}
