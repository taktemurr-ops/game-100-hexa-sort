import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_100_hexa_sort/app/app_state.dart';
import 'package:game_100_hexa_sort/app/bootstrap.dart';
import 'package:game_100_hexa_sort/app/screens/settings.dart';
import 'package:game_100_hexa_sort/app/screens/shop.dart';
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

  // Phones, small/large tablets (portrait + landscape), foldables, desktop web.
  for (final size in const [
    Size(375, 667), // small phone (iPhone SE 2nd/3rd gen)
    Size(430, 932), // large phone
    Size(673, 841), // foldable unfolded
    Size(768, 1024), // iPad portrait
    Size(1366, 1024), // iPad Pro 12.9 landscape
    Size(1280, 800), // Android tablet landscape
    Size(1920, 1080), // desktop browser
  ]) {
    testWidgets('layout works at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final s = await _state();
      await tester.pumpWidget(_app(s));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      final wide = size.width >= 840;
      expect(find.byType(NavigationRail), wide ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationBar), wide ? findsNothing : findsOneWidget);
      for (final tab in ['Daily', 'Collection', 'Achievements', 'Profile', 'Home']) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '$tab at $size');
      }
      await tester.tap(find.text('Play'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'play at $size');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('settings and shop open', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = await _state();
    await tester.pumpWidget(_app(s));
    await tester.pump(const Duration(milliseconds: 100));

    String texts() => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .where((t) => t.isNotEmpty)
        .join(' | ');

    final settings = find.byTooltip('Settings');
    expect(settings, findsOneWidget, reason: texts());
    await tester.tap(settings);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SettingsScreen), findsOneWidget, reason: texts());
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final shop = find.byTooltip('Shop');
    expect(shop, findsOneWidget, reason: texts());
    await tester.tap(shop);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ShopScreen), findsOneWidget, reason: texts());
    // The restore button sits at the end of the list (store policy: it must exist).
    await tester.scrollUntilVisible(find.text('Restore purchases'), 300,
        scrollable: find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Restore purchases'), findsOneWidget, reason: texts());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
