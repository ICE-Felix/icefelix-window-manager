// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

void main() {
  Display sampleDisplay() => const Display(
        id: DisplayId('m1'),
        bounds: Rect.fromLTWH(0, 0, 1920, 1080),
        workArea: Rect.fromLTWH(0, 0, 1920, 1040),
        scaleFactor: 1.0,
        isPrimary: true,
      );

  group('WindowEvent — pattern matching', () {
    test('WindowResizeEvent holds old + new size', () {
      const event = WindowResizeEvent(
        oldSize: Size(800, 600),
        newSize: Size(1000, 700),
      );
      // Exhaustive — sealed match guarantees the WindowResizeEvent branch.
      switch (event) {
        case WindowResizeEvent(:final oldSize, :final newSize):
          expect(oldSize, const Size(800, 600));
          expect(newSize, const Size(1000, 700));
      }
    });

    test('WindowMoveEvent positions nullable for Wayland', () {
      const event = WindowMoveEvent();
      expect(event.oldPosition, isNull);
      expect(event.newPosition, isNull);
    });

    test('WindowMoveEvent with non-null positions', () {
      const event = WindowMoveEvent(
        oldPosition: Offset(10, 20),
        newPosition: Offset(30, 40),
      );
      expect(event.oldPosition, const Offset(10, 20));
      expect(event.newPosition, const Offset(30, 40));
    });

    test('WindowFocusEvent holds focused bool', () {
      const e1 = WindowFocusEvent(focused: true);
      const e2 = WindowFocusEvent(focused: false);
      expect(e1.focused, isTrue);
      expect(e2.focused, isFalse);
    });

    test('WindowStateChangeEvent holds old + new state', () {
      const event = WindowStateChangeEvent(
        oldState: WindowState.normal,
        newState: WindowState.maximized,
      );
      expect(event.oldState, WindowState.normal);
      expect(event.newState, WindowState.maximized);
    });

    test('WindowDisplayChangeEvent holds old + new display', () {
      final old = sampleDisplay();
      const next = Display(
        id: DisplayId('m2'),
        bounds: Rect.fromLTWH(0, 0, 2560, 1440),
        workArea: Rect.fromLTWH(0, 0, 2560, 1400),
        scaleFactor: 1.5,
        isPrimary: false,
      );
      final event = WindowDisplayChangeEvent(oldDisplay: old, newDisplay: next);
      expect(event.oldDisplay, old);
      expect(event.newDisplay, next);
    });

    test('WindowCloseRequestEvent preventDefault triggers callback', () {
      var blocked = false;
      final event = WindowCloseRequestEvent(
        onPreventDefault: () => blocked = true,
      );
      event.preventDefault();
      expect(blocked, isTrue);
    });

    test('WindowCloseRequestEvent preventDefault is idempotent', () {
      var callCount = 0;
      final event = WindowCloseRequestEvent(
        onPreventDefault: () => callCount++,
      );
      event.preventDefault();
      event.preventDefault();
      event.preventDefault();
      // Idempotent: only first call has effect.
      expect(callCount, 1);
    });

    test('WindowCloseRequestEvent wasPreventDefaultCalled tracks state', () {
      final event = WindowCloseRequestEvent(onPreventDefault: () {});
      expect(event.wasPreventDefaultCalled, isFalse);
      event.preventDefault();
      expect(event.wasPreventDefaultCalled, isTrue);
    });

    test('exhaustive switch covers all variants', () {
      WindowEvent makeEvent(int variant) {
        switch (variant) {
          case 0:
            return const WindowResizeEvent(
              oldSize: Size(0, 0),
              newSize: Size(1, 1),
            );
          case 1:
            return const WindowMoveEvent();
          case 2:
            return const WindowFocusEvent(focused: true);
          case 3:
            return const WindowStateChangeEvent(
              oldState: WindowState.normal,
              newState: WindowState.maximized,
            );
          case 4:
            return WindowDisplayChangeEvent(
              oldDisplay: sampleDisplay(),
              newDisplay: sampleDisplay(),
            );
          case 5:
            return WindowCloseRequestEvent(onPreventDefault: () {});
          default:
            throw StateError('bad variant');
        }
      }

      // Exhaustive pattern match — compiler enforces all cases listed.
      String describe(WindowEvent e) {
        return switch (e) {
          WindowResizeEvent() => 'resize',
          WindowMoveEvent() => 'move',
          WindowFocusEvent() => 'focus',
          WindowStateChangeEvent() => 'state',
          WindowDisplayChangeEvent() => 'display',
          WindowCloseRequestEvent() => 'close',
        };
      }

      expect(describe(makeEvent(0)), 'resize');
      expect(describe(makeEvent(1)), 'move');
      expect(describe(makeEvent(2)), 'focus');
      expect(describe(makeEvent(3)), 'state');
      expect(describe(makeEvent(4)), 'display');
      expect(describe(makeEvent(5)), 'close');
    });
  });

  group('DisplayEvent — pattern matching', () {
    test('DisplayAddedEvent holds display', () {
      final event = DisplayAddedEvent(display: sampleDisplay());
      expect(event.display.id, const DisplayId('m1'));
    });

    test('DisplayRemovedEvent holds id only', () {
      const event = DisplayRemovedEvent(id: DisplayId('m1'));
      expect(event.id, const DisplayId('m1'));
    });

    test('DisplayChangedEvent holds old + new', () {
      final old = sampleDisplay();
      const next = Display(
        id: DisplayId('m1'),
        bounds: Rect.fromLTWH(0, 0, 2560, 1440),
        workArea: Rect.fromLTWH(0, 0, 2560, 1400),
        scaleFactor: 1.5,
        isPrimary: true,
      );
      final event = DisplayChangedEvent(oldConfig: old, newConfig: next);
      expect(event.oldConfig.scaleFactor, 1.0);
      expect(event.newConfig.scaleFactor, 1.5);
    });

    test('exhaustive DisplayEvent switch', () {
      final events = <DisplayEvent>[
        DisplayAddedEvent(display: sampleDisplay()),
        const DisplayRemovedEvent(id: DisplayId('m1')),
        DisplayChangedEvent(
          oldConfig: sampleDisplay(),
          newConfig: sampleDisplay(),
        ),
      ];

      final tags = events
          .map(
            (e) => switch (e) {
              DisplayAddedEvent() => 'added',
              DisplayRemovedEvent() => 'removed',
              DisplayChangedEvent() => 'changed',
            },
          )
          .toList();

      expect(tags, ['added', 'removed', 'changed']);
    });
  });
}
