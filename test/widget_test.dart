import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_100_hexa_sort/app/app_state.dart';
import 'package:game_100_hexa_sort/app/bootstrap.dart';
import 'package:game_100_hexa_sort/app/services/ads.dart';
import 'package:game_100_hexa_sort/app/services/audio.dart';
import 'package:game_100_hexa_sort/app/services/purchases.dart';
import 'package:game_100_hexa_sort/core/game_session.dart';
import 'package:game_100_hexa_sort/core/save_store.dart';
import 'package:game_100_hexa_sort/core/telemetry.dart';
import 'package:game_100_hexa_sort/game/game_config.dart';

Future<AppState> _state({bool onboarded = true}) async {
  final mem = MemoryBackend();
  final session = GameSession(rules: gameConfig.rules, store: SaveStore(mem));
  await session.start();
  session.save.language = 'en';
  if (onboarded) {
    session.save
      ..ageGateDone = true
      ..adConsent = 'denied';
  }
  return AppState(
    config: gameConfig,
    session: session,
    audio: AudioService(),
    ads: NoAdsService(),
    purchases: NoPurchaseService(),
    analytics: AnalyticsQueue(mem),
    errors: ErrorJournal(mem),
    perf: PerformanceMonitor(),
  );
}

Widget _app(AppState s) => ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => s)],
      child: GameApp(state: s),
    );

void main() {
  testWidgets('first launch shows the age / privacy screen', (tester) async {
    final s = await _state(onboarded: false);
    await tester.pumpWidget(_app(s));
    await tester.pump();
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Essential only'), findsOneWidget);
  });

  testWidgets('home, every tab and a level start without errors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = await _state();
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Play'), findsOneWidget);

    for (final tab in ['Daily', 'Collection', 'Achievements', 'Profile', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: tab);
    }

    await tester.tap(find.text('Play'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);

    // Leave the round so periodic timers are disposed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('settings and shop open', (tester) async {
    final s = await _state();
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Settings'), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.storefront));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Restore purchases'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
