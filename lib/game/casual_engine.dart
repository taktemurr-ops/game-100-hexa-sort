import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Casual sorting / merging puzzles on the shared arcade framework:
/// merge fruits (physics), screw puzzle, goods sort, triple tile match and
/// hexa sort. Every board is generated from the level seed and proven
/// solvable: the tile and screw puzzles are built backwards from a random
/// legal removal order, goods sort boards are checked by a solver, and the
/// merge / hexa boards are played through by the autopilot.
enum CasualKind { merge, screw, goods, tile, hexa }

class CasualLevel {
  final ArcadeMeta meta;
  final CasualKind kind;
  final int difficulty;
  final int theme;
  const CasualLevel(this.meta, this.kind, this.difficulty, this.theme);
}

CasualLevel generateCasual(CasualKind kind, LevelSpec spec) =>
    CasualLevel(ArcadeMeta.of(spec), kind, spec.difficulty.clamp(1, 10), spec.theme % 4);

abstract class CasualSim extends ArcadeSim {
  final CasualLevel level;
  int board = 0; // boards finished in this run
  int lastEvent = 0; // 1 move, 2 good, 3 great, 4 bad, 5 board done
  String flash = '';
  int flashTicks = 0;
  int freeze = 0;
  bool wasDown = false;

  /// Autopilot scratch (never read by the game rules).
  int botWait = 0;
  final List<int> botPlan = [];

  factory CasualSim(CasualLevel l) => switch (l.kind) {
        CasualKind.merge => MergeSim(l),
        CasualKind.screw => ScrewSim(l),
        CasualKind.goods => GoodsSim(l),
        CasualKind.tile => TileSim(l),
        CasualKind.hexa => HexaSim(l),
      };

  CasualSim.base(this.level) : super(level.meta, lives: 3) {
    setupBoard();
  }

  int get rd => (level.difficulty + (meta.goal ? 0 : board ~/ 2)).clamp(1, 10);
  int get boardSeed => mixSeed([meta.seed, 4111, board]);

  void setupBoard();

  void step(ArcadeInput i);

  bool get boardComplete;

  double get boardProgress;

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    if (freeze > 0) freeze--;
    step(input);
    wasDown = input.down && input.hasPointer;
    if (over) return;
    if (boardComplete) {
      score += 500;
      board++;
      lastEvent = 5;
      say('CLEAR!');
      if (meta.goal) {
        win();
        return;
      }
      botPlan.clear();
      setupBoard();
    }
  }

  void say(String s) {
    flash = s;
    flashTicks = 60;
  }

  /// The board is stuck: costs a life and restarts the same board.
  void boardFailed() {
    lastEvent = 4;
    if (meta.zen) {
      botPlan.clear();
      setupBoard();
      return;
    }
    shield = 0;
    hit();
  }

  @override
  void onLifeLost() {
    botPlan.clear();
    setupBoard();
  }

  @override
  bool useSlow() => false;

  @override
  double get progress => meta.goal ? boardProgress.clamp(0.0, 1.0) : 0;

  @override
  int get stars => won ? lifeStars(this, 3) : 0;
}

// ---------------------------------------------------------------------------
// 096 Merge fruits (drop & merge physics).

const kFruitR = [26.0, 34.0, 43.0, 53.0, 63.0, 75.0, 88.0, 101.0, 114.0, 128.0, 145.0];
const double kBoxL = 150, kBoxR = 850, kBoxT = 330, kBoxB = 1450, kDangerY = 400;

class Fruit {
  double x, y, vx = 0, vy = 0;
  int tier;
  int age = 0;
  bool dead = false;
  Fruit(this.x, this.y, this.tier);
  double get r => kFruitR[tier];
}

class MergeSim extends CasualSim {
  final List<Fruit> fruits = [];
  int next = 0, after = 0;
  double aimX = 500;
  bool aiming = false;
  int cooldown = 0, danger = 0, dropCount = 0;
  int targetTier = 6, bestTier = 0, merges = 0, bigFruits = 0;
  MergeSim(super.l) : super.base();

  SeededRandom _dropRng(int n) => SeededRandom(mixSeed([boardSeed, n, 96]));

  int _pickTier(int n) {
    final r = _dropRng(n);
    final w = r.nextDouble();
    return w < 0.32 ? 0 : (w < 0.6 ? 1 : (w < 0.82 ? 2 : (w < 0.95 ? 3 : 4)));
  }

  @override
  void setupBoard() {
    fruits.clear();
    dropCount = 0;
    next = _pickTier(0);
    after = _pickTier(1);
    cooldown = 0;
    danger = 0;
    bestTier = 0;
    targetTier = (4 + rd ~/ 2).clamp(5, 9);
  }

  void _drop() {
    final r = kFruitR[next];
    final x = clampD(aimX, kBoxL + r, kBoxR - r);
    fruits.add(Fruit(x, kBoxT + r * 0.2 - 40, next));
    dropCount++;
    next = after;
    after = _pickTier(dropCount + 1);
    cooldown = 26;
    lastEvent = 1;
  }

