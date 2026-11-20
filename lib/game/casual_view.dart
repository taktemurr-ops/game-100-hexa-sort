import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/arcade_stage.dart';
import '../app/play_kit.dart';
import '../app/services/audio.dart';
import '../core/arcade.dart';
import 'casual_engine.dart';

/// Bright, toy-like vector art for the casual puzzles.
Paint _p(int c) => Paint()..color = Color(c);

Paint _stroke(int c, double w) => Paint()
  ..color = Color(c)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round;

const _cols = [0xFFE63946, 0xFF457B9D, 0xFFFFB703, 0xFF2A9D8F, 0xFF9D4EDD, 0xFFF77F00, 0xFF06D6A0, 0xFFEF476F];
const _fruitCols = [0xFFD00000, 0xFFFF5D8F, 0xFF9D4EDD, 0xFFFFB703, 0xFFF77F00, 0xFFE63946, 0xFFFFD60A, 0xFFFFC8DD, 0xFFCAFFBF, 0xFF80ED99, 0xFF2D6A4F];
const _goodsIcons = ['🍎', '🥛', '🍪', '🧃', '🥕', '🧀', '🍞', '🍫', '🥚', '🍌', '🍇', '🥤'];
const _tileIcons = ['🌸', '🍀', '⭐', '🍄', '🐟', '🌙', '🔔', '💎', '🍒', '🎈', '🐚', '🌵', '🦋', '🍋'];

void _bg(Canvas c, int top, int bottom) {
  c.drawRect(
    const Rect.fromLTWH(0, 0, kWorldW, kWorldH),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(top), Color(bottom)],
      ).createShader(const Rect.fromLTWH(0, 0, kWorldW, kWorldH)),
  );
}

void paintCasual(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as CasualSim;
  switch (s) {
    case MergeSim m:
      _merge(c, m, t);
    case ScrewSim q:
      _screw(c, q);
    case GoodsSim g:
      _goods(c, g);
    case TileSim q:
      _tiles(c, q);
    case HexaSim h:
      _hexa(c, h);
    default:
      break;
  }
  if (s.flashTicks > 0) {
    paintText(c, s.flash, const Offset(500, 160), 80, Colors.white.withValues(alpha: (s.flashTicks / 60).clamp(0.0, 1.0)));
  }
}

// merge --------------------------------------------------------------------------
void _fruit(Canvas c, double x, double y, int tier) {
  final r = kFruitR[tier];
  final col = Color(_fruitCols[tier % _fruitCols.length]);
  c.drawCircle(Offset(x + r * 0.08, y + r * 0.12), r, _p(0x33000000));
  c.drawCircle(Offset(x, y), r, Paint()..color = col);
  c.drawCircle(Offset(x - r * 0.35, y - r * 0.35), r * 0.25, _p(0x66FFFFFF));
  c.drawLine(Offset(x, y - r), Offset(x + r * 0.15, y - r - r * 0.3), _stroke(0xFF6B4226, math.max(3, r * 0.08)));
  // face
  c.drawCircle(Offset(x - r * 0.25, y), r * 0.07, _p(0xFF222222));
  c.drawCircle(Offset(x + r * 0.25, y), r * 0.07, _p(0xFF222222));
  c.drawArc(Rect.fromCenter(center: Offset(x, y + r * 0.15), width: r * 0.4, height: r * 0.25), 0.2, 2.7, false, _stroke(0xFF222222, math.max(2, r * 0.04)));
}

