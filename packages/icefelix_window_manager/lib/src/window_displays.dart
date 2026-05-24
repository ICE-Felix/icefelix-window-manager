// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import 'display.dart';
import 'messages.g.dart';
import 'window_event.dart';
import 'window_manager_platform.dart';

/// Multi-monitor sub-namespace.
///
/// Access via `WindowManager.instance.displays`.
class WindowDisplays {
  WindowDisplays._();

  final StreamController<DisplayEvent> _events =
      StreamController<DisplayEvent>.broadcast();
  List<Display>? _lastKnown;

  /// Fresh query — bypasses any cache, calls native each time.
  Future<List<Display>> list() async {
    final pigeons = await WindowManagerPlatform.instance.listDisplays();
    return pigeons.map(convertDisplayRaw).toList(growable: false);
  }

  Future<Display> getCurrent() async {
    final p = await WindowManagerPlatform.instance.getCurrentDisplay();
    return convertDisplayRaw(p);
  }

  Future<Display> getPrimary() async {
    final p = await WindowManagerPlatform.instance.getPrimaryDisplay();
    return convertDisplayRaw(p);
  }

  /// **Broadcast stream**. Hot-plug aware: connect/disconnect/config-change events.
  Stream<DisplayEvent> get events => _events.stream;

  /// Internal: seed initial known displays so the first [handleDisplaysChanged]
  /// call doesn't emit phantom Added events for already-known displays.
  /// Called by [WindowManager.ensureInitialized].
  @internal
  void seedLastKnown(List<Display> initial) {
    _lastKnown = List<Display>.unmodifiable(initial);
  }

  /// Called by [WindowManager] when FlutterApi.onDisplaysChanged fires.
  /// Diff old vs current and emit Added/Removed/Changed events.
  void handleDisplaysChanged(List<DisplayRaw> pigeons) {
    final current = pigeons.map(convertDisplayRaw).toList(growable: false);
    final old = _lastKnown ?? const <Display>[];

    final currentIds = current.map((d) => d.id.value).toSet();
    final oldIds = old.map((d) => d.id.value).toSet();

    // Removed: ids in old not in current.
    for (final o in old) {
      if (!currentIds.contains(o.id.value)) {
        _events.add(DisplayRemovedEvent(id: o.id));
      }
    }

    // Added: ids in current not in old.
    for (final c in current) {
      if (!oldIds.contains(c.id.value)) {
        _events.add(DisplayAddedEvent(display: c));
      }
    }

    // Changed: same id, different fields.
    for (final c in current) {
      if (!oldIds.contains(c.id.value)) continue; // Added, already handled
      final o = old.firstWhere((d) => d.id == c.id);
      if (o != c) {
        _events.add(DisplayChangedEvent(oldConfig: o, newConfig: c));
      }
    }

    _lastKnown = current;
  }

  void dispose() {
    _events.close();
  }
}

// Internal factory + visible converter (shared with WindowManager).

WindowDisplays createWindowDisplays() => WindowDisplays._();

Display convertDisplayRaw(DisplayRaw p) {
  return Display(
    id: DisplayId(p.id),
    name: p.name,
    bounds:
        Rect.fromLTWH(p.bounds.x, p.bounds.y, p.bounds.width, p.bounds.height),
    workArea: Rect.fromLTWH(
      p.workArea.x,
      p.workArea.y,
      p.workArea.width,
      p.workArea.height,
    ),
    physicalSize: (p.physicalWidthMm != null && p.physicalHeightMm != null)
        ? Size(p.physicalWidthMm!, p.physicalHeightMm!)
        : null,
    dpi: p.dpi,
    scaleFactor: p.scaleFactor,
    isPrimary: p.isPrimary,
    refreshRate: p.refreshRate,
  );
}
