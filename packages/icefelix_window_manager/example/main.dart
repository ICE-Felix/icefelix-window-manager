// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Minimal example showing the typical lifecycle:
//   1. ensureInitialized() once at startup
//   2. listen to events / snapshot reactively
//   3. drive the window via setters
//
// For an end-to-end testbed exercising every API method see
// `packages/icefelix_window_manager_macos/example/` in the repository.

import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});
  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final WindowManager _wm;

  @override
  void initState() {
    super.initState();
    _wm = WindowManager.instance;
    _wm.events.listen((event) {
      // ignore: avoid_print
      print('window event: ${event.runtimeType}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('icefelix_window_manager example')),
        body: Center(
          child: ValueListenableBuilder<WindowSnapshot>(
            valueListenable: _wm.snapshot,
            builder: (context, snap, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('size: ${snap.bounds.size}'),
                Text('state: ${snap.state.name}'),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => _wm.setSize(const Size(900, 600)),
                      child: const Text('Resize 900×600'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _wm.center,
                      child: const Text('Center'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _wm.maximize,
                      child: const Text('Maximize'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
