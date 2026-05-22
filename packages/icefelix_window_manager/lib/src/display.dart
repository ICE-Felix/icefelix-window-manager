// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';

/// Opaque display identifier. **Valid only for the current process session.**
///
/// Do NOT persist across app restarts — the same physical monitor may receive
/// a different ID after unplug/replug or session restart.
extension type const DisplayId(String value) {}

/// A physical or virtual display attached to the system.
@immutable
class Display {
  const Display({
    required this.id,
    this.name,
    required this.bounds,
    required this.workArea,
    this.physicalSize,
    this.dpi,
    required this.scaleFactor,
    required this.isPrimary,
    this.refreshRate,
  });

  /// Opaque identifier; do not persist (see [DisplayId]).
  final DisplayId id;

  /// Human-readable name (e.g. "Built-in Retina", "DELL U2720Q"). Null if unknown.
  final String? name;

  /// Total display area in logical px, **global virtual desktop coordinates**
  /// (origin = top-left of primary display; secondaries may have negative coords).
  final Rect bounds;

  /// Display area excluding taskbar/dock/menubar, in global coords.
  final Rect workArea;

  /// Physical dimensions in millimeters. **Null** for virtual displays or
  /// USB-C dongles that don't report EDID.
  final Size? physicalSize;

  /// Pixels per inch. **Null** if [physicalSize] is null (derived from it).
  final double? dpi;

  /// Logical-to-physical pixel ratio (1.0, 1.5, 2.0, …). Always known.
  final double scaleFactor;

  /// True if this is the system primary display.
  final bool isPrimary;

  /// Refresh rate in Hz. Null if unknown (Linux Wayland often null).
  final int? refreshRate;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Display &&
        other.id == id &&
        other.name == name &&
        other.bounds == bounds &&
        other.workArea == workArea &&
        other.physicalSize == physicalSize &&
        other.dpi == dpi &&
        other.scaleFactor == scaleFactor &&
        other.isPrimary == isPrimary &&
        other.refreshRate == refreshRate;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        bounds,
        workArea,
        physicalSize,
        dpi,
        scaleFactor,
        isPrimary,
        refreshRate,
      );

  @override
  String toString() =>
      'Display(id=$id, name=$name, bounds=$bounds, scale=$scaleFactor, '
      'primary=$isPrimary, refresh=$refreshRate)';
}
