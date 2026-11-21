import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'casual_engine.dart';
import 'casual_view.dart';
import 'rules.dart';

final gameConfig = GameConfig(
  gameId: 'game-100-hexa-sort',
  title: const ['Altıgen Sıralama', 'Hexa Sort', 'Hexa-Sortieren', 'Hexa Ordenar', 'Tri Hexa'],
  tagline: const ['Renkleri yığ, birleştir, on tanesinde patlat!', 'Stack, merge and blast ten of a colour!', 'Stapeln, verbinden, zehn auflösen!', '¡Apila y junta diez!', 'Empilez et réunissez-en dix !'],
  seedColor: const Color(0xFF9D4EDD),
  icon: Icons.hexagon,
  rules: HexaSortRules(),
  buildPlay: (ctx) => ArcadeStage(
    ctx: ctx,
    create: () => CasualSim((ctx.generated as GeneratedLevel<CasualLevel>).puzzle),
    paint: paintCasual,
    sound: casualSound,
    boosterIcon: Icons.hardware,
    boosterLabel: (l) => l == 'tr' ? 'Çekiç' : 'Hammer',
    howTo: const ['Alttan bir yığın seç (ilk yığın seçili gelir), sonra boş bir hücreye dokun.', 'Pick a stack at the bottom (the first is pre-selected), then tap an empty cell.', 'Stapel wählen, dann leere Zelle.', 'Elige una pila y una celda vacía.', 'Choisissez une pile puis une case vide.'],
  ),
  tutorial: const [
    TutorialStep(Icons.touch_app, ['Yığını seç, boş hücreye koy.', 'Pick a stack, place it.', 'Stapel setzen.', 'Coloca una pila.', 'Placez une pile.']),
    TutorialStep(Icons.call_merge, ['Aynı üst renkler toplanır.', 'Equal top colours gather.', 'Gleiche Farben sammeln sich.', 'Colores iguales se juntan.', 'Les couleurs se rassemblent.']),
    TutorialStep(Icons.looks_one, ['10 aynı renk = patlama!', '10 of a colour = blast!', '10 gleiche = Explosion!', '¡10 iguales = explosión!', '10 pareils = explosion !']),
  ],
);
