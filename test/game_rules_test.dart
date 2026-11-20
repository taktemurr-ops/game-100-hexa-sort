import 'package:flutter_test/flutter_test.dart';
import 'package:game_100_hexa_sort/core/arcade.dart';
import 'package:game_100_hexa_sort/core/level_plan.dart';
import 'package:game_100_hexa_sort/game/casual_engine.dart';
import 'package:game_100_hexa_sort/game/rules.dart';

void main() {
  final rules = HexaSortRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  CasualSim fresh([int n = 1]) => CasualSim(rules.build(planner.spec(n)).puzzle);

  test('a stuck board costs a life and restarts the same board', () {
    final s = fresh(4);
    final g = s.goalText;
    s.boardFailed();
    expect(s.lives, 2);
    expect(s.goalText, g);
  });

  test('autopilot clears the first twelve boards without losing a life', () {
    for (var n = 1; n <= 12; n++) {
      final s = fresh(n);
      expect(runBot(s, rules.bot, 60 * 60 * 6).won, isTrue, reason: 'level $n');
      expect(s.lives, 3, reason: 'level $n');
    }
  });

  test('hexa: same top colours gather and ten of a colour clear', () {
    final cells = <int, List<int>>{
      HexaSim.key(0, 0): [1, 1, 1, 1, 1],
      HexaSim.key(1, 0): [2, 1, 1, 1, 1, 1],
    };
    final cleared = HexaSim.resolve(cells, HexaSim.key(0, 0));
    expect(cleared, 10);
    expect(cells[HexaSim.key(1, 0)], [2]);
  });
}
