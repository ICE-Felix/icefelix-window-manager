// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'icefelix_window_manager — macOS testbed',
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
  final List<String> _eventLog = [];
  StreamSubscription<WindowEvent>? _eventsSub;
  StreamSubscription<DisplayEvent>? _displaySub;
  final _titleCtrl = TextEditingController(text: 'icefelix testbed');

  // Property flags
  bool _alwaysOnTop = false;
  bool _resizable = true;
  bool _movable = true;
  bool _minimizable = true;
  bool _maximizable = true;
  bool _closable = true;
  bool _frameless = false;
  bool _hasShadow = true;
  bool _preventClose = false;
  bool _hasUnsavedChanges = false;
  double _opacity = 1.0;
  TitleBarStyle _titleBarStyle = TitleBarStyle.normal;
  Color _bgColor = Colors.black;

  // Displays
  List<Display> _displays = [];

  @override
  void initState() {
    super.initState();
    _eventsSub = WindowManager.instance.events.listen((event) {
      String desc;
      switch (event) {
        case WindowResizeEvent(:final oldSize, :final newSize):
          desc = 'Resize: $oldSize -> $newSize';
        case WindowMoveEvent(:final oldPosition, :final newPosition):
          desc = 'Move: $oldPosition -> $newPosition';
        case WindowFocusEvent(:final focused):
          desc = 'Focus: $focused';
        case WindowStateChangeEvent(:final oldState, :final newState):
          desc = 'State: ${oldState.name} -> ${newState.name}';
        case WindowDisplayChangeEvent(:final oldDisplay, :final newDisplay):
          desc =
              'Display: ${oldDisplay.name ?? "?"} -> ${newDisplay.name ?? "?"}';
        case WindowCloseRequestEvent():
          desc = 'CloseRequest fired (unsaved=$_hasUnsavedChanges)';
          if (_hasUnsavedChanges) {
            event.preventDefault();
            _showSaveDialog();
          }
      }
      _appendLog(desc);
    });
    _displaySub = WindowManager.instance.displays.events.listen((event) {
      final desc = switch (event) {
        DisplayAddedEvent(:final display) =>
          'Display ADDED: ${display.name ?? display.id.value}',
        DisplayRemovedEvent(:final id) => 'Display REMOVED: ${id.value}',
        DisplayChangedEvent(:final newConfig) =>
          'Display CHANGED: ${newConfig.name ?? newConfig.id.value}',
      };
      _appendLog(desc);
    });
    _refreshDisplays();
  }

  void _appendLog(String s) {
    setState(() {
      _eventLog.insert(
        0,
        '${DateTime.now().toIso8601String().substring(11, 19)} $s',
      );
      if (_eventLog.length > 20) _eventLog.removeLast();
    });
  }

  Future<void> _refreshDisplays() async {
    final ds = await WindowManager.instance.displays.list();
    if (!mounted) return;
    setState(() => _displays = ds);
  }

  Future<void> _showSaveDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes. Discard or Cancel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (result == 'discard') {
      await WindowManager.instance.destroy();
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _displaySub?.cancel();
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('icefelix_window_manager — testbed')),
      body: ValueListenableBuilder<WindowSnapshot>(
        valueListenable: WindowManager.instance.snapshot,
        builder: (context, snap, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _snapshotPanel(snap),
                const SizedBox(height: 16),
                _section('Bounds', [
                  _btn('Center', () => WindowManager.instance.center()),
                  _btn(
                    'Set 800x600 @ (100,100)',
                    () => WindowManager.instance.setBounds(
                      const WindowBounds(
                        position: Offset(100, 100),
                        size: Size(800, 600),
                      ),
                    ),
                  ),
                  _btn(
                    'Set size 1024x768',
                    () => WindowManager.instance.setSize(const Size(1024, 768)),
                  ),
                  _btn(
                    'Set min 400x300',
                    () =>
                        WindowManager.instance.setMinSize(const Size(400, 300)),
                  ),
                  _btn(
                    'Set max 1200x900',
                    () => WindowManager.instance.setMaxSize(
                      const Size(1200, 900),
                    ),
                  ),
                  _btn('Clear min/max', () async {
                    await WindowManager.instance.setMinSize(null);
                    await WindowManager.instance.setMaxSize(null);
                  }),
                ]),
                _section('State', [
                  _btn('Minimize', () => WindowManager.instance.minimize()),
                  _btn('Maximize', () => WindowManager.instance.maximize()),
                  _btn('Unmaximize', () => WindowManager.instance.unmaximize()),
                  _btn('Restore', () => WindowManager.instance.restore()),
                  _btn('Hide (1s)', () async {
                    await WindowManager.instance.hide();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await WindowManager.instance.show();
                  }),
                  _btn('Fullscreen', () => WindowManager.instance.fullscreen()),
                  _btn(
                    'Exit fullscreen',
                    () => WindowManager.instance.exitFullscreen(),
                  ),
                ]),
                _section('Focus', [
                  _btn('Focus', () => WindowManager.instance.focus()),
                  _btn('Blur', () => WindowManager.instance.blur()),
                ]),
                _section('Title', [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Window title',
                      ),
                    ),
                  ),
                  _btn(
                    'Set title',
                    () => WindowManager.instance.setTitle(_titleCtrl.text),
                  ),
                ]),
                _section('Properties (toggles)', [
                  _toggle('Always on top', _alwaysOnTop, (v) async {
                    setState(() => _alwaysOnTop = v);
                    await WindowManager.instance.setAlwaysOnTop(v);
                  }),
                  _toggle('Resizable', _resizable, (v) async {
                    setState(() => _resizable = v);
                    await WindowManager.instance.setResizable(v);
                  }),
                  _toggle('Movable', _movable, (v) async {
                    setState(() => _movable = v);
                    await WindowManager.instance.setMovable(v);
                  }),
                  _toggle('Minimizable', _minimizable, (v) async {
                    setState(() => _minimizable = v);
                    await WindowManager.instance.setMinimizable(v);
                  }),
                  _toggle('Maximizable', _maximizable, (v) async {
                    setState(() => _maximizable = v);
                    await WindowManager.instance.setMaximizable(v);
                  }),
                  _toggle('Closable', _closable, (v) async {
                    setState(() => _closable = v);
                    await WindowManager.instance.setClosable(v);
                  }),
                  _toggle('Frameless', _frameless, (v) async {
                    setState(() => _frameless = v);
                    await WindowManager.instance.setFrameless(v);
                  }),
                  _toggle('Has shadow', _hasShadow, (v) async {
                    setState(() => _hasShadow = v);
                    await WindowManager.instance.setHasShadow(v);
                  }),
                ]),
                _section('TitleBarStyle', [
                  RadioGroup<TitleBarStyle>(
                    groupValue: _titleBarStyle,
                    onChanged: (v) async {
                      if (v != null) {
                        setState(() => _titleBarStyle = v);
                        await WindowManager.instance.setTitleBarStyle(v);
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in TitleBarStyle.values)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Radio<TitleBarStyle>(value: s),
                              Text(s.name),
                              const SizedBox(width: 16),
                            ],
                          ),
                      ],
                    ),
                  ),
                ]),
                _section('Visual', [
                  SizedBox(
                    width: 360,
                    child: Row(
                      children: [
                        const Text('Opacity: '),
                        Expanded(
                          child: Slider(
                            value: _opacity,
                            onChanged: (v) async {
                              setState(() => _opacity = v);
                              await WindowManager.instance.setOpacity(v);
                            },
                          ),
                        ),
                        Text(_opacity.toStringAsFixed(2)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Text('BG: '),
                      for (final c in [
                        Colors.black,
                        Colors.red,
                        Colors.blue,
                        Colors.green,
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () async {
                              setState(() => _bgColor = c);
                              await WindowManager.instance.setBackgroundColor(
                                c,
                              );
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c,
                                border: Border.all(
                                  color: _bgColor == c
                                      ? Colors.white
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ]),
                _section('Drag region (test with frameless = true)', [
                  Container(
                    height: 40,
                    color: Colors.blueGrey,
                    child: Listener(
                      onPointerDown: (_) => WindowManager.instance.startDrag(),
                      child: const Center(child: Text('-> DRAG ME <-')),
                    ),
                  ),
                ]),
                _section('Resize handles (test with frameless = true)', [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                            ),
                            child: const Center(child: Text('Resize\nedges')),
                          ),
                        ),
                        _resizeHandle(
                          Alignment.topLeft,
                          ResizeDirection.topLeft,
                        ),
                        _resizeHandle(Alignment.topCenter, ResizeDirection.top),
                        _resizeHandle(
                          Alignment.topRight,
                          ResizeDirection.topRight,
                        ),
                        _resizeHandle(
                          Alignment.centerLeft,
                          ResizeDirection.left,
                        ),
                        _resizeHandle(
                          Alignment.centerRight,
                          ResizeDirection.right,
                        ),
                        _resizeHandle(
                          Alignment.bottomLeft,
                          ResizeDirection.bottomLeft,
                        ),
                        _resizeHandle(
                          Alignment.bottomCenter,
                          ResizeDirection.bottom,
                        ),
                        _resizeHandle(
                          Alignment.bottomRight,
                          ResizeDirection.bottomRight,
                        ),
                      ],
                    ),
                  ),
                ]),
                _section('Close interception', [
                  _toggle('Prevent close', _preventClose, (v) async {
                    setState(() => _preventClose = v);
                    await WindowManager.instance.setPreventClose(v);
                  }),
                  _toggle('Has unsaved changes', _hasUnsavedChanges, (v) {
                    setState(() => _hasUnsavedChanges = v);
                  }),
                  _btn(
                    'close() (intercept-able)',
                    () => WindowManager.instance.close(),
                  ),
                  _btn(
                    'destroy() (force)',
                    () => WindowManager.instance.destroy(),
                  ),
                ]),
                _section('Multi-monitor', [
                  _btn('Refresh list', _refreshDisplays),
                  for (final d in _displays)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d.id.value}: ${d.name ?? "?"} '
                          '(${d.bounds.width.toInt()}x${d.bounds.height.toInt()} '
                          '@${d.scaleFactor}x, ${d.refreshRate ?? "?"}Hz, '
                          'primary=${d.isPrimary})',
                        ),
                        Row(
                          children: [
                            _btn(
                              'Move to',
                              () => WindowManager.instance.moveToDisplay(d.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                ]),
                _section('Event log (last 20)', [
                  Container(
                    height: 200,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(color: Colors.grey),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _eventLog.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'Menlo',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }

  Widget _btn(String label, Future<void> Function() onTap) => ElevatedButton(
        onPressed: () async {
          try {
            await onTap();
          } catch (e) {
            _appendLog('ERR: $e');
          }
        },
        child: Text(label),
      );

  Widget _toggle(String label, bool value, void Function(bool) onChanged) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: value, onChanged: onChanged),
          const SizedBox(width: 4),
          Text(label),
        ],
      );

  Widget _resizeHandle(Alignment align, ResizeDirection dir) {
    return Align(
      alignment: align,
      child: Listener(
        onPointerDown: (_) => WindowManager.instance.startResize(dir),
        child: Container(
          width: 24,
          height: 24,
          color: Colors.amber.withValues(alpha: 0.6),
          alignment: Alignment.center,
          child: Text(
            dir.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(fontSize: 10, color: Colors.black),
          ),
        ),
      ),
    );
  }

  Widget _snapshotPanel(WindowSnapshot snap) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SNAPSHOT (reactive)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Bounds: ${snap.bounds.size} @ ${snap.bounds.position}',
            style: const TextStyle(fontFamily: 'Menlo'),
          ),
          Text(
            'State: ${snap.state.name} | Focused: ${snap.isFocused} '
            '| Title: "${snap.title}"',
            style: const TextStyle(fontFamily: 'Menlo'),
          ),
          Text(
            'Display: ${snap.currentDisplay.name ?? "?"} '
            '(${snap.currentDisplay.scaleFactor}x, '
            '${snap.currentDisplay.refreshRate ?? "?"}Hz, '
            'primary=${snap.currentDisplay.isPrimary})',
            style: const TextStyle(fontFamily: 'Menlo'),
          ),
          Text(
            'alwaysOnTop=${snap.alwaysOnTop} resizable=${snap.resizable} '
            'frameless=${snap.frameless} preventClose=${snap.preventClose}',
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
          ),
        ],
      ),
    );
  }
}