  @override
  void step(ArcadeInput i) {
    if (cooldown > 0) cooldown--;
    if (i.down && i.hasPointer) {
      aimX = i.x;
      aiming = true;
    } else if (aiming) {
      aiming = false;
      if (cooldown == 0) _drop();
    }
    if (i.dirX != 0) aimX = clampD(aimX + i.dirX * 12, kBoxL, kBoxR);
    if (i.tap && !i.hasPointer && cooldown == 0) _drop();
    _physics();
    // danger line: settled fruit above the line for 2 seconds ends the board
    var above = false;
    for (final f in fruits) {
      if (f.age > 50 && f.y - f.r < kDangerY && f.vy.abs() < 2) above = true;
    }
    danger = above ? danger + 1 : 0;
    if (danger > 120 && !meta.zen) boardFailed();
    if (danger > 120 && meta.zen) {
      // zen: clear the top half instead of failing
      fruits.removeWhere((f) => f.y < 800);
      danger = 0;
    }
  }

  static void physicsStep(List<Fruit> fs, void Function(Fruit a, Fruit b) onMerge) {
    for (final f in fs) {
      f.vy += 0.6;
      f.vx *= 0.99;
      f.vy *= 0.995;
      f.x += f.vx;
      f.y += f.vy;
      f.age++;
    }
    for (var it = 0; it < 4; it++) {
      for (var a = 0; a < fs.length; a++) {
        final p = fs[a];
        if (p.dead) continue;
        for (var b = a + 1; b < fs.length; b++) {
          final q = fs[b];
          if (q.dead) continue;
          final dx = q.x - p.x, dy = q.y - p.y;
          final rr = p.r + q.r;
          final d2 = dx * dx + dy * dy;
          if (d2 >= rr * rr || d2 < 1e-6) continue;
          if (p.tier == q.tier && p.tier < kFruitR.length) {
            onMerge(p, q);
            continue;
          }
          final dist = math.sqrt(d2);
          final nx = dx / dist, ny = dy / dist;
          final pen = rr - dist;
          final mp = p.r * p.r, mq = q.r * q.r;
          final tp = mq / (mp + mq), tq = mp / (mp + mq);
          p.x -= nx * pen * tp;
          p.y -= ny * pen * tp;
          q.x += nx * pen * tq;
          q.y += ny * pen * tq;
          final rv = (q.vx - p.vx) * nx + (q.vy - p.vy) * ny;
          if (rv < 0) {
            final j = -1.2 * rv / (1 / mp + 1 / mq);
            p.vx -= j * nx / mp;
            p.vy -= j * ny / mp;
            q.vx += j * nx / mq;
            q.vy += j * ny / mq;
          }
        }
      }
      for (final f in fs) {
        if (f.x - f.r < kBoxL) {
          f.x = kBoxL + f.r;
          f.vx = f.vx.abs() * 0.3;
        } else if (f.x + f.r > kBoxR) {
          f.x = kBoxR - f.r;
          f.vx = -f.vx.abs() * 0.3;
        }
        if (f.y + f.r > kBoxB) {
          f.y = kBoxB - f.r;
          f.vy = -f.vy.abs() * 0.2;
          f.vx *= 0.9;
        }
      }
    }
    fs.removeWhere((f) => f.dead);
  }

  void _physics() {
    physicsStep(fruits, (p, q) {
      p.dead = true;
      q.dead = true;
      final t = p.tier + 1;
      merges++;
      if (t >= kFruitR.length) {
        score += 2000;
        bigFruits++;
        lastEvent = 3;
        return;
      }
      final nf = Fruit((p.x + q.x) / 2, (p.y + q.y) / 2, t)..age = 60;
      fruits.add(nf);
      score += (t + 1) * (t + 1) * 5;
      if (t > bestTier) bestTier = t;
      if (t >= 6) bigFruits++;
      lastEvent = t >= 5 ? 3 : 2;
    });
  }

  @override
  bool get boardComplete => meta.goal && bestTier >= targetTier;

  @override
  double get boardProgress => bestTier / targetTier;

  @override
  String get goalText => meta.goal ? '${bestTier + 1}/${targetTier + 1}' : '${bestTier + 1}';

  @override
  bool useBooster() {
    // Shake: removes the smallest fruits on the board.
    if (over) return false;
    fruits.removeWhere((f) => f.tier <= 1);
    danger = 0;
    return true;
  }

  @override
  Map<String, int> get stats => {
        'merges': merges,
        'big_fruits': bigFruits,
        'best_fruit': bestTier + 1,
      };
}

// ---------------------------------------------------------------------------
// 097 Screw puzzle.

class Plate {
  final double x, y, w, h;
  final int z;
  final int color;
  bool fallen = false;
  double fall = 0;
  Plate(this.x, this.y, this.w, this.h, this.z, this.color);
  bool covers(double px, double py) => px > x - 22 && px < x + w + 22 && py > y - 22 && py < y + h + 22;
}

class Screw {
  final double x, y;
  final int plate;
  int color;
  bool gone = false;
  Screw(this.x, this.y, this.plate, this.color);
}

class ScrewSim extends CasualSim {
  final List<Plate> plates = [];
  final List<Screw> screws = [];
  final List<int> boxes = []; // colour queue (3 screws each)
  int boxIdx = 0;
  final List<int> boxFill = [0, 0];
  final List<int> buffer = []; // colours of parked screws
  int bufferCap = 5;
  final List<int> order = []; // proven removal order (autopilot)
  int removed = 0, totalRemoved = 0, boxesDone = 0, platesDropped = 0;
  ScrewSim(super.l) : super.base();

