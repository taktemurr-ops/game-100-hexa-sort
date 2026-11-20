import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/daily.dart';
import '../../core/level_plan.dart';
import '../../core/missions.dart';
import '../app_state.dart';
import '../widgets.dart';
import 'home.dart';
import 'play.dart';

/// Daily login, wheel, surprise, daily/weekly levels, missions, records.
class DailyScreen extends ConsumerWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final s = app.save;
    final now = app.session.now();
    final d = app.session.daily;
    final today = app.dayKey();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Login calendar ----
        SectionTitle(app.t('daily_login')),
        Text(app.t('streak', {'n': s.loginStreak})),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: DailySystems.loginCycle.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (c, i) {
              final cyclePos = (s.loginStreak - 1) % DailySystems.loginCycle.length;
              final isToday = i == cyclePos;
              final r = DailySystems.loginCycle[i];
              return Container(
                width: 72,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isToday
                      ? Theme.of(c).colorScheme.primaryContainer
                      : Theme.of(c).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday ? Border.all(color: Theme.of(c).colorScheme.primary, width: 2) : null,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(app.t('day_n', {'n': i + 1}), style: const TextStyle(fontSize: 12)),
                  Icon(r.gems > 0 ? Icons.diamond : Icons.monetization_on,
                      color: r.gems > 0 ? Colors.cyan : Colors.amber),
                  Text('${r.coins}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: d.loginRewardAvailable(s, now)
              ? () {
                  final r = app.claimLogin();
                  if (r != null) _rewardDialog(context, app, r);
                }
              : null,
          child: Text(d.loginRewardAvailable(s, now) ? app.t('claim') : app.t('claimed')),
        ),

        // ---- Wheel & surprise ----
        SectionTitle(app.t('wheel')),
        _Wheel(app: app),
        SectionTitle(app.t('surprise')),
        ListTile(
          leading: const Icon(Icons.card_giftcard, color: Colors.purple),
          title: Text(app.t('surprise')),
          subtitle: Text(s.lastSurpriseDay == today ? app.t('claimed') : app.t('surprise_hint')),
          trailing: FilledButton(
            onPressed: d.surpriseAvailable(s, now)
                ? () {
                    final r = app.claimSurprise();
                    if (r != null) _rewardDialog(context, app, r);
                  }
                : null,
            child: Text(app.t('claim')),
          ),
        ),

        // ---- Special levels ----
        SectionTitle(app.t('mode_daily')),
        Card(
          child: ListTile(
            leading: const Icon(Icons.today),
            title: Text(app.t('mode_daily')),
            subtitle: Text(app.t('mode_daily_d')),
            trailing: s.dailyLevelDoneDay == today
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.play_arrow),
            onTap: () => openMode(context, app, GameModeId.daily),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.date_range),
            title: Text(app.t('mode_weekly')),
            subtitle: Text(app.t('mode_weekly_d')),
            trailing: s.weeklyLevelDoneWeek == s.weeklyKey
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.play_arrow),
            onTap: () => openMode(context, app, GameModeId.weekly),
          ),
        ),
        Text(app.t('daily_record', {'n': s.dailyRecordDay == today ? s.dailyRecord : 0})),
        Text(app.t('weekly_goal', {'a': d.weeklyGoalProgress(s), 'b': d.weeklyGoal(s)})),
        LinearProgressIndicator(
          value: (d.weeklyGoalProgress(s) / d.weeklyGoal(s)).clamp(0.0, 1.0),
        ),

        // ---- Missions ----
        SectionTitle(app.t('daily_missions')),
        for (final m in app.session.dailyMissions) _MissionTile(app: app, m: m),
        SectionTitle(app.t('weekly_missions')),
        for (final m in app.session.weeklyMissions) _MissionTile(app: app, m: m),
      ],
    );
  }
}

void _rewardDialog(BuildContext context, AppState app, Reward r) {
  showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(app.t('reward')),
      content: RewardChips(reward: r),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(app.t('ok')))],
    ),
  );
}

String missionTitle(AppState app, Mission m) {
  final id = m.id.substring(2);
  final key = 'mission_$id';
  final text = app.t(key, {'n': m.target});
  if (text != key) return text;
  return achievementTitle(app, 'mission_stat', {'stat': m.statKey, 'n': '${m.target}'}, m.id);
}

class _MissionTile extends StatelessWidget {
  final AppState app;
  final Mission m;
  const _MissionTile({required this.app, required this.m});

  @override
  Widget build(BuildContext context) {
    final p = m.progress(app.save).clamp(0, m.target);
    final claimed = m.claimed(app.save);
    return Card(
      child: ListTile(
        title: Text(missionTitle(app, m)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p / m.target),
          const SizedBox(height: 4),
          Text('$p / ${m.target}   +${m.coins} 🪙${m.gems > 0 ? '  +${m.gems} 💎' : ''}'),
        ]),
        trailing: claimed
            ? const Icon(Icons.check_circle, color: Colors.green)
            : FilledButton(
                onPressed: m.done(app.save)
                    ? () {
                        final r = app.session.claimMission(m);
                        if (r != null) {
                          app.changed(saveNow: true);
                          _rewardDialog(context, app, r);
                        }
                      }
                    : null,
                child: Text(app.t('claim')),
              ),
      ),
    );
  }
}

class _Wheel extends StatefulWidget {
  final AppState app;
  const _Wheel({required this.app});

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  double _target = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    final app = widget.app;
    final idx = app.session.daily.wheelResult(app.save, app.session.now());
    final n = DailySystems.wheelSlices.length;
    final slice = 2 * math.pi / n;
    _target = 6 * math.pi + (n - idx) * slice - slice / 2;
    if (app.save.reducedMotion) {
      _c.value = 1;
    } else {
      await _c.forward(from: 0);
    }
    final r = app.spinWheel();
    if (r != null && mounted) _rewardDialog(context, app, r);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final available = app.session.daily.wheelAvailable(app.save, app.session.now());
    return Column(children: [
      SizedBox(
        width: 220,
        height: 220,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.rotate(
              angle: Curves.easeOutCubic.transform(_c.value) * _target,
              child: CustomPaint(size: const Size(220, 220), painter: _WheelPainter()),
            ),
          ),
          const Positioned(top: 0, child: Icon(Icons.arrow_drop_down, size: 40)),
        ]),
      ),
      FilledButton(
        onPressed: available && !_c.isAnimating ? _spin : null,
        child: Text(available ? app.t('spin') : app.t('come_back_tomorrow')),
      ),
    ]);
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final n = DailySystems.wheelSlices.length;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    final sweep = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      final paint = Paint()..color = HSLColor.fromAHSL(1, i * 360 / n, 0.7, 0.55).toColor();
      canvas.drawArc(rect, -math.pi / 2 + i * sweep, sweep, true, paint);
      final reward = DailySystems.wheelSlices[i];
      final label = reward.coins > 0
          ? '${reward.coins}'
          : reward.gems > 0
              ? '💎${reward.gems}'
              : reward.hints > 0
                  ? '💡${reward.hints}'
                  : '⚡${reward.boosters}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      final a = -math.pi / 2 + (i + 0.5) * sweep;
      final pos = c + Offset(math.cos(a), math.sin(a)) * r * 0.65;
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(c, 18, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => false;
}
