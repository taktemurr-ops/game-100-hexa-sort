import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:game_100_hexa_sort/game/rules.dart';

/// Level production test (doc 5.3 / 10: "Bölüm üretim testi 50.000 bölüm").
/// Normal CI: levels 1..150 + sample. Nightly (--dart-define=LONG=true):
/// levels 1..10.000 one by one + every 40th level up to 50.000 + all
/// challenges + all modes.
const bool long = bool.fromEnvironment('LONG');

void main() {
  final rules = createRules();
  final p = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('consecutive levels are valid and deterministic', () {
    final last = long ? 10000 : 150;
    var fallbacks = 0;
    for (var l = 1; l <= last; l++) {
      final g = rules.build(p.spec(l));
      expect(g.validation.ok, isTrue, reason: 'level $l');
      if (g.attempts >= 40) fallbacks++;
    }
    // Fallback = easier replacement level; must stay rare.
    expect(fallbacks, lessThan(last ~/ 20 + 2));
  }, timeout: const Timeout(Duration(hours: 2)));

  test('sampled levels up to 50.000 and beyond (endless)', () {
    final step = long ? 40 : 2500;
    for (var l = 10001; l <= 52000; l += step) {
      expect(rules.build(p.spec(l)).validation.ok, isTrue, reason: 'level $l');
    }
  }, timeout: const Timeout(Duration(hours: 2)));

  test('special challenges and every mode', () {
    final count = long ? LevelPlanner.challengeCount : 10;
    for (var c = 1; c <= count; c++) {
      expect(rules.build(p.challenge(c)).validation.ok, isTrue, reason: 'challenge $c');
    }
    for (final m in rules.modes) {
      for (var run = 1; run <= (long ? 50 : 3); run++) {
        final spec = switch (m) {
          GameModeId.campaign => p.spec(run * 37),
          GameModeId.daily => p.daily('2026-01-${(run % 28 + 1).toString().padLeft(2, '0')}'),
          GameModeId.weekly => p.weekly('2026-W${(run % 52 + 1).toString().padLeft(2, '0')}'),
          GameModeId.challenge => p.challenge(run),
          _ => p.run(m, run),
        };
        expect(rules.build(spec).validation.ok, isTrue, reason: '${m.name} $run');
      }
    }
  }, timeout: const Timeout(Duration(hours: 1)));

  test('same seed -> same level (determinism across runs)', () {
    for (final l in [1, 99, 1234, 49999]) {
      final a = rules.build(p.spec(l));
      final b = rules.build(p.spec(l));
      expect(a.spec.seed, b.spec.seed);
      expect(a.attempts, b.attempts);
    }
  });
}