  int get colors => (3 + rd ~/ 2).clamp(3, 7);

  @override
  void setupBoard() {
    final r = SeededRandom(boardSeed);
    final d = rd;
    plates.clear();
    screws.clear();
    boxes.clear();
    buffer.clear();
    order.clear();
    boxIdx = 0;
    boxFill[0] = boxFill[1] = 0;
    removed = 0;
    bufferCap = d <= 3 ? 6 : (d <= 7 ? 5 : 4);
    final nPlates = (4 + d).clamp(5, 13);
    for (var p = 0; p < nPlates; p++) {
      final w = 200.0 + r.nextDouble() * 330, h = 90.0 + r.nextDouble() * 120;
      final x = 120 + r.nextDouble() * (760 - w), y = 330 + r.nextDouble() * (760 - h);
      plates.add(Plate(x, y, w, h, p, r.nextInt(6)));
      final holes = 2 + r.nextInt(d >= 4 ? 3 : 2);
      for (var k = 0; k < holes; k++) {
        final sx = holes == 1 ? x + w / 2 : x + 30 + (w - 60) * k / (holes - 1);
        final sy = k.isEven ? y + 30 : y + h - 30;
        screws.add(Screw(sx, sy, p, -1));
      }
    }
    // screw count multiple of 3
    while (screws.length % 3 != 0) {
      screws.removeLast();
    }
    // random legal removal order; colours assigned in triples along it
    final gone = List<bool>.filled(screws.length, false);
    final plateGone = List<bool>.filled(plates.length, false);
    for (final p in plates) {
      if (!screws.any((s) => s.plate == p.z)) {
        p.fallen = true;
        plateGone[p.z] = true;
      }
    }
    var tripleColor = r.nextInt(colors);
    for (var n = 0; n < screws.length; n++) {
      final free = <int>[];
      for (var k = 0; k < screws.length; k++) {
        if (!gone[k] && _freeWith(k, plateGone)) free.add(k);
      }
      final k = free[r.nextInt(free.length)];
      gone[k] = true;
      order.add(k);
      if (n % 3 == 0) {
        tripleColor = (tripleColor + 1 + r.nextInt(colors - 1)) % colors;
        boxes.add(tripleColor);
      }
      screws[k].color = tripleColor;
      final p = screws[k].plate;
      if (screws.every((s) => s.plate != p || gone[screws.indexOf(s)])) plateGone[p] = true;
    }
  }

  bool _freeWith(int k, List<bool> plateGone) {
    final s = screws[k];
    for (final p in plates) {
      if (p.z > plates[s.plate].z && !plateGone[p.z] && p.covers(s.x, s.y)) return false;
    }
    return true;
  }

  bool isFree(int k) {
    final s = screws[k];
    if (s.gone) return false;
    for (final p in plates) {
      if (p.z > plates[s.plate].z && !p.fallen && p.covers(s.x, s.y)) return false;
    }
    return true;
  }

  /// Colour of active box slot 0/1 (-1 none).
  int activeBox(int i) => boxIdx + i < boxes.length ? boxes[boxIdx + i] : -1;

  void _take(int k) {
    final s = screws[k];
    s.gone = true;
    removed++;
    totalRemoved++;
    var placed = false;
    for (var b = 0; b < 2; b++) {
      if (activeBox(b) == s.color && boxFill[b] < 3) {
        boxFill[b]++;
        placed = true;
        break;
      }
    }
    if (!placed) {
      buffer.add(s.color);
      lastEvent = 1;
    } else {
      lastEvent = 2;
      score += 10;
    }
    final p = s.plate;
    if (screws.every((o) => o.plate != p || o.gone)) {
      plates[p].fallen = true;
      platesDropped++;
      score += 30;
    }
    _settleBoxes();
    if (buffer.length > bufferCap) boardFailed();
  }

  void _settleBoxes() {
    var changed = true;
    while (changed) {
      changed = false;
      for (var b = 0; b < 2; b++) {
        if (activeBox(b) < 0) continue;
        if (boxFill[b] >= 3) {
          // box done: it leaves and the queue slides up
          boxesDone++;
          score += 50;
          lastEvent = 3;
          boxes.removeAt(boxIdx + b);
          if (b == 0) boxFill[0] = boxFill[1];
          boxFill[1] = 0;
          changed = true;
          break;
        }
        // pull matching parked screws
        final c = activeBox(b);
        while (boxFill[b] < 3 && buffer.contains(c)) {
          buffer.remove(c);
          boxFill[b]++;
          changed = true;
        }
      }
    }
  }

  @override
  void step(ArcadeInput i) {
    for (final p in plates) {
      if (p.fallen && p.fall < 1) p.fall = math.min(1, p.fall + 0.05);
    }
    if (!(i.tap && i.hasPointer)) return;
    // topmost screw under the finger (free ones first)
    var best = -1;
    for (var k = 0; k < screws.length; k++) {
      final s = screws[k];
      if (s.gone) continue;
      if ((s.x - i.x) * (s.x - i.x) + (s.y - i.y) * (s.y - i.y) >= 34 * 34) continue;
      if (best < 0 || (isFree(k) && !isFree(best)) || (isFree(k) == isFree(best) && s.plate > screws[best].plate)) best = k;
    }
    if (best < 0) return;
    if (isFree(best)) {
      _take(best);
    } else {
      lastEvent = 4;
    }
  }

