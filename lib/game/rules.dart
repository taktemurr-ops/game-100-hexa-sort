import '../core/arcade.dart';
import '../core/level_plan.dart';
import '../core/missions.dart';
import '../core/stats.dart';
import 'casual_engine.dart';

class HexaSortRules extends ArcadeRules<CasualLevel> {
  @override
  String get gameId => 'game-100-hexa-sort';

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameStat> get gameStats => const [
        GameStat('hexes_cleared', 'Temizlenen altıgen', 'Hexes cleared', scale: 5000),
        GameStat('stacks_cleared', 'Temizlenen yığın', 'Stacks cleared', scale: 300),
        GameStat('hexes_placed', 'Yerleştirilen altıgen', 'Hexes placed', scale: 8000),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('hexes_cleared', 'hexes_cleared', [1250, 2500, 5000]),
        MissionTemplate('stacks_cleared', 'stacks_cleared', [37, 75, 150], coinReward: 80),
      ];

  @override
  CasualLevel generate(LevelSpec spec) => generateCasual(CasualKind.hexa, spec);

  @override
  ArcadeMeta metaOf(CasualLevel l) => l.meta;

  @override
  ArcadeSim createSim(CasualLevel l) => CasualSim(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => casualBot(sim);
}

ArcadeRules createRules() => HexaSortRules();