void _merge(Canvas c, MergeSim m, double t) {
  _bg(c, 0xFFFFF3B0, 0xFFFFD6A5);
  const box = Rect.fromLTRB(kBoxL, kBoxT, kBoxR, kBoxB);
  c.drawRRect(RRect.fromRectAndRadius(box.inflate(16), const Radius.circular(24)), _p(0xFFB08968));
  c.drawRect(box, _p(0xFFFFF8E7));
  final danger = m.danger > 0 && (t * 6).floor().isEven;
  c.drawLine(const Offset(kBoxL, kDangerY), const Offset(kBoxR, kDangerY), _stroke(danger ? 0xFFE63946 : 0x55E63946, 5));
  for (final f in m.fruits) {
    _fruit(c, f.x, f.y, f.tier);
  }
  // aim line and next fruit
  final r = kFruitR[m.next];
  final x = clampD(m.aimX, kBoxL + r, kBoxR - r);
  if (m.cooldown == 0) {
    for (var y = kBoxT + 20; y < kBoxB; y += 40) {
      c.drawLine(Offset(x, y), Offset(x, y + 18), _stroke(0x44000000, 3));
    }
  }
  _fruit(c, x, kBoxT - 50, m.next);
  paintText(c, 'NEXT', const Offset(880, 210), 30, Colors.black54);
  _fruit(c, 880, 270, m.after);
  // evolution ring
  for (var k = 0; k < kFruitR.length; k++) {
    final a = k / kFruitR.length * 2 * math.pi - math.pi / 2;
    final o = Offset(120 + math.cos(a) * 70, 230 + math.sin(a) * 70);
    c.drawCircle(o, k <= m.bestTier ? 13 : 9, Paint()..color = Color(_fruitCols[k % _fruitCols.length]).withValues(alpha: k <= m.bestTier ? 1 : 0.3));
    if (k == m.targetTier && m.meta.goal) c.drawCircle(o, 18, _stroke(0xFF000000, 3));
  }
}

// screw --------------------------------------------------------------------------
void _screw(Canvas c, ScrewSim s) {
  _bg(c, 0xFFCAF0F8, 0xFF90E0EF);
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(80, 300, 840, 840), const Radius.circular(30)), _p(0xFFADB5BD));
  for (final pl in s.plates) {
    if (pl.fallen && pl.fall >= 1) continue;
    final dy = pl.fall * 900;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(pl.x, pl.y + dy, pl.w, pl.h), const Radius.circular(22));
    c.drawRRect(r.shift(const Offset(6, 10)), _p(0x33000000));
    c.drawRRect(r, Paint()..color = Color(_cols[pl.color % _cols.length]).withValues(alpha: 0.85));
    c.drawRRect(r, _stroke(0x55FFFFFF, 4));
  }
  for (var k = 0; k < s.screws.length; k++) {
    final sc = s.screws[k];
    if (sc.gone) continue;
    final free = s.isFree(k);
    final o = Offset(sc.x, sc.y);
    c.drawCircle(o, 24, _p(0xFF343A40));
    c.drawCircle(o, 19, Paint()..color = Color(_cols[sc.color % _cols.length]).withValues(alpha: free ? 1 : 0.45));
    c.drawLine(o.translate(-10, -10), o.translate(10, 10), _stroke(0xAA000000, 4));
    c.drawLine(o.translate(-10, 10), o.translate(10, -10), _stroke(0xAA000000, 4));
  }
  // boxes and parking tray
  for (var b = 0; b < 2; b++) {
    final col = s.activeBox(b);
    final rect = Rect.fromLTWH(160 + b * 380, 1180, 300, 120);
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)), _p(col < 0 ? 0x33000000 : _cols[col % _cols.length]));
    for (var k = 0; k < 3; k++) {
      c.drawCircle(Offset(rect.left + 60 + k * 90, rect.center.dy), 24, _p(k < s.boxFill[b] ? 0xFFFFFFFF : 0x55000000));
    }
  }
  for (var k = 0; k < s.bufferCap; k++) {
    final o = Offset(500 + (k - (s.bufferCap - 1) / 2) * 100, 1420);
    c.drawCircle(o, 34, _p(0x55000000));
    if (k < s.buffer.length) c.drawCircle(o, 24, _p(_cols[s.buffer[k] % _cols.length]));
  }
}

// goods --------------------------------------------------------------------------
void _goods(Canvas c, GoodsSim g) {
  _bg(c, 0xFFFFE5D9, 0xFFFFCAD4);
  for (var s = 0; s < g.shelves.length; s++) {
    final (x, y, w, h) = g.shelfRect(s);
    final sh = g.shelves[s];
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(16)), _p(0xFFB08968));
    c.drawRect(Rect.fromLTWH(x + 8, y + h - 24, w - 16, 16), _p(0xFF7F5539));
    // hint of the layer behind
    if (sh.back.isNotEmpty) {
      for (var k = 0; k < 3; k++) {
        final it = sh.back.last[k];
        if (it < 0) continue;
        paintText(c, _goodsIcons[it % _goodsIcons.length], Offset(x + w * (k + 0.5) / 3 + 10, y + h * 0.4), 44,
            Colors.black.withValues(alpha: 0.25));
      }
    }
    for (var k = 0; k < 3; k++) {
      final it = sh.front[k];
      if (it < 0) continue;
      final (px, py) = g.slotPos(s, k);
      final sel = g.selShelf == s && g.selSlot == k;
      if (sel) c.drawCircle(Offset(px, py - 10), 52, _p(0x88FFFFFF));
      paintText(c, _goodsIcons[it % _goodsIcons.length], Offset(px, py - (sel ? 22 : 0)), 64, Colors.black);
    }
  }
}

