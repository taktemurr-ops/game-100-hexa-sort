import 'package:flutter_test/flutter_test.dart';
import 'package:game_100_hexa_sort/core/clock.dart';
import 'package:game_100_hexa_sort/core/game_rules.dart';
import 'package:game_100_hexa_sort/core/game_session.dart';
import 'package:game_100_hexa_sort/core/level_plan.dart';
import 'package:game_100_hexa_sort/core/rng.dart';
import 'package:game_100_hexa_sort/core/save_store.dart';
import 'package:game_100_hexa_sort/core/telemetry.dart';
import 'package:game_100_hexa_sort/game/rules.dart';

/// 24-month operation simulation (doc 6, 10, 12): a virtual player opens
/// the game for 730 days with app restarts, clock tampering, offline
/// analytics, corrupted saves and every daily/weekly system - without any
/// human intervention. Invariants must hold for the whole period.
const bool long = bool.fromEnvironment('LONG');

void main() {
  test('730 virtual days of unattended operation', () async {
    final rules = createRules();
    final mem = MemoryBackend();
    final rnd = SeededRandom(2026);
    var now = DateTime(2026, 1, 1, 9);
    final days = long ? 730 : 120;
    var lastLevel = 1;
    var corrupted = false;
    final analytics = AnalyticsQueue(mem, enabled: true);

    for (var day = 0; day < days; day++) {
      final sessionsToday = rnd.range(0, 3); // some days the player skips
      for (var s = 0; s < sessionsToday; s++) {
        now = DateTime(now.year, now.month, now.day, 8 + s * 5, rnd.nextInt(60));
        final clockNow = now;
        // Every launch = fresh process (restart test).
        final session = GameSession(
          rules: rules,
          store: SaveStore(mem),
          clock: ClockGuard(now: () => clockNow),
          analytics: analytics,
        );
        await session.start();
        final save = session.save;
        if (!corrupted) {
          expect(save.currentLevel, greaterThanOrEqualTo(lastLevel), reason: 'progress lost on day $day');
        } else {
          // Recovered from the newest backup: at most one session is lost.
          expect(save.currentLevel, greaterThan(1));
          corrupted = false;
        }

        session.daily.claimLogin(save, session.now());
        session.daily.spinWheel(save, session.now());

        final rounds = rnd.range(2, 8);
        for (var r = 0; r < rounds; r++) {
          final mode = rnd.chance(0.75)
              ? GameModeId.campaign
              : rules.modes[rnd.nextInt(rules.modes.length)];
          final LevelSpec spec;
          switch (mode) {
            case GameModeId.campaign:
              spec = session.nextCampaignSpec;
              break;
            case GameModeId.daily:
              spec = session.planner.daily(DateKeys.day(session.now()));
              break;
            case GameModeId.weekly:
              spec = session.planner.weekly(DateKeys.week(session.now()));
              break;
            case GameModeId.challenge:
              spec = session.planner.challenge(rnd.range(1, LevelPlanner.challengeCount));
              break;
            default:
              spec = session.planner.run(mode, day * 10 + r);
          }
          // Generate a real level regularly to exercise the generator.
          if (r == 0 && day % (long ? 1 : 7) == 0) {
            expect(rules.build(spec).validation.ok, isTrue);
          }
          final win = rnd.chance(0.7);
          session.completeRound(
            spec,
            RoundResult(
              won: win,
              stars: win ? rnd.range(1, 3) : 0,
              score: rnd.range(0, 5000),
              seconds: rnd.range(5, 240),
              hintsUsed: rnd.chance(0.2) ? 1 : 0,
            ),
          );
        }
        for (final m in [...session.dailyMissions, ...session.weeklyMissions]) {
          session.claimMission(m);
        }
        session.daily.claimSurprise(save, session.now());
        expect(save.coins, greaterThanOrEqualTo(0));
        expect(save.hints, greaterThanOrEqualTo(0));
        expect(save.achievements.length, lessThanOrEqualTo(session.achievementCatalog.all.length));
        expect(await session.persist(), isTrue);
        lastLevel = save.currentLevel;

        // Offline most of the time; analytics flush occasionally succeeds.
        if (rnd.chance(0.2)) await analytics.flush(NoopSink());
      }

      // Disaster drills.
      if (day % 97 == 13) {
        mem.data['gs100.save'] = 'corrupted';
        corrupted = true;
      }
      if (day % 61 == 30) {
        // Player turns the clock back two days; rewards must not repeat.
        final probe = GameSession(
          rules: rules,
          store: SaveStore(mem),
          clock: ClockGuard(now: () => now.subtract(const Duration(days: 2))),
        );
        await probe.start();
        expect(probe.daily.claimLogin(probe.save, probe.now()), isNull);
        await probe.persist();
      }
      now = now.add(const Duration(days: 1));
    }

    final finalSession = GameSession(rules: rules, store: SaveStore(mem), clock: ClockGuard(now: () => now));
    await finalSession.start();
    expect(finalSession.save.currentLevel, greaterThanOrEqualTo(lastLevel));
    expect(finalSession.save.stat('sessions'), greaterThan(days ~/ 3));
    expect(analytics.length, lessThanOrEqualTo(analytics.maxEvents));
  }, timeout: const Timeout(Duration(hours: 2)));
}
