// 상태에서 화면에 필요한 값을 계산한다. 모두 순수 함수다. 웹 버전 src/app/derive.ts와 같은 규칙.

import '../core/engine/achievement.dart';
import '../core/engine/correction.dart';
import '../core/engine/schedule_builder.dart';
import '../core/engine/set_day.dart';
import '../core/model/models.dart';
import 'duration.dart';
import 'state.dart';

/// 같은 값이면 원래 순서를 지키는 정렬(Dart의 sort는 순서를 지키지 않는다).
List<T> stableSorted<T>(Iterable<T> xs, int Function(T a, T b) cmp) {
  final indexed = [for (final (i, x) in xs.indexed) (i, x)];
  indexed.sort((a, b) {
    final c = cmp(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final p in indexed) p.$2];
}

bool _isAfter(DateTime a, DateTime b) => a.isAfter(b);
bool _isBefore(DateTime a, DateTime b) => a.isBefore(b);

/// 그 날 일정에 쓸 목표. 그날만 바꾼 기상·습관, 교정 중이면 이번 주 기상 목표, 코칭으로 바꾼 저녁 시각을 반영한다.
HabitGoals effectiveGoals(AppState s, String key) {
  final g = s.goals;
  final c = s.correction;
  final o = s.overrides[key];
  final wake = o?.wake != null ? ClockTime(o!.wake!) : (c != null && c.plan.status == CorrectionStatus.active ? ClockTime(c.plan.weekTarget) : g.wake);
  final shift = o?.dinnerShift ?? 0;
  HabitSlot? edit(HabitSlot slot) {
    final e = o?.habits[slot.title];
    if (e == null) return slot;
    if (e.skip) return null;
    return slot.copyWith(start: e.start != null ? ClockTime(e.start!) : null, minutes: e.minutes);
  }

  final ex = g.exercise == null ? null : edit(g.exercise!);
  return g.copyWith(
    wake: wake,
    meals: [
      for (final m in g.meals)
        if (edit(shift != 0 && m.title.contains('저녁') ? m.copyWith(start: ClockTime(m.start.minutes + shift)) : m) case final x?) x,
    ],
    exercise: ex,
    clearExercise: ex == null,
  );
}

/// 다른 날 일정에 이미 잡힌 할 일 시간. 오늘 잡아 둔 조각을 내일 또 넣지 않도록 뺀다.
/// '했어요'로 반영한 조각은 doneMinutes에 이미 들어 있고, '못 했어요'는 다시 넣어야 하므로 뺀다.
Map<String, int> reservedMinutes(AppState s, List<ScheduleBlock> blocks) {
  final credited = {for (final c in s.credits) c.blockId};
  final missed = {for (final m in s.misses) m.blockId};
  final out = <String, int>{};
  for (final b in blocks) {
    final id = b.taskId;
    if (b.kind != BlockKind.task || id == null || credited.contains(b.id) || missed.contains(b.id)) continue;
    out[id] = (out[id] ?? 0) + diffMin(b.end, b.start);
  }
  return out;
}

/// 일정에 넣을 할 일: 목록 순서가 곧 우선순위(rank), 걸리는 시간은 보정한 시간.
List<TaskItem> tasksForPlanning(AppState s, Map<String, int> reserved) {
  final open = s.tasks.where((t) => !t.done).toList();
  return [
    for (var i = 0; i < open.length; i++)
      open[i].copyWith(rank: i, estMinutes: plannedMinutes(open[i], s.durations), doneMinutes: open[i].doneMinutes + (reserved[open[i].id] ?? 0)),
  ].where((t) => t.remainingMinutes > 0).toList();
}

/// 엔진으로 하루 일정을 새로 만든다(저장하지 않음).
DayPlan buildPlan(AppState s, String key, {DateTime? notBefore, List<ScheduleBlock> reservedBlocks = const []}) {
  final plan = const ScheduleBuilder().buildDay(DayPlanInput(
    date: fromKey(key),
    goals: effectiveGoals(s, key),
    settings: s.settings,
    fixedEvents: s.events,
    tasks: tasksForPlanning(s, reservedMinutes(s, reservedBlocks)),
    notBefore: notBefore,
  ));
  final extra = s.overrides[key]?.notes ?? const <String>[];
  final c = s.correction;
  final alarms = c != null && c.plan.status == CorrectionStatus.active && plan.alarms.first.reason.startsWith('목표 기상')
      ? [
          plan.alarms.first.copyWith(reason: '단계적 교정: 이번 주 기상 목표 ${formatClock(c.plan.weekTarget)} (최종 ${formatClock(c.plan.target)})'),
          ...plan.alarms.skip(1),
        ]
      : plan.alarms;
  return plan.copyWith(alarms: alarms, notes: [...plan.notes, ...extra]);
}

/// 화면에 보일 그 날 일정. 저장했는지와 입력이 바뀌어 오래됐는지 함께 알려 준다.
class PlanView {
  const PlanView(this.plan, {required this.stored, required this.outdated});
  final DayPlan plan;
  final bool stored;
  final bool outdated;

  List<ScheduleBlock> get blocks => plan.blocks;
  DateTime get wake => plan.wake;
  DateTime get bedTonight => plan.bedTonight;
}

/// 저장한 일정이 있으면 그것을, 없으면 지금 입력으로 만든 일정을 돌려준다.
PlanView planFor(AppState s, String key, DateTime now) {
  final stored = s.plans[key];
  if (stored != null) return PlanView(stored.plan, stored: true, outdated: stored.inputsVersion < s.inputsVersion);
  final todayKey = dateKey(now);
  // 내일 일정은 오늘 남은 할 일 조각을 빼고 만든다.
  final reserved = key.compareTo(todayKey) > 0 ? (s.plans[todayKey]?.blocks ?? const <ScheduleBlock>[]) : const <ScheduleBlock>[];
  return PlanView(buildPlan(s, key, reservedBlocks: reserved), stored: false, outdated: false);
}

StoredPlan storedFrom(DayPlan plan, AppState s, [int regen = 0]) => StoredPlan(plan, inputsVersion: s.inputsVersion, regen: regen);

/// 하루 중간에 다시 짠다: 이미 지난 블록은 그대로 두고 남은 시간만 새로 채운다.
StoredPlan regeneratePlan(AppState s, String key, DateTime now) {
  final old = s.plans[key];
  final todayKey = dateKey(now);
  if (old == null || key.compareTo(todayKey) > 0) {
    final reserved = key.compareTo(todayKey) > 0 ? (s.plans[todayKey]?.blocks ?? const <ScheduleBlock>[]) : const <ScheduleBlock>[];
    return storedFrom(buildPlan(s, key, reservedBlocks: reserved), s, (old?.regen ?? 0) + 1);
  }
  // 지금 하고 있는 할 일 조각은 끊지 않는다(그 할 일이 아직 남아 있을 때).
  final openIds = {for (final t in s.tasks) if (!t.done) t.id};
  final current = old.blocks
      .where((b) => b.kind == BlockKind.task && b.taskId != null && openIds.contains(b.taskId) && !_isAfter(b.start, now) && _isAfter(b.end, now))
      .toList();
  final kept = [...old.blocks.where((b) => !_isAfter(b.end, now)), ...current];
  final notBefore = current.fold<DateTime>(now, (m, b) => _isAfter(b.end, m) ? b.end : m);
  final fresh = buildPlan(s, key, notBefore: notBefore, reservedBlocks: kept);
  final regen = old.regen + 1;
  final future = [
    for (final b in fresh.blocks)
      if (_isAfter(b.end, now) && !(b.kind == BlockKind.task && _isBefore(b.start, notBefore))) b.copyWith(id: 'r$regen-${b.id}'),
  ];
  final blocks = stableSorted([...kept, ...future], (a, b) => a.start.compareTo(b.start));
  return StoredPlan(
    fresh.copyWith(
      wake: old.plan.wake,
      bedTonight: old.plan.bedTonight,
      alarms: [old.plan.alarms.first, ...fresh.alarms.skip(1)],
      blocks: blocks,
    ),
    inputsVersion: s.inputsVersion,
    regen: regen,
  );
}

// ---------------------------------------------------------------------------
// 기록
// ---------------------------------------------------------------------------

ActivityLog? currentLog(AppState s) {
  for (var i = s.logs.length - 1; i >= 0; i--) {
    if (s.logs[i].isOpen) return s.logs[i];
  }
  return null;
}

WakeRecord? wakeRecord(AppState s, String key) {
  for (final w in s.wakes) {
    if (w.day == key) return w;
  }
  return null;
}

/// 그 날 실제 기상 시각: 알람 끄기 기록, 없으면 기상 무렵에 끝난 수면 기록.
DateTime? wakeTime(AppState s, String key, DayPlan plan) {
  final rec = wakeRecord(s, key);
  if (rec != null) return rec.at;
  final from = addMin(plan.wake, -180);
  final to = addMin(plan.wake, 240);
  for (final l in s.logs) {
    final e = l.end;
    if (l.activity == Activity.sleep && e != null && !l.isEstimate && !_isBefore(e, from) && !_isAfter(e, to)) return e;
  }
  return null;
}

List<ActivityLog> logsAround(AppState s, String key) {
  final day = fromKey(key);
  final from = addMin(day, -12 * 60);
  final to = addMin(addDays(day, 1), 6 * 60);
  return s.logs.where((l) => !_isBefore(l.start, from) && _isBefore(l.start, to)).toList();
}

DayMarks marksFor(AppState s, String key) => DayMarks(
      missed: {for (final m in s.misses) if (m.day == key) m.blockId},
      skipped: {for (final m in s.skips) if (m.day == key) m.blockId},
      rest: s.restDays.contains(key),
    );

/// 하루 평가(달성·셋 데이).
class DayView {
  const DayView({required this.key, required this.plan, required this.hasData, required this.ev});
  final String key;
  final DayPlan plan;
  final bool hasData;
  final DayEvaluation ev;

  List<BlockOutcome> get outcomes => ev.outcomes;
  List<BlockOutcome> get habits => ev.habits;
  bool get isSetDay => ev.isSetDay;
  bool get rest => ev.rest;
  bool get wakeOk => ev.wakeOk;
  DateTime? get wakeAt => ev.wakeAt;
  int get achieved => ev.achieved;
  int get total => ev.total;
  double? get rate => ev.rate;
}

/// 하루 평가. 일정이 저장되지 않은 지난 날은 데이터 없음으로 본다.
DayView evaluate(AppState s, String key, DateTime now) {
  final todayKey = dateKey(now);
  final view = planFor(s, key, now);
  final plan = view.plan;
  final obs = s.observation;
  final observing = obs != null && (obs.phase == ObservationPhase.recording || key.compareTo(obs.day1) <= 0);
  final hasData = !observing && key.compareTo(todayKey) <= 0 && (view.stored || key == todayKey);
  final logs = logsAround(s, key);
  final marks = marksFor(s, key);
  // 같은 활동을 다른 시각에 확정 기록했다면 '기록 없음(추정)'이 아니라 시각을 놓친 것이다.
  bool loggedOffTime(ScheduleBlock b) => logs.any((l) =>
      l.activity == b.activity && !l.isEstimate && _isBefore(l.start, addMin(b.end, 120)) && _isAfter(l.end ?? now, addMin(b.start, -120)));
  final target = plan.blocks.where((b) => !marks.skipped.contains(b.id) && !loggedOffTime(b)).toList();
  final estimates = estimateMissing(blocks: target, logs: logs, now: now);
  final ev = evaluateDay(
    blocks: plan.blocks,
    logs: [...logs, ...estimates],
    wake: plan.wake,
    wakeAt: wakeTime(s, key, plan),
    now: now,
    goalSleepMinutes: s.goals.sleepMinutes,
    marks: marks,
  );
  return DayView(key: key, plan: plan, hasData: hasData, ev: ev);
}

/// 저녁 확인에서 물을 일정: 시작한 습관·할 일 중 기록으로 달성이 확인되지 않은 것 + 이미 답한 것.
/// open은 아직 답하지 않은 것('남은 건 일정대로 했어요'로 한 번에 채울 대상). 웹 eveningAsk와 같다.
({List<ScheduleBlock> blocks, List<ScheduleBlock> open}) eveningAsk(AppState s, String key, DateTime now) {
  final view = evaluate(s, key, now);
  final missed = {for (final m in s.misses) if (m.day == key) m.blockId};
  final skipped = {for (final m in s.skips) if (m.day == key) m.blockId};
  final did = {for (final l in s.logs) if (l.source == LogSource.evening) l.id.replaceFirst(RegExp('^ev-'), '')};
  bool answered(ScheduleBlock b) => did.contains(b.id) || missed.contains(b.id) || skipped.contains(b.id);
  final blocks = view.plan.blocks.where((b) {
    if (b.activity == null || b.kind == BlockKind.fixed || b.activity == Activity.sleep) return false;
    if (b.start.isAfter(now)) return false;
    if (answered(b)) return true;
    final o = view.outcomes.where((x) => x.block.id == b.id).firstOrNull;
    return o != null && o.outcome != Outcome.achieved && o.outcome != Outcome.pending;
  }).toList();
  return (blocks: blocks, open: blocks.where((b) => !answered(b)).toList());
}

/// 오늘 습관 진행도(기록 직후·위젯에 보여 준다). 저녁 확인 머리와 같은 숫자.
({int achieved, int total}) todayProgress(AppState s, DateTime now) {
  final v = evaluate(s, dateKey(now), now);
  return (achieved: v.achieved, total: v.total);
}

List<String> weekKeys(DateTime now, [int offsetWeeks = 0]) {
  final mon = addDays(mondayOf(now), offsetWeeks * 7);
  return [for (var i = 0; i < 7; i++) dateKey(addDays(mon, i))];
}

/// month는 1~12.
List<String> monthKeys(int year, int month) {
  final days = DateTime(year, month + 1, 0).day;
  return [for (var i = 1; i <= days; i++) dateKey(DateTime(year, month, i))];
}

/// 통계 칸: 습관(활동)별, 할 일은 따로.
class RateKey {
  const RateKey.activity(Activity this.activity) : task = false;
  const RateKey.task()
      : activity = null,
        task = true;
  final Activity? activity;
  final bool task;

  @override
  bool operator ==(Object other) => other is RateKey && other.activity == activity && other.task == task;

  @override
  int get hashCode => Object.hash(activity, task);
}

class PeriodStats {
  const PeriodStats({required this.days, required this.setDays, required this.rates});
  final List<DayView> days;
  final int setDays;
  final Map<RateKey, HabitRate> rates;
}

/// 기간 통계: 셋 데이 수와 습관별 달성률. 할 일 블록은 따로 센다.
PeriodStats periodStats(AppState s, List<String> keys, DateTime now) {
  final todayKey = dateKey(now);
  final days = [for (final k in keys) if (k.compareTo(todayKey) <= 0) evaluate(s, k, now)].where((d) => d.hasData).toList();
  final rates = <RateKey, HabitRate>{};
  for (final o in days.expand((d) => d.outcomes)) {
    final k = o.block.kind == BlockKind.task ? const RateKey.task() : RateKey.activity(o.block.activity!);
    final r = rates[k] ?? HabitRate(activity: o.block.activity!, achieved: 0, counted: 0, estimated: 0);
    rates[k] = HabitRate(
      activity: r.activity,
      achieved: r.achieved + (o.outcome == Outcome.achieved ? 1 : 0),
      counted: r.counted + (o.outcome == Outcome.achieved || o.outcome == Outcome.missed ? 1 : 0),
      estimated: r.estimated + (o.outcome == Outcome.estimated ? 1 : 0),
    );
  }
  return PeriodStats(days: days, setDays: days.where((d) => d.isSetDay).length, rates: rates);
}

/// 저녁 확인에서 물어볼 블록: 이미 시작했고, 달성으로 확인되지 않은 습관·할 일.
List<BlockOutcome> openQuestions(DayView view, DateTime now) => view.outcomes
    .where((o) => !_isAfter(o.block.start, now) && o.outcome != Outcome.achieved && o.outcome != Outcome.pending && o.block.activity != Activity.sleep)
    .toList();

String weekMonday(String key) => dateKey(mondayOf(fromKey(key)));

/// 최근 기상 기록의 스누즈 횟수(오래된 것부터, 마지막이 오늘).
List<int> recentSnoozes(AppState s, String todayKey, [int days = 7]) {
  final today = fromKey(todayKey);
  return [
    for (var i = days - 1; i >= 0; i--)
      if (wakeRecord(s, dateKey(addDays(today, -i))) case final rec?) rec.snoozes,
  ];
}

// ---------------------------------------------------------------------------
// 1일차 관찰: 기록에서 하루 모습을 읽는다
// ---------------------------------------------------------------------------

const mealSlots = ['아침 식사', '점심 식사', '저녁 식사'];

class Span {
  const Span(this.start, this.minutes);
  final DateTime start;
  final int minutes;
}

class WorkSpan {
  const WorkSpan(this.start, this.end, this.minutes);
  final DateTime start;
  final DateTime end;
  final int minutes;
}

class ObservedDay {
  const ObservedDay({
    required this.key,
    this.wakeAt,
    this.bedAt,
    this.firstLogAt,
    this.meals = const {},
    this.exercise,
    this.work,
    this.logCount = 0,
  });
  final String key;

  /// 일어난 시각(그날 아침 끝난 수면 기록, 없으면 기상 기록).
  final DateTime? wakeAt;

  /// 그날 밤 잠든 시각(이미 기록했으면).
  final DateTime? bedAt;

  /// 첫 기록 시각. 일어난 시각을 모를 때 기본값으로 쓴다.
  final DateTime? firstLogAt;

  /// 끼니 이름('아침 식사' 등) → 기록.
  final Map<String, Span> meals;
  final Span? exercise;
  final WorkSpan? work;
  final int logCount;
}

String _mealSlotOf(DateTime d) {
  final m = d.hour * 60 + d.minute;
  return m < 10 * 60 + 30 ? '아침 식사' : (m < 15 * 60 ? '점심 식사' : '저녁 식사');
}

ObservedDay observedDay(AppState s, String key, DateTime now) {
  final day = fromKey(key);
  final from = addMin(day, 3 * 60);
  final to = addMin(addDays(day, 1), 3 * 60);
  final confirmed = s.logs.where((l) => !l.isEstimate).toList();
  final inDay = confirmed.where((l) => !_isBefore(l.start, from) && _isBefore(l.start, to)).toList();
  DateTime end(ActivityLog l) => l.end ?? now;
  int minutes(ActivityLog l) {
    final m = diffMin(end(l), l.start);
    return m < 1 ? 1 : m;
  }

  final morningSleep = confirmed.where((l) => l.activity == Activity.sleep && l.end != null && !_isBefore(l.end!, from) && _isBefore(l.end!, addMin(day, 15 * 60))).firstOrNull;
  final wakeAt = morningSleep?.end ?? wakeRecord(s, key)?.at;
  // 그날 밤 수면: 저녁 6시 이후 ~ 다음 날 새벽 3시 사이에 시작한 수면 기록
  final night = inDay.where((l) => l.activity == Activity.sleep && !_isBefore(l.start, addMin(day, 18 * 60))).firstOrNull;

  final meals = <String, Span>{};
  for (final l in inDay.where((x) => x.activity == Activity.meal)) {
    meals.putIfAbsent(_mealSlotOf(l.start), () => Span(l.start, minutes(l)));
  }
  final ex = inDay.where((l) => l.activity == Activity.exercise).firstOrNull;
  final works = inDay.where((l) => l.activity == Activity.work).toList();
  final work = works.isEmpty
      ? null
      : WorkSpan(works.first.start, works.map(end).reduce((a, b) => _isAfter(a, b) ? a : b), works.fold<int>(0, (n, l) => n + minutes(l)));
  return ObservedDay(
    key: key,
    wakeAt: wakeAt,
    bedAt: night?.start,
    firstLogAt: inDay.where((x) => x.activity != Activity.sleep).firstOrNull?.start,
    meals: meals,
    exercise: ex == null ? null : Span(ex.start, minutes(ex)),
    work: work,
    logCount: inDay.length,
  );
}

/// 시각을 5분 단위로 맞춘 자정 기준 분.
int roundedClock(DateTime d) => ((d.hour * 60 + d.minute) / 5).round() * 5;

// ---------------------------------------------------------------------------
// 일정이 어떻게 바뀌는지(캘린더 일정 추가 미리보기, 시연 비교)
// ---------------------------------------------------------------------------

enum PlanDiffKind { wake, bed, moved, dropped, tasks, deferred }

class PlanDiff {
  const PlanDiff(this.kind, this.text);
  final PlanDiffKind kind;
  final String text;
}

/// 두 일정의 차이를 사람이 읽는 문장으로.
List<PlanDiff> comparePlans(DayPlan before, DayPlan after) {
  final out = <PlanDiff>[];
  if (before.wake != after.wake) {
    out.add(PlanDiff(PlanDiffKind.wake, '기상 알람 ${formatHm(before.wake)} → ${formatHm(after.wake)} (${after.alarms.first.reason})'));
  }
  if (before.bedTonight != after.bedTonight) {
    out.add(PlanDiff(PlanDiffKind.bed, '전날 밤 취침 ${formatHm(before.bedTonight)} → ${formatHm(after.bedTonight)}'));
  }
  List<ScheduleBlock> habits(DayPlan p) => p.blocks.where((b) => b.kind == BlockKind.habit && b.activity != Activity.sleep).toList();
  for (final b in habits(before)) {
    final a = habits(after).where((x) => x.title == b.title).firstOrNull;
    if (a == null) {
      out.add(PlanDiff(PlanDiffKind.dropped, '${b.title}: 겹쳐서 이날은 빠져요'));
    } else if (a.start != b.start) {
      out.add(PlanDiff(PlanDiffKind.moved, '${b.title} ${formatHm(b.start)} → ${formatHm(a.start)} (겹쳐서 뒤로)'));
    }
  }
  if (before.taskMinutes != after.taskMinutes) {
    out.add(PlanDiff(PlanDiffKind.tasks, '할 일 ${formatDuration(before.taskMinutes)} → ${formatDuration(after.taskMinutes)}'));
  }
  int deferredMin(DayPlan p) => p.deferred.fold(0, (n, d) => n + d.minutes);
  if (deferredMin(after) > deferredMin(before)) {
    out.add(PlanDiff(PlanDiffKind.deferred, '다음 날로 넘기는 할 일 ${formatDuration(deferredMin(after) - deferredMin(before))} 늘어요'));
  }
  return out;
}

/// 이 캘린더 일정을 넣으면 그 날 일정이 어떻게 바뀌는지.
List<PlanDiff> eventImpact(AppState s, FixedEvent ev, DateTime now) {
  final key = dateKey(ev.start);
  final todayKey = dateKey(now);
  final reserved = key.compareTo(todayKey) > 0 ? (s.plans[todayKey]?.blocks ?? const <ScheduleBlock>[]) : const <ScheduleBlock>[];
  DayPlan build(AppState x) => key == todayKey ? buildPlan(x, key, notBefore: now) : buildPlan(x, key, reservedBlocks: reserved);
  final before = build(s);
  final after = build(s.copyWith(events: [...s.events.where((e) => e.id != ev.id), ev]));
  return comparePlans(before, after);
}