// tiles --------------------------------------------------------------------------
void _tiles(Canvas c, TileSim s) {
  _bg(c, 0xFFD8F3DC, 0xFF95D5B2);
  final order = List.generate(s.tiles.length, (k) => k)..sort((a, b) => s.tiles[a].layer.compareTo(s.tiles[b].layer));
  for (final k in order) {
    final t = s.tiles[k];
    if (t.gone) continue;
    final free = s.isFree(k);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(t.x + 3, t.y + 3, kTileW - 6, kTileH - 6), const Radius.circular(16));
    c.drawRRect(r.shift(const Offset(5, 9)), _p(0x55000000));
    c.drawRRect(r, _p(0xFFFFFCF2));
    c.drawRRect(r, _stroke(0xFF2D6A4F, 3));
    paintText(c, _tileIcons[t.type % _tileIcons.length], Offset(t.x + kTileW / 2, t.y + kTileH / 2), 54, Colors.black);
    if (!free) c.drawRRect(r, _p(0x77000000));
  }
  // tray
  final tray = RRect.fromRectAndRadius(Rect.fromLTWH(500 - s.trayCap * 58, 1300, s.trayCap * 116.0, 150), const Radius.circular(24));
  c.drawRRect(tray, _p(0xFF6B4226));
  for (var k = 0; k < s.trayCap; k++) {
    final x = 500 - s.trayCap * 58 + 8 + k * 116.0;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 1316, 100, 118), const Radius.circular(14)), _p(0x33FFFFFF));
    if (k < s.tray.length) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 1316, 100, 118), const Radius.circular(14)), _p(0xFFFFFCF2));
      paintText(c, _tileIcons[s.tray[k] % _tileIcons.length], Offset(x + 50, 1375), 50, Colors.black);
    }
  }
}

// hexa ---------------------------------------------------------------------------
Path _hex(Offset o, double r) {
  final p = Path();
  for (var k = 0; k < 6; k++) {
    final a = k * math.pi / 3;
    final v = o.translate(math.cos(a) * r, math.sin(a) * r);
    if (k == 0) {
      p.moveTo(v.dx, v.dy);
    } else {
      p.lineTo(v.dx, v.dy);
    }
  }
  return p..close();
}

void _stack(Canvas c, Offset o, List<int> st, double r) {
  for (var k = 0; k < st.length; k++) {
    final y = o.dy - k * 9;
    final path = _hex(Offset(o.dx, y), r);
    c.drawPath(path, _p(_cols[st[k] % _cols.length]));
    c.drawPath(path, _stroke(0x55000000, 2));
  }
  if (st.isNotEmpty) paintText(c, '${HexaSim.topRun(st)}', Offset(o.dx, o.dy - (st.length - 1) * 9), 26, Colors.white);
}

void _hexa(Canvas c, HexaSim h) {
  _bg(c, 0xFF22223B, 0xFF4A4E69);
  final keys = h.cells.keys.toList()..sort((a, b) => HexaSim.unkey(a).$2.compareTo(HexaSim.unkey(b).$2));
  for (final k in keys) {
    final (q, r) = HexaSim.unkey(k);
    final (x, y) = h.center(q, r);
    final path = _hex(Offset(x, y), 78);
    c.drawPath(path, _p(h.blocked.contains(k) ? 0xFF111111 : 0xFF9A8C98));
    c.drawPath(path, _stroke(0x55FFFFFF, 3));
  }
  for (final k in keys) {
    final (q, r) = HexaSim.unkey(k);
    final (x, y) = h.center(q, r);
    _stack(c, Offset(x, y), h.cells[k]!, 66);
  }
  for (var o = 0; o < 3; o++) {
    final center = Offset(250 + o * 250.0, 1470);
    if (o == h.selected) c.drawCircle(center.translate(0, -20), 95, _p(0x55FFFFFF));
    _stack(c, center, h.offer[o], 56);
  }
}

Sfx? casualSound(ArcadeSim sim) => switch ((sim as CasualSim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.place,
      3 => Sfx.combo,
      4 => Sfx.error,
      5 => Sfx.clear,
      _ => null,
    };