  @override
  bool get boardComplete => screws.every((s) => s.gone) && buffer.isEmpty;

  @override
  double get boardProgress => screws.isEmpty ? 1 : removed / screws.length;

  @override
  String get goalText => '$removed/${screws.length} • ${buffer.length}/$bufferCap';

  @override
  bool useBooster() {
    // Extra slot in the parking tray.
    if (over) return false;
    bufferCap++;
    return true;
  }

  @override
  Map<String, int> get stats => {
        'screws_removed': totalRemoved,
        'boxes_filled': boxesDone,
        'plates_dropped': platesDropped,
      };
}

// ---------------------------------------------------------------------------
// 098 Goods sort: three of a kind on a shelf clears it.

class Shelf {
  final List<int> front = [-1, -1, -1];
  final List<List<int>> back = []; // layers behind (each 3, -1 empty)
  Shelf copy() {
    final s = Shelf();
    for (var k = 0; k < 3; k++) {
      s.front[k] = front[k];
    }
    for (final l in back) {
      s.back.add(List.of(l));
    }
    return s;
  }
}

class GoodsSim extends CasualSim {
  final List<Shelf> shelves = [];
  int cols = 3;
  int selShelf = -1, selSlot = -1;
  int items = 0, cleared = 0, totalCleared = 0, moves = 0, moveLimit = 0, combos = 0;
  GoodsSim(super.l) : super.base();

  @override
  void setupBoard() {
    final d = rd;
    for (var attempt = 0; attempt < 30; attempt++) {
      final r = SeededRandom(mixSeed([boardSeed, attempt]));
      shelves.clear();
      final n = (4 + d ~/ 2).clamp(4, 9);
      cols = n <= 4 ? 2 : 3;
      final types = (n + 1 + d ~/ 3).clamp(4, 12);
      final layers = d <= 2 ? 1 : (d <= 6 ? 2 : 3);
      final pool = <int>[];
      for (var t = 0; t < types; t++) {
        pool.addAll([t, t, t]);
      }
      pool.shuffle(math.Random(mixSeed([boardSeed, attempt, 7])));
      // capacity: n shelves * layers * 3, keep a few holes in the front row
      final cap = n * layers * 3;
      while (pool.length > cap - 3) {
        final t = pool.removeLast();
        pool.removeWhere((x) => x == t);
      }
      for (var s = 0; s < n; s++) {
        final sh = Shelf();
        for (var l = 1; l < layers; l++) {
          sh.back.add([-1, -1, -1]);
        }
        shelves.add(sh);
      }
      // fill back layers first, then fronts, leaving holes in front
      var p = 0;
      for (var l = layers - 2; l >= 0; l--) {
        for (final sh in shelves) {
          for (var k = 0; k < 3 && p < pool.length; k++) {
            if (r.chance(0.85)) sh.back[l][k] = pool[p++];
          }
        }
      }
      final frontSlots = <(int, int)>[];
      for (var s = 0; s < n; s++) {
        for (var k = 0; k < 3; k++) {
          frontSlots.add((s, k));
        }
      }
      frontSlots.shuffle(math.Random(mixSeed([boardSeed, attempt, 9])));
      for (final (s, k) in frontSlots) {
        if (p < pool.length) shelves[s].front[k] = pool[p++];
      }
      if (p < pool.length) continue;
      // empty shelves pull the next layer forward
      for (final sh in shelves) {
        _promote(sh);
      }
      items = pool.length;
      cleared = 0;
      moves = 0;
      selShelf = -1;
      final sol = solveGoods(shelves.map((s) => s.copy()).toList(), 40000);
      if (sol != null) {
        moveLimit = sol.length ~/ 2 + 8 + (10 - d);
        botPlan
          ..clear()
          ..addAll(sol);
        return;
      }
    }
    // fallback: trivially solvable
    shelves
      ..clear()
      ..add(Shelf()..front.setAll(0, [0, 0, 1]))
      ..add(Shelf()..front.setAll(0, [1, 1, 0]))
      ..add(Shelf());
    items = 6;
    moveLimit = 6;
    botPlan
      ..clear()
      ..addAll(solveGoods(shelves.map((s) => s.copy()).toList(), 10000)!);
  }

  static bool _promote(Shelf sh) {
    var changed = false;
    while (sh.front.every((x) => x < 0) && sh.back.isNotEmpty) {
      final l = sh.back.removeLast();
      sh.front.setAll(0, l);
      changed = true;
    }
    return changed;
  }

  static int _clearTriples(List<Shelf> ss) {
    var n = 0;
    for (final sh in ss) {
      if (sh.front[0] >= 0 && sh.front[0] == sh.front[1] && sh.front[1] == sh.front[2]) {
        sh.front.setAll(0, [-1, -1, -1]);
        n++;
      }
      _promote(sh);
    }
    return n;
  }

  /// Moves the item in (from,slot) to the first free slot of shelf [to].
  static bool applyMove(List<Shelf> ss, int from, int slot, int to) {
    if (from == to) return false;
    final it = ss[from].front[slot];
    if (it < 0) return false;
    final free = ss[to].front.indexOf(-1);
    if (free < 0) return false;
    ss[from].front[slot] = -1;
    ss[to].front[free] = it;
    _promote(ss[from]);
    return true;
  }

