// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Minimal smoke test — example app is a manual verification target for the
// macOS plugin Swift code (built via `flutter build macos`), not a unit-test
// host. Workspace `melos run test` excludes example/** by design.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icefelix_window_manager_macos_example/main.dart';

void main() {
  testWidgets('example app renders W2 status note', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('W2.1 scaffold'), findsOneWidget);
  });
}
