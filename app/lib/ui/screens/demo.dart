// 일정 자동 생성 시연: 엔진이 내일 일정을 짜는 과정을 단계별로 보여 준다. 저장된 기록은 건드리지 않는다.
// 웹 버전 src/ui/screens/Demo.tsx와 같은 화면.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/derive.dart';
import '../../app/state.dart';
import '../../core/engine/coaching.dart';
import '../../core/engine/schedule_builder.dart';
import '../../core/model/models.dart';
import '../add_event.dart' show ImpactLine;
import '../day_ring.dart';
import '../kit.dart';
import '../scope.dart';
import '../theme.dart';

enum _Scenario {
  normal('평소 하루', '목표 습관과 할 일 3개로 내일 일정을 짜요'),
  meeting('아침 8시 회의', '이른 회의가 생기면 기상 알람을 당겨요'),
  lunch('점심 약속', '겹치는 습관은 뒤로 밀어요'),
  overload('할 일 폭탄', '빈 시간의 75%까지만 넣고 나머지는 넘겨요'),
  tired('5시간 40분 잔 날', '적게 잔 날은 코칭이 운동과 집중 작업을 줄여요');

  const _Scenario(this.label, this.desc);
  final String label;
  final String desc;
}

class _Step {
  const _Step({required this.title, required this.value, required this.lines, required this.blocks, this.nightSleep = false});
  final String title;
  final String value;
  final List<String> lines;

  /// 이 단계에서 링에 새로 나타나는 블록.
  final List<ScheduleBlock> blocks;
  final bool nightSleep;
}

class _Built {
  const _Built({required this.base, required this.plan, required this.changes, required this.steps, required this.day});
  final DayPlan base;
  final DayPlan plan;
  final List<PlanDiff> changes;
  final List<_Step> steps;
  final DateTime day;
}

List<TaskItem> _demoTasks(DateTime day, bool overload) {
  DateTime at(int plus, int h) => DateTime(day.year, day.month, day.day + plus, h);
  final base = [
    TaskItem(id: 'd-report', title: '분기 보고서', estMinutes: 180, dueAt: at(2, 18), type: TaskType.work, priority: TaskPriority.high, focus: true),
    TaskItem(id: 'd-english', title: '영어 숙제', estMinutes: 60, dueAt: at(1, 23), type: TaskType.homework),
    TaskItem(id: 'd-call', title: '치과 예약 전화', estMinutes: 10, dueAt: at(0, 18), type: TaskType.personal),
  ];
  if (!overload) return base;
  return [
    ...base,
    TaskItem(id: 'd-proposal', title: '제안서 마감', estMinutes: 300, dueAt: at(0, 23), type: TaskType.work, priority: TaskPriority.high, focus: true),
    TaskItem(id: 'd-slides', title: '발표 자료', estMinutes: 240, dueAt: at(1, 18), type: TaskType.work),
  ];
}

List<FixedEvent> _demoEvents(DateTime day, _Scenario id) {
  DateTime at(int h, [int m = 0]) => DateTime(day.year, day.month, day.day, h, m);
  return switch (id) {
    _Scenario.meeting => [FixedEvent(id: 'd-ev1', title: '팀 회의', start: at(8), end: at(9))],
    _Scenario.lunch => [FixedEvent(id: 'd-ev2', title: '점심 미팅', start: at(11, 30), end: at(13))],
    _ => const [],
  };
}

