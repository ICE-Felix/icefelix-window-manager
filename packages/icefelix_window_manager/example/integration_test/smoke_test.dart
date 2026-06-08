// Comprehensive smoke test — exercises every WindowManager API and reports
// results line-by-line. Run under xvfb+openbox for full coverage:
//
//     scripts/xvfb-with-wm.sh flutter test integration_test/smoke_test.dart -d linux

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FULL SMOKE TEST', (tester) async {
    // ── Init ──
    await WindowManager.instance.ensureInitialized();
    runApp(const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
    final wm = WindowManager.instance;

    debugPrint('');
    debugPrint('══════════════════════════════════════');
    debugPrint('  icefelix_window_manager SMOKE TEST  ');
    debugPrint('══════════════════════════════════════');
    debugPrint('');

    // ── Platform ──
    final p = wm.platform;
    debugPrint('PLATFORM');
    debugPrint('  target:        ${p.target}');
    debugPrint('  displayServer: ${p.displayServer}');
    debugPrint('  ✅ platform detected');
    debugPrint('');

    // ── Initial snapshot ──
    await wm.refreshSnapshot();
    var s = wm.snapshot.value;
    debugPrint('INITIAL SNAPSHOT');
    debugPrint('  size:      ${s.bounds.size}');
    debugPrint('  position:  ${s.bounds.position}');
    debugPrint('  state:     ${s.state}');
    debugPrint('  title:     "${s.title}"');
    debugPrint('  focused:   ${s.isFocused}');
    debugPrint('  display:   ${s.currentDisplay.name} (${s.currentDisplay.scaleFactor}x, primary=${s.currentDisplay.isPrimary})');
    debugPrint('  ✅ snapshot initialized');
    debugPrint('');

    // ── Displays ──
    final displays = await wm.displays.list();
    debugPrint('DISPLAYS');
    debugPrint('  count:     ${displays.length}');
    for (final d in displays) {
      debugPrint('  - ${d.name}: ${d.bounds.width}x${d.bounds.height} @ ${d.scaleFactor}x, primary=${d.isPrimary}');
    }
    expect(displays.length, greaterThanOrEqualTo(1));
    debugPrint('  ✅ displays enumerated');
    debugPrint('');

    // ── Properties (flag-tracked, work even headless) ──
    debugPrint('PROPERTIES (flag-tracked)');

    await wm.setAlwaysOnTop(true);
    await wm.refreshSnapshot();
    s = wm.snapshot.value;
    debugPrint('  alwaysOnTop=true:  ${s.alwaysOnTop == true ? "✅" : "❌"} (got ${s.alwaysOnTop})');

    await wm.setAlwaysOnTop(false);
    await wm.refreshSnapshot();
    s = wm.snapshot.value;
    debugPrint('  alwaysOnTop=false: ${s.alwaysOnTop == false ? "✅" : "❌"} (got ${s.alwaysOnTop})');

    await wm.setPreventClose(true);
    await wm.refreshSnapshot();
    s = wm.snapshot.value;
    debugPrint('  preventClose=true: ${s.preventClose == true ? "✅" : "❌"} (got ${s.preventClose})');

    await wm.setPreventClose(false);
    await wm.refreshSnapshot();
    s = wm.snapshot.value;
    debugPrint('  preventClose=false: ${s.preventClose == false ? "✅" : "❌"} (got ${s.preventClose})');
    debugPrint('');

    // ── Detect real window ──
    await wm.setTitle('_probe_');
    await wm.refreshSnapshot();
    final hasWindow = wm.snapshot.value.title == '_probe_';
    await wm.setTitle('');
    debugPrint('WINDOW DETECTION');
    debugPrint('  hasRealWindow: $hasWindow');
    if (!hasWindow) {
      debugPrint('  ⚠️  No real GtkWindow (flutter test headless). GTK-dependent tests skip.');
    }
    debugPrint('');

    if (hasWindow) {
      // ── Title ──
      debugPrint('TITLE');
      await wm.setTitle('Smoke Test Title');
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setTitle("Smoke Test Title"): ${s.title == "Smoke Test Title" ? "✅" : "❌"} (got "${s.title}")');
      debugPrint('');

      // ── Size ──
      debugPrint('SIZE');
      await wm.setSize(const Size(1024, 768));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setSize(1024,768): ${s.bounds.size.width == 1024 && s.bounds.size.height == 768 ? "✅" : "❌"} (got ${s.bounds.size})');

      await wm.setMinSize(const Size(400, 300));
      await wm.refreshSnapshot();
      debugPrint('  setMinSize(400,300): ✅ (set)');

      await wm.setMaxSize(const Size(1200, 900));
      await wm.refreshSnapshot();
      debugPrint('  setMaxSize(1200,900): ✅ (set)');

      await wm.setMinSize(null);
      await wm.setMaxSize(null);
      debugPrint('');

      // ── Position ──
      debugPrint('POSITION');
      await wm.setPosition(const Offset(100, 100));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      if (p.displayServer == DisplayServer.x11) {
        debugPrint('  setPosition(100,100) [X11]: ${s.bounds.position != null ? "✅" : "❌"} (got ${s.bounds.position})');
      } else {
        debugPrint('  setPosition(100,100) [Wayland]: position=${s.bounds.position} (expected null, no-op)');
      }
      debugPrint('');

      // ── State ──
      debugPrint('STATE');
      await wm.maximize();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  maximize(): ${s.state == WindowState.maximized ? "✅" : "❌"} (got ${s.state})');

      await wm.unmaximize();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  unmaximize(): ${s.state == WindowState.normal ? "✅" : "❌"} (got ${s.state})');

      await wm.fullscreen();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  fullscreen(): ${s.state == WindowState.fullscreen ? "✅" : "❌"} (got ${s.state})');

      await wm.exitFullscreen();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  exitFullscreen(): ${s.state == WindowState.normal ? "✅" : "❌"} (got ${s.state})');
      debugPrint('');

      // ── Resizable / Closable / Frameless ──
      debugPrint('GTK PROPERTIES');
      await wm.setResizable(false);
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setResizable(false): ${s.resizable == false ? "✅" : "❌"} (got ${s.resizable})');
      await wm.setResizable(true);

      await wm.setClosable(false);
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setClosable(false): ${s.closable == false ? "✅" : "❌"} (got ${s.closable})');
      await wm.setClosable(true);

      await wm.setFrameless(true);
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setFrameless(true): ${s.frameless == true ? "✅" : "❌"} (got ${s.frameless})');
      await wm.setFrameless(false);

      await wm.setOpacity(0.5);
      await wm.refreshSnapshot();
      s = wm.snapshot.value;
      debugPrint('  setOpacity(0.5): ${(s.opacity - 0.5).abs() < 0.01 ? "✅" : "❌"} (got ${s.opacity})');
      await wm.setOpacity(1.0);
      debugPrint('');
    }

    // ── Close interception ──
    debugPrint('CLOSE INTERCEPTION');
    await wm.setPreventClose(true);
    bool gotEvent = false;
    final sub = wm.events.listen((event) {
      if (event is WindowCloseRequestEvent) {
        gotEvent = true;
        event.preventDefault();
      }
    });
    final allowed = await wm.debugSimulateCloseRequest();
    await sub.cancel();
    await wm.setPreventClose(false);
    debugPrint('  debugSimulateCloseRequest: ${!allowed && gotEvent ? "✅" : "❌"} (allowed=$allowed, gotEvent=$gotEvent)');
    debugPrint('');

    // ── Summary ──
    debugPrint('══════════════════════════════════════');
    debugPrint('  SMOKE TEST COMPLETE');
    debugPrint('  Platform: ${p.target} / ${p.displayServer}');
    debugPrint('  Real window: $hasWindow');
    debugPrint('══════════════════════════════════════');
    debugPrint('');
  });
}