  /// Depth-first solver; returns moves as flat [from, slot*10+to, ...].
  static List<int>? solveGoods(List<Shelf> start, int budget) {
    final seen = <String>{};
    var nodes = 0;
    List<int>? dfs(List<Shelf> ss, int depth) {
      if (ss.every((s) => s.front.every((x) => x < 0) && s.back.isEmpty)) return [];
      if (++nodes > budget || depth > 120) return null;
      final k = ss.map((s) => '${(List.of(s.front)..sort()).join(',')}/${s.back.map((l) => l.join(',')).join(';')}').join('|');
      if (!seen.add(k)) return null;
      // candidate moves ranked: completing a triple first, then pairing
      final cand = <(int, int, int, int)>[];
      for (var f = 0; f < ss.length; f++) {
        for (var sl = 0; sl < 3; sl++) {
          final it = ss[f].front[sl];
          if (it < 0) continue;
          for (var t = 0; t < ss.length; t++) {
            if (t == f || !ss[t].front.contains(-1)) continue;
            final same = ss[t].front.where((x) => x == it).length;
            final empties = ss[t].front.where((x) => x < 0).length;
            var v = same * 10 - (same == 0 && empties < 3 ? 6 : 0);
            if (same == 0 && empties == 3) v -= 2;
            // emptying a shelf reveals the back
            if (ss[f].front.where((x) => x >= 0).length == 1) v += 3;
            cand.add((v, f, sl, t));
          }
        }
      }
      cand.sort((a, b) => b.$1.compareTo(a.$1));
      for (final (_, f, sl, t) in cand.take(14)) {
        final next = ss.map((s) => s.copy()).toList();
        applyMove(next, f, sl, t);
        while (_clearTriples(next) > 0) {}
        final rest = dfs(next, depth + 1);
        if (rest != null) return [f, sl * 10 + t, ...rest];
      }
      return null;
    }

    return dfs(start, 0);
  }

  (double, double, double, double) shelfRect(int s) {
    final rows = (shelves.length / cols).ceil();
    final w = 800 / cols, h = math.min(260.0, 1050 / rows);
    final c = s % cols, rr = s ~/ cols;
    return (100 + c * w + 10, 280 + rr * h, w - 20, h - 30);
  }

  (double, double) slotPos(int s, int k) {
    final (x, y, w, h) = shelfRect(s);
    return (x + w * (k + 0.5) / 3, y + h * 0.55);
  }

  @override
  void step(ArcadeInput i) {
    if (!(i.tap && i.hasPointer)) return;
    for (var s = 0; s < shelves.length; s++) {
      final (x, y, w, h) = shelfRect(s);
      if (i.x < x || i.x > x + w || i.y < y || i.y > y + h) continue;
      final k = ((i.x - x) / (w / 3)).floor().clamp(0, 2);
      if (selShelf >= 0) {
        if (s == selShelf) {
          selShelf = -1;
          return;
        }
        if (applyMove(shelves, selShelf, selSlot, s)) {
          moves++;
          lastEvent = 1;
          var c = 0;
          for (var n = _clearTriples(shelves); n > 0; n = _clearTriples(shelves)) {
            c += n;
          }
          if (c > 0) {
            cleared += c * 3;
            totalCleared += c * 3;
            combos += c > 1 ? 1 : 0;
            score += 60 * c;
            lastEvent = 2;
          }
          selShelf = -1;
          if (!meta.zen && moves >= moveLimit && !boardComplete) boardFailed();
          return;
        }
        // tapped another item instead: select it
      }
      if (shelves[s].front[k] >= 0) {
        selShelf = s;
        selSlot = k;
        lastEvent = 1;
      } else {
        selShelf = -1;
      }
      return;
    }
  }

  @override
  bool get boardComplete => shelves.every((s) => s.front.every((x) => x < 0) && s.back.isEmpty);

  @override
  double get boardProgress => items == 0 ? 1 : cleared / items;

  @override
  String get goalText => '$cleared/$items • ${moveLimit - moves}';

  @override
  bool useBooster() {
    if (over) return false;
    moveLimit += 5;
    return true;
  }

  @override
  Map<String, int> get stats => {
        'goods_cleared': totalCleared,
        'moves': moves,
        'combos': combos,
      };
}

// ---------------------------------------------------------------------------
// 099 Triple tile match.

class Tile {
  final double x, y;
  final int layer;
  int type = 0;
  bool gone = false;
  Tile(this.x, this.y, this.layer);
}

const double kTileW = 108, kTileH = 120;

class TileSim extends CasualSim {
  final List<Tile> tiles = [];
  final List<int> tray = [];
  int trayCap = 7;
  final List<int> order = [];
  int matched = 0, totalMatched = 0;
  TileSim(super.l) : super.base();

  int get types => (5 + rd).clamp(6, 14);

