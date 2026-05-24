// polygon_demo — Flutter Windows app showcasing icefelix_window_manager's
// setShape API. Each instance picks its shape, position, label, and color
// from argv so we can fire up a swarm of differently-shaped windows for
// the promo screenshot:
//
//   polygon_demo.exe --shape=hexagon --x=400 --y=200 --color=8A2BE2 --label=Hex
//
// Supported shapes: triangle, square, diamond, pentagon, hexagon, heptagon,
// octagon, decagon, star5, star6, cross.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:icefelix_window_manager_windows/icefelix_window_manager_windows.dart';

const double _windowSize = 360.0;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  IcefelixWindowManagerWindows.registerWith();
  await WindowManager.instance.ensureInitialized();

  final cfg = _parseArgs(args);

  await WindowManager.instance.setFrameless(true);
  await WindowManager.instance.setSize(const Size(_windowSize, _windowSize));
  await WindowManager.instance.setOpacity(0.96);
  if (cfg.x != null && cfg.y != null) {
    await WindowManager.instance.setPosition(Offset(cfg.x!, cfg.y!));
  } else {
    await WindowManager.instance.center();
  }
  await WindowManager.instance.setShape(
    _shapePoints(cfg.shape, _windowSize),
  );

  runApp(_PolygonApp(label: cfg.label, color: cfg.color));
}

class _Cfg {
  _Cfg({
    required this.shape,
    required this.label,
    required this.color,
    this.x,
    this.y,
  });
  final String shape;
  final String label;
  final Color color;
  final double? x;
  final double? y;
}

_Cfg _parseArgs(List<String> args) {
  String shape = 'hexagon';
  String label = 'icefelix';
  int colorArgb = 0xFF8A2BE2; // blueviolet default
  double? x, y;
  for (final a in args) {
    if (a.startsWith('--shape=')) shape = a.substring(8);
    if (a.startsWith('--label=')) label = a.substring(8);
    if (a.startsWith('--color=')) {
      colorArgb = 0xFF000000 | int.parse(a.substring(8), radix: 16);
    }
    if (a.startsWith('--x=')) x = double.tryParse(a.substring(4));
    if (a.startsWith('--y=')) y = double.tryParse(a.substring(4));
  }
  return _Cfg(
    shape: shape,
    label: label,
    color: Color(colorArgb),
    x: x,
    y: y,
  );
}

// ============ Shape generators ============

List<Offset> _shapePoints(String name, double size) {
  switch (name) {
    case 'triangle':
      return _regularPolygon(3, size);
    case 'square':
      return _regularPolygon(4, size, rotation: pi / 4);
    case 'diamond':
      return _regularPolygon(4, size); // pointy-top square = diamond
    case 'pentagon':
      return _regularPolygon(5, size);
    case 'hexagon':
      return _regularPolygon(6, size);
    case 'heptagon':
      return _regularPolygon(7, size);
    case 'octagon':
      return _regularPolygon(8, size);
    case 'decagon':
      return _regularPolygon(10, size);
    case 'star5':
      return _starPolygon(5, size);
    case 'star6':
      return _starPolygon(6, size);
    case 'cross':
      return _crossPolygon(size);
    default:
      return _regularPolygon(6, size);
  }
}

List<Offset> _regularPolygon(int sides, double size, {double rotation = 0}) {
  final cx = size / 2;
  final cy = size / 2;
  final r = size / 2;
  final base = -pi / 2 + rotation;
  return [
    for (var i = 0; i < sides; i++)
      Offset(
        cx + r * cos(base + i * 2 * pi / sides),
        cy + r * sin(base + i * 2 * pi / sides),
      ),
  ];
}

List<Offset> _starPolygon(int spikes, double size) {
  // 2*spikes vertices: alternate outer + inner radius.
  final cx = size / 2;
  final cy = size / 2;
  final rOuter = size / 2;
  final rInner = rOuter * 0.45;
  final pts = <Offset>[];
  for (var i = 0; i < spikes * 2; i++) {
    final r = i.isEven ? rOuter : rInner;
    final angle = -pi / 2 + i * pi / spikes;
    pts.add(Offset(cx + r * cos(angle), cy + r * sin(angle)));
  }
  return pts;
}

List<Offset> _crossPolygon(double size) {
  // Plus / cross — 12-point polygon. Arm thickness = size/3.
  final s = size;
  final t = s / 3; // arm thickness
  final a = (s - t) / 2; // edge offset
  return [
    Offset(a, 0),         //  top-left of top arm
    Offset(a + t, 0),     //  top-right of top arm
    Offset(a + t, a),
    Offset(s, a),         //  top-right of right arm
    Offset(s, a + t),     //  bottom-right of right arm
    Offset(a + t, a + t),
    Offset(a + t, s),     //  bottom-right of bottom arm
    Offset(a, s),         //  bottom-left of bottom arm
    Offset(a, a + t),
    Offset(0, a + t),     //  bottom-left of left arm
    Offset(0, a),         //  top-left of left arm
    Offset(a, a),
  ];
}

// ============ UI ============

class _PolygonApp extends StatelessWidget {
  const _PolygonApp({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'icefelix polygon $label',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: color,
        body: _PolygonHome(label: label),
      ),
    );
  }
}

class _PolygonHome extends StatefulWidget {
  const _PolygonHome({required this.label});
  final String label;

  @override
  State<_PolygonHome> createState() => _PolygonHomeState();
}

class _PolygonHomeState extends State<_PolygonHome> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background drag layer (catch-all). The InkResponses above consume
        // their taps via Material so they never reach this Listener.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => WindowManager.instance.startDrag(),
          ),
        ),
        // Title-bar buttons at very top: minimize + close.
        Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _IconBtn(
                icon: Icons.remove,
                size: 28,
                onTap: () => WindowManager.instance.minimize(),
              ),
              const SizedBox(width: 12),
              _IconBtn(
                icon: Icons.close,
                size: 28,
                onTap: () => WindowManager.instance.destroy(),
              ),
            ],
          ),
        ),
        // Shape-type label ABOVE the counter (TRI / HEX / STAR5 / etc.).
        // Bigger + bolder than before so it reads as a section header.
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        // Counter — large number in the middle of the polygon.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Text(
                '$_count',
                style: const TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
        // Increment button — placed at y≈240 so it sits inside the visible
        // polygon for ALL shapes. For triangle (bottom edge y=270) and
        // star5 (whose central bottom area is a click-through "notch"
        // between the two bottom spikes), the original bottom:50 placement
        // was outside the polygon, making clicks pass through to the
        // desktop. bottom:110 keeps it in the safe interior zone.
        Positioned(
          bottom: 85,
          left: 0,
          right: 0,
          child: Center(
            child: _IconBtn(
              icon: Icons.add,
              size: 48,
              onTap: () => setState(() => _count++),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.size = 22,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: size * 0.7,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(size / 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: size * 0.6, color: Colors.white),
        ),
      ),
    );
  }
}
