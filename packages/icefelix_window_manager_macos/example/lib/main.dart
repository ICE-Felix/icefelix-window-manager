// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';
import 'package:icefelix_window_manager_macos/icefelix_window_manager_macos.dart';

void main() {
  // Register the macOS plugin (normally Flutter does this auto via dartPluginClass,
  // but we call it explicitly here as a sanity check).
  IcefelixWindowManagerMacos.registerWith();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'icefelix_window_manager macOS example',
      home: Scaffold(
        appBar: AppBar(title: const Text('icefelix_window_manager — W2 dev')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'W2.1 scaffold. Native impls land in W2.2-W2.4.\n\n'
              'Any WindowManager call will currently fatalError on the macOS side '
              '(stub). Full functionality after W2.4.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