  @override
  void setupBoard() {
    final r = SeededRandom(boardSeed);
    final d = rd;
    tiles.clear();
    tray.clear();
    order.clear();
    matched = 0;
    trayCap = 7;
    final layers = (2 + d ~/ 2).clamp(2, 6);
    for (var l = 0; l < layers; l++) {
      final cols = 7 - (l.isOdd ? 1 : 0), rows = 8 - (l.isOdd ? 1 : 0);
      final ox = 120 + (l.isOdd ? kTileW / 2 : 0), oy = 280 + (l.isOdd ? kTileH / 2 : 0);
      for (var j = 0; j < rows; j++) {
        for (var i = 0; i < cols; i++) {
          if (r.chance(0.58 - l * 0.06)) tiles.add(Tile(ox + i * kTileW, oy + j * kTileH, l));
        }
      }
    }
    while (tiles.length % 3 != 0) {
      tiles.removeLast();
    }
    // random legal removal order, types assigned in triples along it
    final gone = List<bool>.filled(tiles.length, false);
    for (var n = 0; n < tiles.length; n += 3) {
      final t = r.nextInt(types);
      for (var m = 0; m < 3; m++) {
        final free = <int>[];
        for (var k = 0; k < tiles.length; k++) {
          if (!gone[k] && _freeWith(k, gone)) free.add(k);
        }
        final k = free[r.nextInt(free.length)];
        gone[k] = true;
        tiles[k].type = t;
        order.add(k);
      }
    }
  }

  bool _freeWith(int k, List<bool> gone) {
    final a = tiles[k];
    for (var o = 0; o < tiles.length; o++) {
      final b = tiles[o];
      if (gone[o] || b.layer <= a.layer) continue;
      if ((a.x - b.x).abs() < kTileW - 4 && (a.y - b.y).abs() < kTileH - 4) return false;
    }
    return true;
  }

  bool isFree(int k) {
    final a = tiles[k];
    if (a.gone) return false;
    for (final b in tiles) {
      if (b.gone || b.layer <= a.layer) continue;
      if ((a.x - b.x).abs() < kTileW - 4 && (a.y - b.y).abs() < kTileH - 4) return false;
    }
    return true;
  }

  void take(int k) {
    final t = tiles[k];
    t.gone = true;
    // insert next to the same type
    final at = tray.lastIndexOf(t.type);
    if (at >= 0) {
      tray.insert(at + 1, t.type);
    } else {
      tray.add(t.type);
    }
    lastEvent = 1;
    if (tray.where((x) => x == t.type).length >= 3) {
      for (var n = 0; n < 3; n++) {
        tray.remove(t.type);
      }
      matched += 3;
      totalMatched += 3;
      score += 90;
      lastEvent = 2;
    }
    if (tray.length >= trayCap && !boardComplete) boardFailed();
  }

  @override
  void step(ArcadeInput i) {
    if (!(i.tap && i.hasPointer)) return;
    // topmost tile under the finger
    var best = -1;
    for (var k = 0; k < tiles.length; k++) {
      final t = tiles[k];
      if (t.gone) continue;
      if (i.x >= t.x && i.x <= t.x + kTileW && i.y >= t.y && i.y <= t.y + kTileH) {
        if (best < 0 || t.layer > tiles[best].layer) best = k;
      }
    }
    if (best >= 0 && isFree(best)) take(best);
  }

  @override
  bool get boardComplete => tiles.every((t) => t.gone) && tray.isEmpty;

  @override
  double get boardProgress => tiles.isEmpty ? 1 : matched / tiles.length;

  @override
  String get goalText => '$matched/${tiles.length} • ${tray.length}/$trayCap';

  @override
  bool useBooster() {
    // Undo-to-board: returns the last three tray tiles.
    if (over || tray.isEmpty) return false;
    var n = 0;
    while (tray.isNotEmpty && n < 3) {
      final t = tray.removeLast();
      for (final k in order.reversed) {
        if (tiles[k].gone && tiles[k].type == t) {
          tiles[k].gone = false;
          break;
        }
      }
      n++;
    }
    return true;
  }

  @override
  Map<String, int> get stats => {
        'tiles_matched': totalMatched,
        'boards_cleared': board,
      };
}

// ---------------------------------------------------------------------------
// 100 Hexa sort: stack, merge and clear coloured hexagons.

class HexaSim extends CasualSim {
  int radius = 2;
  final Map<int, List<int>> cells = {}; // key q*100+r -> stack (bottom..top)
  final Set<int> blocked = {};
  final List<List<int>> offer = [[], [], []];
  int selected = 0, dealt = 0;
  int clearedTiles = 0, goal = 60, stacksCleared = 0, totalTiles = 0;
  HexaSim(super.l) : super.base();

  int get colors => (3 + rd ~/ 2).clamp(3, 7);

  static int key(int q, int r) => (q + 50) * 100 + (r + 50);
  static (int, int) unkey(int k) => (k ~/ 100 - 50, k % 100 - 50);

  (double, double) center(int q, int r) {
    const s = 82.0;
    return (500 + s * 1.5 * q, 780 + s * math.sqrt(3) * (r + q / 2));
  }

  @override
  void setupBoard() {
    final r = SeededRandom(boardSeed);
    final d = rd;
    radius = d <= 4 ? 2 : 3;
    cells.clear();
    blocked.clear();
    for (var q = -radius; q <= radius; q++) {
      for (var rr = math.max(-radius, -q - radius); rr <= math.min(radius, -q + radius); rr++) {
        cells[key(q, rr)] = [];
      }
    }
    if (radius == 3) {
      final ks = cells.keys.toList()..sort();
      for (var n = 0; n < d - 4; n++) {
        final k = ks[r.nextInt(ks.length)];
        if (k != key(0, 0)) blocked.add(k);
      }
    }
    dealt = 0;
    clearedTiles = 0;
    goal = 40 + d * 14;
    for (var o = 0; o < 3; o++) {
      offer[o] = _deal();
    }
    selected = 0;
  }