_Built _build(AppState s, _Scenario id, DateTime now) {
  final day = addDays(dayStart(now), 1);
  final useMine = s.onboarded && s.observation?.phase != ObservationPhase.recording;
  final goals = useMine ? effectiveGoals(s, dateKey(day)) : defaultGoals;
  final settings = s.settings.copyWith(travelMinutes: s.settings.travelMinutes != 0 ? s.settings.travelMinutes : 40);
  DayPlan run(List<FixedEvent> events, bool overload) =>
      const ScheduleBuilder().buildDay(DayPlanInput(date: day, goals: goals, settings: settings, fixedEvents: events, tasks: _demoTasks(day, overload)));
  final base = run(const [], false);
  var plan = run(_demoEvents(day, id), id == _Scenario.overload);
  final changes = id == _Scenario.normal ? <PlanDiff>[] : comparePlans(base, plan);

  List<String>? coachLines;
  if (id == _Scenario.tired) {
    final sg = CoachingEngine().evaluate(const WakeLogged(sleepMinutes: 340), today: plan.blocks, now: plan.wake).firstOrNull;
    if (sg != null) {
      final applied = applyChanges(plan.blocks, sg.changes);
      plan = plan.copyWith(blocks: applied.blocks);
      final ex = applied.blocks.where((b) => b.adjusted).firstOrNull;
      final baseEx = base.blocks.where((b) => b.activity == Activity.exercise).firstOrNull ?? ex;
      coachLines = [
        sg.message,
        if (ex != null) '운동 ${formatDuration(baseEx!.minutes)} → ${formatDuration(ex.minutes)}',
        if (applied.deferred.isNotEmpty) '집중 작업 ${applied.deferred.length}개는 다음 날로',
      ];
      changes.addAll(coachLines.skip(1).map((t) => PlanDiff(PlanDiffKind.moved, t)));
    }
  }

  // 단계별로 나누기
  final blocks = plan.blocks;
  final sleep = blocks.first;
  final fixed = blocks.where((b) => b.kind == BlockKind.fixed).toList();
  final habits = blocks.where((b) => b.kind == BlockKind.habit && b.activity != Activity.sleep).toList();
  final tasks = blocks.where((b) => b.kind == BlockKind.task).toList();
  final budget = (plan.freeMinutes * settings.fillRatio).floor();
  HabitSlot? slotOf(String title) => [...goals.meals, if (goals.exercise != null) goals.exercise!].where((h) => h.title == title).firstOrNull;
  final deferredMin = plan.deferred.fold<int>(0, (n, d) => n + d.minutes);
  const hm = formatHm;

  final steps = [
    _Step(
      title: '① 기상 시각 정하기',
      value: '${hm(plan.wake)} 기상',
      lines: [plan.alarms.first.reason, fixed.isNotEmpty ? '첫 일정이 이르면 준비·이동 시간만큼 알람을 당겨요' : '첫 일정이 늦어서 목표 기상을 그대로 써요'],
      blocks: const [],
    ),
    _Step(title: '② 전날 밤 취침 시각', value: '${hm(plan.bedTonight)} 취침', lines: [plan.alarms[1].reason], blocks: [sleep], nightSleep: true),
    _Step(
      title: '③ 캘린더 일정 고정',
      value: fixed.isNotEmpty ? '${fixed.where((b) => b.locked).length}개 고정' : '없음',
      lines: fixed.isNotEmpty ? [for (final b in fixed) '${hm(b.start)}–${hm(b.end)} ${b.title}'] : const ['캘린더 일정이 없어요. 엔진이 움직이지 않는 블록이에요'],
      blocks: fixed,
    ),
    _Step(
      title: '④ 식사·운동 자리 잡기',
      value: '습관 ${habits.length}개',
      lines: [
        for (final b in habits)
          () {
            final slot = slotOf(b.title);
            final moved = slot != null && formatClock(slot.start.minutes) != hm(b.start);
            return '${hm(b.start)} ${b.title}${moved ? ' (겹쳐서 ${formatClock(slot.start.minutes)} → ${hm(b.start)})' : ''}';
          }(),
      ],
      blocks: habits,
    ),
    _Step(
      title: '⑤ 빈 시간 계산',
      value: formatDuration(plan.freeMinutes),
      lines: ['빈 시간 ${formatDuration(plan.freeMinutes)} 중 75%인 ${formatDuration(budget)}까지만 할 일을 넣어요', '나머지 25%는 쉬는 틈과 예상 못 한 일에 남겨요'],
      blocks: const [],
    ),
    _Step(
      title: '⑥ 할 일 넣기',
      value: '할 일 ${formatDuration(plan.taskMinutes)}',
      lines: [
        '마감이 빠른 순서 → 우선순위, 50분씩 나누고 10분 쉬어요',
        '집중이 필요한 일은 09–12시에 먼저 넣어요',
        for (final b in tasks) '${hm(b.start)}–${hm(b.end)} ${b.title}${b.focus ? ' · 집중' : ''}',
        if (deferredMin > 0) '다 넣지 못한 ${formatDuration(deferredMin)}은 다음 날로 넘겨요',
      ],
      blocks: tasks,
    ),
    _Step(
      title: '⑦ 알람 맞추기',
      value: '알람 3개',
      lines: ['기상 ${hm(plan.wake)}', '마무리 ${hm(plan.alarms[2].at)} · ${plan.alarms[2].reason}', '취침 ${hm(plan.bedTonight)}'],
      blocks: const [],
    ),
    if (coachLines != null) _Step(title: '⑧ 코칭으로 조정', value: '자동 조정', lines: coachLines, blocks: blocks.where((b) => b.adjusted).toList()),
  ];
  return _Built(base: base, plan: plan, changes: changes, steps: steps, day: day);
}

