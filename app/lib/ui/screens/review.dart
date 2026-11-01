// 내 하루 보기: 1일차 기록을 보여 주고, 바꾸고 싶은 시각만 고친 뒤 다음 날 일정을 만든다.
// 웹 버전 src/ui/screens/Review.tsx와 같은 흐름이다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/derive.dart';
import '../../app/state.dart';
import '../../core/model/models.dart';
import '../kit.dart';
import '../preview.dart';
import '../scope.dart';
import '../theme.dart';

class _HabitRow {
  _HabitRow({required this.title, required this.include, required this.recorded, required this.start, required this.minutes});
  final String title;
  bool include;
  final Span? recorded;
  int start;
  int minutes;
}

int _clamp(int v, int lo, int hi) => math.max(lo, math.min(hi, v));
int _round5(num m) => (m / 5).round() * 5;

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final String _day1;
  late final ObservedDay _obs;
  late int _actualWake;
  late int _wake;
  late int _sleepMinutes;
  late final List<_HabitRow> _rows;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final store = context.store;
    final s = store.state;
    final o = s.observation;
    if (o == null) return;
    _ready = true;
    _day1 = o.day1;
    _obs = observedDay(s, _day1, store.now());
    final obs = _obs;
    _actualWake = obs.wakeAt != null
        ? roundedClock(obs.wakeAt!)
        : obs.firstLogAt != null
            ? _round5(roundedClock(obs.firstLogAt!) - 30)
            : 7 * 60 + 30;
    // 처음 접속할 때 고른 목표가 있으면 그 시각을 앞으로의 기상으로 둔다.
    final intent = s.intent;
    bool wants(GoalFocus f) => intent?.focus.contains(f) ?? false;
    _wake = wants(GoalFocus.wake) ? intent!.wake : _actualWake;
    if (wants(GoalFocus.sleep)) {
      _sleepMinutes = intent!.sleepMinutes;
    } else {
      final morning = s.logs.where((l) => l.activity == Activity.sleep && l.end != null && obs.wakeAt != null && l.end == obs.wakeAt).firstOrNull;
      final mins = morning != null ? diffMin(morning.end!, morning.start) : 420;
      _sleepMinutes = (_clamp((mins / 60 * 2).round(), 10, 20) * 30);
    }
    _HabitRow meal(String slot) {
      final r = obs.meals[slot];
      final def = defaultGoals.meals.firstWhere((m) => m.title == slot);
      return r != null
          ? _HabitRow(title: slot, include: true, recorded: r, start: roundedClock(r.start), minutes: _clamp(_round5(r.minutes), 15, 90))
          : _HabitRow(title: slot, include: slot == '아침 식사' && wants(GoalFocus.breakfast), recorded: null, start: def.start.minutes, minutes: def.minutes);
    }

    final ex = obs.exercise;
    _rows = [
      for (final slot in mealSlots) meal(slot),
      ex != null
          ? _HabitRow(title: '운동', include: true, recorded: ex, start: roundedClock(ex.start), minutes: _clamp(_round5(ex.minutes), 10, 120))
          : _HabitRow(title: '운동', include: wants(GoalFocus.exercise), recorded: null, start: 20 * 60 + 30, minutes: intent?.exerciseMinutes ?? 30),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return ScreenList(tab: false, children: [TopBar(title: '내 하루 보기', onBack: context.ui.actions.back), const DsBanner('관찰 기록이 없어요.')]);
    }
    final c = context.ds;
    final s = context.app;
    final now = context.ui.now;
    final obs = _obs;
    final todayKey = dateKey(now);
    final isToday = _day1 == todayKey;
    final day2 = dateKey(addDays(fromKey(_day1), 1));
    final fromToday = todayKey.compareTo(day2) >= 0;

    final focusStart = obs.work != null ? roundedClock(obs.work!.start) : s.settings.focusStart.minutes;
    final gap = (_actualWake - _wake).abs();
    final firstAlarm = gap > 30 ? _actualWake : _wake;
    final weeks = (gap / 30).ceil();
    final bed = firstAlarm - _sleepMinutes - s.settings.sleepLatencyMinutes;

    void submit() {
      HabitSlot slot(_HabitRow r) => HabitSlot(title: r.title, activity: r.title == '운동' ? Activity.exercise : Activity.meal, start: ClockTime(r.start), minutes: r.minutes);
      final goals = HabitGoals(
        wake: ClockTime(_wake),
        sleepMinutes: _sleepMinutes,
        meals: [for (final r in _rows) if (r.include && r.title != '운동') slot(r)],
        exercise: _rows[3].include ? slot(_rows[3]) : null,
      );
      final store = context.store;
      store.completeObservation(
        goals: goals,
        settings: obs.work != null ? s.settings.copyWith(focusStart: ClockTime(focusStart), focusEnd: ClockTime(focusStart + 180)) : s.settings,
        recordedWake: _actualWake,
      );
      context.ui.actions.back();
      context.toast('일정을 만들었어요. 설정에서 언제든 바꿀 수 있어요');
    }

    return ScreenList(tab: false, children: [
      TopBar(
        title: isToday ? '오늘 이렇게 지냈어요' : '어제 이렇게 지냈어요',
        sub: '${koreanDate(fromKey(_day1))} · 바꾸고 싶은 시각만 고치세요',
        onBack: context.ui.actions.back,
      ),
      if (obs.logCount < 3) const DsBanner('기록이 적어요. 기록하지 않은 습관은 기본 시각으로 넣거나 빼 주세요.'),
      Semantics(
        label: '기상과 수면',
        container: true,
        child: DsCard(gap: 14, children: [
          const DsTitle('기상과 수면'),
          _CompareRow(
            label: '일어난 시각',
            recorded: obs.wakeAt != null ? '기록 ${formatHm(obs.wakeAt!)}' : '기록 없음',
            value: _actualWake,
            onChanged: (v) => setState(() {
              if (_wake == _actualWake) _wake = v;
              _actualWake = v;
            }),
            hint: obs.wakeAt != null ? null : '몇 시에 일어났는지 알려 주세요',
          ),
          _CompareRow(label: '앞으로 일어날 시각', value: _wake, onChanged: (v) => setState(() => _wake = v), changed: _wake != _actualWake),
          HoursField(label: '수면 시간', minutes: _sleepMinutes, onChanged: (v) => setState(() => _sleepMinutes = v)),
          if (gap > 30) richBody(context, '$gap분 차이는 한 번에 바꾸지 않고 **$weeks주**에 걸쳐 매주 30분씩 옮겨요. 내일 알람은 ${formatClock(firstAlarm)}이에요.'),
        ]),
      ),
      Semantics(
        label: '식사와 운동',
        container: true,
        child: DsCard(gap: 14, children: [
          const DsTitle('식사와 운동'),
          for (var i = 0; i < _rows.length; i++) _habit(context, i),
        ]),
      ),
      if (obs.work != null)
        Semantics(
          label: '업무',
          container: true,
          child: DsCard(children: [
            Row(children: [
              Expanded(child: Text('업무', style: DsText.body.copyWith(fontWeight: FontWeight.w600, color: c.ink))),
              Text('${formatHm(obs.work!.start)}–${formatHm(obs.work!.end)} · ${formatDuration(obs.work!.minutes)}',
                  style: DsText.body.copyWith(color: c.ink, fontFeatures: DsText.num)),
            ]),
            LabelText('집중이 필요한 할 일은 업무를 시작하는 ${formatClock(focusStart)}부터 3시간 안에 먼저 넣어요.'),
          ]),
        ),
      Semantics(
        label: '다음 날',
        container: true,
        child: DsCard(tint: true, children: [
          LabelText('${fromToday ? '오늘' : '내일'}부터'),
          _kv(context, '기상 알람', formatClock(firstAlarm)),
          if (!fromToday) _kv(context, '오늘 밤 취침', formatHm(addMin(fromKey(day2), bed))),
          const LabelText('식사·운동은 위 시각으로, 할 일은 빈 시간에 자동으로 넣어요. 설정에서 언제든 바꿀 수 있어요.'),
          DsButton.primary(fromToday ? '이대로 오늘 일정 만들기' : '이대로 내일 일정 만들기', block: true, onPressed: submit),
        ]),
      ),
    ]);
  }

  Widget _kv(BuildContext context, String k, String v) {
    final c = context.ds;
    return Row(children: [
      Expanded(child: Text(k, style: DsText.body.copyWith(color: c.ink))),
      Text(v, style: DsText.body.copyWith(fontWeight: FontWeight.w600, color: c.ink, fontFeatures: DsText.num)),
    ]);
  }

  Widget _habit(BuildContext context, int i) {
    final c = context.ds;
    final r = _rows[i];
    final rec = r.recorded;
    final changed = r.include && rec != null && r.start != roundedClock(rec.start);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      DsSwitch(value: r.include, onChanged: (v) => setState(() => r.include = v), label: r.title, onText: '일정에 넣기', offText: '빼기'),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: rec != null ? '기록 ${formatHm(rec.start)} · ${formatDuration(math.max(5, _round5(rec.minutes)))}' : '기록 없음'),
          if (!r.include) const TextSpan(text: ' · 일정에서 빼요'),
          if (changed) TextSpan(text: ' · 바뀜', style: TextStyle(color: c.accentStrong, fontWeight: FontWeight.w600)),
        ]),
        style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num),
      ),
      if (r.include) ...[
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: ClockBox(value: r.start, semanticLabel: '${r.title} 시각', onChanged: (v) => setState(() => r.start = v))),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: _MinutesBox(value: r.minutes, label: r.title, onChanged: (v) => setState(() => r.minutes = v)),
          ),
        ]),
      ],
      if (i < _rows.length - 1) ...[const SizedBox(height: 12), Divider(height: 1, thickness: 1, color: c.line)],
    ]);
  }
}

