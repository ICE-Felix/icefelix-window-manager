// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

void main() {
  group('WindowBounds', () {
    test('position can be null (Wayland case)', () {
      const bounds = WindowBounds(size: Size(800, 600));
      expect(bounds.position, isNull);
      expect(bounds.size, const Size(800, 600));
    });

    test('position can be set explicitly', () {
      const bounds =
          WindowBounds(position: Offset(10, 20), size: Size(800, 600));
      expect(bounds.position, const Offset(10, 20));
    });

    test('equality based on position + size', () {
      const a = WindowBounds(position: Offset(0, 0), size: Size(100, 100));
      const b = WindowBounds(position: Offset(0, 0), size: Size(100, 100));
      const c = WindowBounds(position: Offset(1, 0), size: Size(100, 100));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Display', () {
    test('physicalSize and dpi nullable for unknown monitors', () {
      const display = Display(
        id: DisplayId('m1'),
        name: 'Test Display',
        bounds: Rect.fromLTWH(0, 0, 1920, 1080),
        workArea: Rect.fromLTWH(0, 0, 1920, 1040),
        physicalSize: null,
        dpi: null,
        scaleFactor: 1.0,
        isPrimary: true,
        refreshRate: 60,
      );
      expect(display.physicalSize, isNull);
      expect(display.dpi, isNull);
    });

    test('DisplayId equality via extension type wrap', () {
      const a = DisplayId('m1');
      const b = DisplayId('m1');
      const c = DisplayId('m2');
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  group('WindowSnapshot', () {
    Display sampleDisplay() => const Display(
          id: DisplayId('m1'),
          bounds: Rect.fromLTWH(0, 0, 1920, 1080),
          workArea: Rect.fromLTWH(0, 0, 1920, 1040),
          scaleFactor: 1.0,
          isPrimary: true,
        );

    WindowSnapshot baseSnapshot() => WindowSnapshot(
          bounds: const WindowBounds(size: Size(800, 600)),
          state: WindowState.normal,
          title: '',
          isFocused: true,
          alwaysOnTop: false,
          skipTaskbar: false,
          resizable: true,
          movable: true,
          minimizable: true,
          maximizable: true,
          closable: true,
          frameless: false,
          titleBarStyle: TitleBarStyle.normal,
          opacity: 1.0,
          hasShadow: true,
          preventClose: false,
          currentDisplay: sampleDisplay(),
        );

    test('isVisible computed from state', () {
      final snap = baseSnapshot();
      expect(snap.isVisible, isTrue);

      final snapMinimized = snap.copyWith(state: WindowState.minimized);
      expect(snapMinimized.isVisible, isFalse);

      final snapHidden = snap.copyWith(state: WindowState.hidden);
      expect(snapHidden.isVisible, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      final original = baseSnapshot();
      final updated = original.copyWith(title: 'Bar');
      expect(updated.title, 'Bar');
      expect(updated.state, WindowState.normal);
      expect(updated.isFocused, isTrue);
      expect(updated.currentDisplay, original.currentDisplay);
    });

    test('equality and hashCode based on all fields', () {
      final a = baseSnapshot();
      final b = baseSnapshot();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(title: 'Different');
      expect(a, isNot(equals(c)));
    });
  });

  group('Enums sanity', () {
    test('WindowState has 5 values', () {
      expect(WindowState.values.length, 5);
    });

    test('TitleBarStyle has 3 values', () {
      expect(TitleBarStyle.values.length, 3);
    });

    test('ResizeDirection has 8 values', () {
      expect(ResizeDirection.values.length, 8);
    });
  });
}