  List<int> _deal() {
    final r = SeededRandom(mixSeed([boardSeed, dealt++, 100]));
    final n = 2 + r.nextInt(4);
    final c1 = r.nextInt(colors);
    final out = <int>[];
    final split = r.chance(0.55) ? 1 + r.nextInt(n - 1) : n;
    final c2 = (c1 + 1 + r.nextInt(colors - 1)) % colors;
    for (var k = 0; k < n; k++) {
      out.add(k < split ? c1 : c2);
    }
    return out;
  }

  static List<int> neighbours(int k) {
    final (q, r) = unkey(k);
    return [key(q + 1, r), key(q - 1, r), key(q, r + 1), key(q, r - 1), key(q + 1, r - 1), key(q - 1, r + 1)];
  }

  static int topRun(List<int> s) {
    if (s.isEmpty) return 0;
    var n = 1;
    while (n < s.length && s[s.length - 1 - n] == s.last) {
      n++;
    }
    return n;
  }

  /// Merges around [start] until stable; clears runs of 10+. Returns tiles cleared.
  static int resolve(Map<int, List<int>> cells, int start) {
    var cleared = 0;
    final queue = <int>[start];
    var guard = 0;
    while (queue.isNotEmpty && guard++ < 200) {
      final c = queue.removeAt(0);
      final s = cells[c];
      if (s == null || s.isEmpty) continue;
      final col = s.last;
      for (final n in neighbours(c)) {
        final t = cells[n];
        if (t == null || t.isEmpty || t.last != col) continue;
        // move the neighbour's top run onto this stack
        final run = topRun(t);
        for (var k = 0; k < run; k++) {
          s.add(t.removeLast());
        }
        if (t.isNotEmpty) queue.add(n);
        queue.add(c);
      }
      if (topRun(s) >= 10) {
        final run = topRun(s);
        for (var k = 0; k < run; k++) {
          s.removeLast();
        }
        cleared += run;
        if (s.isNotEmpty) queue.add(c);
        for (final n in neighbours(c)) {
          if ((cells[n] ?? const []).isNotEmpty) queue.add(n);
        }
      }
    }
    return cleared;
  }

  bool place(int o, int k) {
    final cell = cells[k];
    if (cell == null || blocked.contains(k) || cell.isNotEmpty || offer[o].isEmpty) return false;
    cell.addAll(offer[o]);
    totalTiles += offer[o].length;
    offer[o] = _deal();
    final c = resolve(cells, k);
    if (c > 0) {
      clearedTiles += c;
      stacksCleared++;
      score += c * 15;
      lastEvent = 3;
    } else {
      lastEvent = 1;
    }
    if (_full()) boardFailed();
    return true;
  }

  bool _full() => cells.entries.every((e) => blocked.contains(e.key) || e.value.isNotEmpty);

  @override
  void step(ArcadeInput i) {
    if (!(i.tap && i.hasPointer)) return;
    // offer slots at the bottom
    for (var o = 0; o < 3; o++) {
      if ((i.x - (250 + o * 250)).abs() < 100 && i.y > 1380) {
        selected = o;
        lastEvent = 1;
        return;
      }
    }
    for (final k in cells.keys) {
      final (q, r) = unkey(k);
      final (cx, cy) = center(q, r);
      if ((i.x - cx) * (i.x - cx) + (i.y - cy) * (i.y - cy) < 70 * 70) {
        place(selected, k);
        return;
      }
    }
  }

  @override
  bool get boardComplete => meta.goal && clearedTiles >= goal;

  @override
  double get boardProgress => clearedTiles / goal;

  @override
  String get goalText => meta.goal ? '$clearedTiles/$goal' : '$clearedTiles';

  @override
  bool useBooster() {
    // Hammer: clears the tallest stack.
    if (over) return false;
    var best = -1, h = 0;
    for (final e in cells.entries) {
      if (e.value.length > h) {
        h = e.value.length;
        best = e.key;
      }
    }
    if (best < 0) return false;
    cells[best]!.clear();
    return true;
  }

  @override
  Map<String, int> get stats => {
        'hexes_cleared': clearedTiles,
        'stacks_cleared': stacksCleared,
        'hexes_placed': totalTiles,
      };
}

// ---------------------------------------------------------------------------
// Autopilot.

ArcadeInput casualBot(ArcadeSim sim) {
  final s = sim as CasualSim;
  if (s.wasDown) return const ArcadeInput(x: 0, y: 0);
  if (s.botWait > 0) {
    s.botWait--;
    return ArcadeInput.idle;
  }
  switch (s) {
    case MergeSim m:
      return _mergeBot(m);
    case ScrewSim c:
      return _screwBot(c);
    case GoodsSim g:
      return _goodsBot(g);
    case TileSim t:
      return _tileBot(t);
    case HexaSim h:
      return _hexaBot(h);
    default:
      return ArcadeInput.idle;
  }
}

ArcadeInput _tap(double x, double y) => ArcadeInput(down: true, tap: true, x: x.roundToDouble(), y: y.roundToDouble());

