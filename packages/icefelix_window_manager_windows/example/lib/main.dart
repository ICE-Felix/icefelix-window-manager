// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Minimal Windows testbed. Session 1: exercises the bounds vertical
// (ensureInitialized + getBounds + setSize/setMin/setMaxSize + maximize) so
// you can verify the WndProc subclass + WM_GETMINMAXINFO + frame-coord
// behavior manually. The full 27-control testbed (matching the macOS one)
// lands in session 2.

import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_windows/icefelix_window_manager_windows.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  IcefelixWindowManagerWindows.registerWith();
  await WindowManager.instance.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'icefelix_window_manager — Windows testbed (session 1)',
      theme: ThemeData.dark(useMaterial3: true),
      home: const TestbedHome(),
    );
  }
}

class TestbedHome extends StatefulWidget {
  const TestbedHome({super.key});

  @override
  State<TestbedHome> createState() => _TestbedHomeState();
}

class _TestbedHomeState extends State<TestbedHome> {
  WindowSnapshot _snap = WindowManager.instance.snapshot.value;

  @override
  void initState() {
    super.initState();
    WindowManager.instance.snapshot.addListener(_onSnap);
  }

  void _onSnap() {
    if (!mounted) return;
    setState(() => _snap = WindowManager.instance.snapshot.value);
  }

  @override
  void dispose() {
    WindowManager.instance.snapshot.removeListener(_onSnap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Windows bounds vertical')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'bounds=${_snap.bounds}\n'
              'state=${_snap.state.name}\n'
              'display=${_snap.currentDisplay.name ?? "?"} '
              'scale=${_snap.currentDisplay.scaleFactor}',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () =>
                      WindowManager.instance.setSize(const Size(900, 700)),
                  child: const Text('setSize 900x700'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      WindowManager.instance.setSize(const Size(640, 480)),
                  child: const Text('setSize 640x480'),
                ),
                ElevatedButton(
                  onPressed: () => WindowManager.instance.center(),
                  child: const Text('center'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      WindowManager.instance.setMaxSize(const Size(1200, 900)),
                  child: const Text('setMaxSize 1200x900'),
                ),
                ElevatedButton(
                  onPressed: () => WindowManager.instance.setMaxSize(null),
                  child: const Text('clear maxSize'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      WindowManager.instance.setMinSize(const Size(400, 300)),
                  child: const Text('setMinSize 400x300'),
                ),
                ElevatedButton(
                  onPressed: () => WindowManager.instance.setMinSize(null),
                  child: const Text('clear minSize'),
                ),
                ElevatedButton(
                  onPressed: () => WindowManager.instance.maximize(),
                  child: const Text('maximize'),
                ),
                ElevatedButton(
                  onPressed: () => WindowManager.instance.unmaximize(),
                  child: const Text('unmaximize'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