List<RingSegment> _toSegments(DsColors c, List<ScheduleBlock> blocks, DateTime day, DayPlan plan, bool nightSleep) {
  final segs = <RingSegment?>[
    for (final b in blocks)
      if (b.kind == BlockKind.fixed && !b.locked)
        clipSegment(day, b.start, b.end, c.calendar, b.title)
      else
        clipSegment(day, b.start, b.end, b.kind == BlockKind.task || b.kind == BlockKind.fixed ? c.work : c.activity(b.activity ?? Activity.work),
            b.kind == BlockKind.task ? '할 일 · ${b.title}' : b.title),
    if (nightSleep) clipSegment(day, plan.dayEnd, addDays(day, 1), c.sleep, '수면(그날 밤)'),
  ];
  return segs.whereType<RingSegment>().toList();
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  _Scenario _id = _Scenario.normal;

  /// 0 = 시작 전, n = n단계까지 보임
  int _step = 0;
  bool _playing = false;
  Timer? _timer;
  _Built? _built;
  (AppState, _Scenario, DateTime)? _builtFor;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(int total) {
    _timer?.cancel();
    if (!_playing) return;
    if (_step >= total) {
      _playing = false;
      return;
    }
    _timer = Timer(Duration(milliseconds: _step == 0 ? 300 : 1500), () {
      if (!mounted) return;
      setState(() => _step++);
      haptic(6);
      _schedule(total);
    });
  }

  void _setPlaying(bool v, int total) {
    setState(() => _playing = v);
    _schedule(total);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final now = context.ui.now;
    final c = context.ds;
    final key = (s, _id, now);
    if (_builtFor == null || !identical(_builtFor!.$1, s) || _builtFor!.$2 != _id || _builtFor!.$3 != now) {
      _built = _build(s, _id, now);
      _builtFor = key;
    }
    final built = _built!;
    final total = built.steps.length;
    final shown = built.steps.take(_step.clamp(0, total)).toList();
    final cur = shown.lastOrNull;
    final segs = [for (final st in shown) ..._toSegments(c, st.blocks, built.day, built.plan, st.nightSleep)];
    final revealed = {for (final b in shown.expand((st) => st.blocks)) if (b.activity != Activity.sleep) b.id: b};
    final uniq = stableSorted(revealed.values, (a, b) => a.start.compareTo(b.start));
    final wakeMin = diffMin(built.plan.wake, built.day);

    void pick(_Scenario x) {
      setState(() {
        _id = x;
        _step = 0;
        _playing = true;
        _builtFor = null;
      });
      _schedule(_build(s, x, now).steps.length);
    }

    return ScreenList(tab: false, children: [
      TopBar(title: '일정 자동 생성 시연', sub: '${koreanDate(built.day)} 일정을 짜는 과정', onBack: context.ui.actions.back),
      Semantics(
        label: '상황',
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in _Scenario.values) DsChip(label: x.label, selected: _id == x, onTap: () => pick(x)),
        ]),
      ),
      LabelText(_id.desc),
      Center(
        child: Semantics(
          container: true,
          label: '일정 링',
          child: DayRing(
            plan: segs,
            records: const [],
            nowMinutes: _step >= 1 ? wakeMin : 0,
            label: '시연 일정 링',
            child: cur != null
                ? _RingInfo(key: ValueKey(_step), pill: '$_step / $total', title: cur.value, sub: cur.title.replaceFirst(RegExp(r'^[①-⑧]\s*'), ''))
                : const _RingInfo(title: '준비됐어요', sub: '▶ 재생을 누르세요'),
          ),
        ),
      ),
      Row(children: [
        _CtrlButton(
          semantic: '처음부터',
          onTap: () {
            _timer?.cancel();
            setState(() {
              _step = 0;
              _playing = false;
            });
          },
          child: DsIcon(DsIcons.refresh, size: 18, color: c.ink),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CtrlButton(
            primary: true,
            semantic: _playing ? '멈춤' : '재생',
            onTap: () {
              if (_step >= total) setState(() => _step = 0);
              _setPlaying(!_playing, total);
            },
            child: Text(
              _playing ? '멈춤' : (_step >= total ? '다시 재생' : (_step == 0 ? '▶ 일정 짜기 시작' : '▶ 이어서 재생')),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.accentInk),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _CtrlButton(
          semantic: '다음 단계',
          onTap: _step >= total
              ? null
              : () {
                  _timer?.cancel();
                  setState(() {
                    _playing = false;
                    _step = (_step + 1).clamp(0, total);
                  });
                  haptic(6);
                },
          child: Text('다음 ›', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink)),
        ),
      ]),
      if (cur != null)
        _FadeIn(
          key: ValueKey('st-$_step'),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: DsGap.cardPad,
              decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DsTitle(cur.title),
                for (final l in cur.lines) ...[const SizedBox(height: 6), Text(l, style: DsText.body.copyWith(color: c.ink))],
              ]),
            ),
          ),
        ),
      if (uniq.isNotEmpty)
        Semantics(
          container: true,
          label: '만들어진 일정',
          child: DsCard(list: true, children: [
            for (var i = 0; i < uniq.length; i++)
              _FadeIn(
                key: ValueKey(uniq[i].id),
                child: LineRow(
                  time: formatHm(uniq[i].start),
                  color: c.block(uniq[i]),
                  last: i == uniq.length - 1,
                  tag: uniq[i].adjusted ? '조정됨' : (uniq[i].kind == BlockKind.task ? '할 일' : (uniq[i].kind == BlockKind.fixed ? '캘린더' : '습관')),
                  tagColor: uniq[i].adjusted ? c.accentStrong : null,
                  child: Text(
                    uniq[i].kind == BlockKind.task ? '${uniq[i].title} · ${formatDuration(uniq[i].minutes)}' : uniq[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsText.base.copyWith(color: c.ink),
                  ),
                ),
              ),
          ]),
        ),
      if (_step >= total && _id != _Scenario.normal)
        _FadeIn(
          child: Semantics(
            container: true,
            label: '평소와 비교',
            child: DsCard(tint: true, gap: 6, children: [
              const DsTitle('평소 하루와 비교하면'),
              if (built.changes.isEmpty) Text('바뀐 것이 없어요', style: DsText.body.copyWith(color: c.ink)) else for (final x in built.changes) ImpactLine(x),
            ]),
          ),
        ),
      Text('시연은 예시 할 일로 계산해요. 내 기록과 일정은 바뀌지 않아요.', textAlign: TextAlign.center, style: DsText.small.copyWith(color: c.muted)),
    ]);
  }
}

class _RingInfo extends StatelessWidget {
  const _RingInfo({super.key, this.pill, required this.title, required this.sub});
  final String? pill;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (pill != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.lineBtn), borderRadius: BorderRadius.circular(999)),
            child: Text(pill!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink, fontFeatures: DsText.num)),
          ),
        const SizedBox(height: 4),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w700, letterSpacing: -0.36, color: c.ink)),
        const SizedBox(height: 3),
        Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 18 / 13, color: c.inkSoft)),
      ]),
    );
  }
}

/// 시연 조작 단추(높이 52, 모서리 16).
class _CtrlButton extends StatelessWidget {
  const _CtrlButton({required this.child, required this.onTap, required this.semantic, this.primary = false});
  final Widget child;
  final VoidCallback? onTap;
  final String semantic;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Pressable(
      onTap: onTap,
      semanticLabel: semantic,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 52,
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? c.accent : Colors.transparent,
            border: Border.all(color: primary ? c.accent : c.lineBtn),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 살짝 아래에서 떠오르며 나타난다(동작 줄이기면 바로).
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child)),
      child: child,
    );
  }
}