ArcadeInput _mergeBot(MergeSim m) {
  if (m.cooldown > 0 || m.aiming) return ArcadeInput.idle;
  final r = kFruitR[m.next];
  var best = 500.0, bv = -1e18;
  for (var k = 0; k <= 20; k++) {
    final x = kBoxL + r + (kBoxR - kBoxL - 2 * r) * k / 20;
    // surface fruit under this x
    Fruit? top;
    for (final f in m.fruits) {
      if ((f.x - x).abs() < f.r + r * 0.6 && (top == null || f.y - f.r < top.y - top.r)) top = f;
    }
    var v = 0.0;
    final surface = top == null ? kBoxB : top.y - top.r;
    v += surface * 0.02;
    if (top != null) {
      if (top.tier == m.next) v += 60;
      v -= (top.tier - m.next).abs() * 6;
      if (top.tier < m.next) v -= 10;
    }
    // keep big fruits toward the sides
    v -= (x - 500).abs() * 0.002 * m.next;
    if (v > bv) {
      bv = v;
      best = x;
    }
  }
  // press then release on the next tick (the stage drops on release)
  m.botWait = 18;
  return ArcadeInput(down: true, x: best.roundToDouble(), y: 500);
}

ArcadeInput _screwBot(ScrewSim s) {
  // follow the proven order, skipping screws already gone
  for (final k in s.order) {
    if (!s.screws[k].gone) {
      if (!s.isFree(k)) break;
      return _tap(s.screws[k].x, s.screws[k].y);
    }
  }
  // fallback: any free screw matching an active box, else any free screw
  int? any;
  for (var k = 0; k < s.screws.length; k++) {
    if (!s.isFree(k)) continue;
    any ??= k;
    if (s.screws[k].color == s.activeBox(0) || s.screws[k].color == s.activeBox(1)) {
      return _tap(s.screws[k].x, s.screws[k].y);
    }
  }
  if (any != null) return _tap(s.screws[any].x, s.screws[any].y);
  return ArcadeInput.idle;
}

ArcadeInput _goodsBot(GoodsSim g) {
  if (g.botPlan.length < 2) {
    final sol = GoodsSim.solveGoods(g.shelves.map((s) => s.copy()).toList(), 20000);
    if (sol == null || sol.isEmpty) return ArcadeInput.idle;
    g.botPlan
      ..clear()
      ..addAll(sol);
  }
  final from = g.botPlan[0], slot = g.botPlan[1] ~/ 10, to = g.botPlan[1] % 10;
  if (g.selShelf != from || g.selSlot != slot) {
    if (g.shelves[from].front[slot] < 0) {
      g.botPlan.clear();
      return ArcadeInput.idle;
    }
    final (x, y) = g.slotPos(from, slot);
    return _tap(x, y);
  }
  g.botPlan.removeRange(0, 2);
  final (x, y, w, h) = g.shelfRect(to);
  return _tap(x + w / 2, y + h / 2);
}

ArcadeInput _tileBot(TileSim t) {
  // 1) follow the proven removal order (triples come out together)
  for (final k in t.order) {
    if (!t.tiles[k].gone) {
      if (t.isFree(k)) return _tap(t.tiles[k].x + kTileW / 2, t.tiles[k].y + kTileH / 2);
      break;
    }
  }
  // 2) off the plan: complete a pair already in the tray, else any free tile
  for (var k = 0; k < t.tiles.length; k++) {
    if (t.isFree(k) && t.tray.where((x) => x == t.tiles[k].type).length == 2) {
      return _tap(t.tiles[k].x + kTileW / 2, t.tiles[k].y + kTileH / 2);
    }
  }
  for (var k = 0; k < t.tiles.length; k++) {
    if (t.isFree(k)) return _tap(t.tiles[k].x + kTileW / 2, t.tiles[k].y + kTileH / 2);
  }
  return ArcadeInput.idle;
}

ArcadeInput _hexaBot(HexaSim h) {
  // evaluate every (offer, cell) placement on a copy
  var bo = -1, bk = -1;
  var bv = -1e18;
  for (var o = 0; o < 3; o++) {
    if (h.offer[o].isEmpty) continue;
    for (final e in h.cells.entries) {
      if (h.blocked.contains(e.key) || e.value.isNotEmpty) continue;
      final copy = {for (final c in h.cells.entries) c.key: List.of(c.value)};
      copy[e.key]!.addAll(h.offer[o]);
      final cleared = HexaSim.resolve(copy, e.key);
      var empties = 0, chaos = 0;
      for (final c in copy.entries) {
        if (h.blocked.contains(c.key)) continue;
        if (c.value.isEmpty) {
          empties++;
          continue;
        }
        // mixed stacks are bad; neighbours sharing a top colour are good
        var changes = 0;
        for (var k = 1; k < c.value.length; k++) {
          if (c.value[k] != c.value[k - 1]) changes++;
        }
        chaos += changes;
        for (final n in HexaSim.neighbours(c.key)) {
          final t = copy[n];
          if (t != null && t.isNotEmpty && t.last == c.value.last) chaos -= 1;
        }
      }
      final v = cleared * 40.0 + empties * 6 - chaos * 3;
      if (v > bv) {
        bv = v;
        bo = o;
        bk = e.key;
      }
    }
  }
  if (bo < 0) return ArcadeInput.idle;
  if (h.selected != bo) return _tap(250 + bo * 250.0, 1450);
  final (q, r) = HexaSim.unkey(bk);
  final (x, y) = h.center(q, r);
  return _tap(x, y);
}