/// 분 단위 길이(5분씩). 이름표 없이 '− 30분 +'.
class _MinutesBox extends StatelessWidget {
  const _MinutesBox({required this.value, required this.label, required this.onChanged});
  final int value;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    void set(int v) => onChanged(_clamp(v, 5, 180));
    return Container(
      height: 44,
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        DsIconButton(DsIcons.minus, onPressed: value > 5 ? () => set(value - 5) : null, label: '$label 5분 줄이기', size: 40, iconSize: 18),
        Expanded(
          child: Semantics(
            label: '$label 시간 $value분',
            child: Center(child: Text('$value분', style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num))),
          ),
        ),
        DsIconButton(DsIcons.plus, onPressed: value < 180 ? () => set(value + 5) : null, label: '$label 5분 늘리기', size: 40, iconSize: 18),
      ]),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.label, this.recorded, required this.value, required this.onChanged, this.changed = false, this.hint});
  final String label;
  final String? recorded;
  final int value;
  final ValueChanged<int> onChanged;
  final bool changed;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: label),
          if (recorded != null) TextSpan(text: ' · $recorded', style: DsText.label.copyWith(color: c.muted)),
          if (changed) TextSpan(text: ' · 바뀜', style: TextStyle(color: c.accentStrong, fontWeight: FontWeight.w600)),
        ]),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted),
      ),
      const SizedBox(height: 6),
      ClockBox(value: value, onChanged: onChanged, semanticLabel: label),
      if (hint != null) ...[const SizedBox(height: 6), LabelText(hint!)],
    ]);
  }
}
