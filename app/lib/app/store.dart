// 앱 상태 저장소와 동작. 화면은 여기 있는 메서드만 부른다. 웹 버전 src/app/store.ts와 같은 규칙.
//
// Flutter에 의존하지 않는다(순수 Dart). 화면은 addListener로 바뀜을 듣는다(lib/ui/scope.dart).

import 'dart:math' as math;

import '../core/engine/achievement.dart';
import '../core/engine/coaching.dart';
import '../core/engine/correction.dart';
import '../core/engine/now_tracker.dart';
import '../core/model/models.dart';
import 'derive.dart';
import 'duration.dart';
import 'ics.dart';
import 'metrics.dart';
import 'priority_model.dart';
import 'state.dart';

/// 할 일·캘린더를 바꾼 결과.
class PlanChange {
  const PlanChange({required this.replanned, this.deferred = const []});

  /// 남은 일정의 할 일 조각이 바뀌었는지.
  final bool replanned;

  /// 이번 변경으로 빈 시간이 모자라 오늘에서 밀려난 할 일 이름.
  final List<String> deferred;
}

class ImportOutcome extends PlanChange {
  const ImportOutcome({required super.replanned, super.deferred, required this.count, required this.dupes, required this.capped});
  final int count;

  /// 이미 직접 넣은(또는 다른 캘린더에서 가져온) 같은 일정이라 뺀 수.
  final int dupes;

  /// 너무 많아 뺀 수.
  final int capped;
}

class TapOutcome {
  const TapOutcome({required this.changed, this.merged = false});
  final bool changed;
  final bool merged;
}

enum RingKind { wake, bed }

class Ring {
  const Ring({required this.kind, required this.key, required this.at});
  final RingKind kind;
  final String key;
  final DateTime at;
}

class Nudge {
  const Nudge({required this.key, required this.title, required this.body});
  final String key;
  final String title;
  final String body;
}

enum AddResult { added, updated, self }

/// 한 캘린더에서 가져오는 일정 최대 수(저장 공간 보호).
const maxImport = 400;

/// 할 일·캘린더 변경을 되돌릴 수 있는 시간.
const planUndoWindow = Duration(seconds: 15);

class Store {
  Store({required this.storage, DateTime Function()? wallClock}) : _wall = wallClock ?? DateTime.now {
    _state = storage.load(now: now());
  }

  final StateStorage storage;
  final DateTime Function() _wall;
  late AppState _state;
  SaveResult _saveResult = SaveResult.ok;
  final _listeners = <void Function()>[];

  // -------------------------------------------------------------------------
  // 시계. 시험·시연용으로 멈추거나 앞당길 수 있다.
  // -------------------------------------------------------------------------

  Duration _offset = Duration.zero;
  DateTime? _fixed;

  DateTime now() => _fixed ?? _wall().add(_offset);

  /// 테스트용: 시계를 멈춘 시각으로 고정한다(null이면 해제).
  void setFixedClock(DateTime? t) => _fixed = t;

  Duration get clockOffset => _offset;
  set clockOffset(Duration d) {
    _offset = d;
    _emit();
  }

  // -------------------------------------------------------------------------
  // 상태
  // -------------------------------------------------------------------------

  AppState get state => _state;

  /// 마지막 저장 결과: quota면 저장 공간이 가득 찼다.
  SaveResult get storageProblem => _saveResult;
  bool get storageAvailable => _saveResult == SaveResult.ok;
  KeptReason? get loadIssue => storage.loadIssue;

  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);

  void _emit() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  void _set(AppState Function(AppState s) fn) {
    _state = fn(_state);
    _saveResult = storage.save(_state);
    _emit();
  }

  void replaceState(AppState next) {
    _state = next;
    _tracker = null;
    _saveResult = storage.save(_state);
    _emit();
  }

  static int _seq = 0;
  static String newId(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}';

  // -------------------------------------------------------------------------
  // 백업 내보내기·불러오기
  // -------------------------------------------------------------------------

  /// 지금 상태를 백업 JSON으로(웹 버전과 같은 형식).
  String exportBackup() => serialize(_state);

  /// 웹·앱에서 내보낸 백업을 불러온다. 지금 데이터는 지우지 않고 따로 보관한다.
  /// 형식이 맞지 않으면 FormatException을 던지고 아무것도 바꾸지 않는다.
  void importBackup(String text) {
    final next = deserialize(text);
    storage.keepCopy(serialize(_state), KeptReason.beforeImport);
    replaceState(next);
    ensureDay();
  }

  /// 보관해 둔 이전 데이터로 되돌린다.
  bool restoreKept(String key) {
    final text = storage.kv.read(key);
    if (text == null) return false;
    try {
      final next = deserialize(text);
      replaceState(next);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 하루 시작·일정 확정
  // -------------------------------------------------------------------------

  bool _recording(AppState s) => s.observation?.phase == ObservationPhase.recording;

  /// 오늘 일정이 없으면 지금 입력으로 만들어 고정한다. 주간 교정 판정도 여기서 한다.
  void ensureDay([DateTime? at]) {
    final t = at ?? now();
    if (!_state.onboarded || _recording(_state)) return;
    final key = dateKey(t);
    // 관찰 1일차까지는 일정이 없다.
    final obs = _state.observation;
    if (obs != null && key.compareTo(obs.day1) <= 0) return;
    var changed = false;
    var s = _state;
    final weekly = _runWeeklyCorrection(s, t);
    if (weekly != null) {
      s = weekly;
      changed = true;
    }
    if (!s.plans.containsKey(key)) {
      s = s.withPlan(key, storedFrom(buildPlan(s, key, notBefore: t), s));
      changed = true;
    }
    if (changed) _set((_) => s);
  }

  AppState? _runWeeklyCorrection(AppState s, DateTime t) {
    final c = s.correction;
    final thisWeek = dateKey(mondayOf(t));
    if (c == null || c.plan.status != CorrectionStatus.active || c.lastUpdateWeek.compareTo(thisWeek) >= 0) return null;
    final lastWeek = weekKeys(addDays(t, -7));
    final days = [for (final k in lastWeek) evaluate(s, k, t)].where((d) => d.hasData && !d.rest).toList();
    final rate = days.isEmpty ? null : days.where((d) => d.wakeOk).length / days.length;
    final tired = s.misses.where((m) => m.reason == MissReason.tired && lastWeek.contains(m.day)).length;
    if (rate == null) return s.copyWith(correction: c.copyWith(lastUpdateWeek: thisWeek));
    final r = c.plan.weeklyUpdate(achievementRate: rate, tiredCount: c.holdNext ? math.max(2, tired) : tired);
    final target = r.plan.weekTarget;
    final pct = (rate * 100).round();
    final info = InboxItem(
      id: newId('info'),
      day: dateKey(t),
      createdAt: t,
      kind: InboxKind.info,
      message: r.decision == WeeklyDecision.done
          ? '기상 목표 ${formatClock(target)}에 도달했어요. 지난주 기상 달성 $pct%.'
          : '이번 주 기상 목표는 ${formatClock(target)}이에요. 지난주 기상 달성 $pct% · ${r.decision.label}.',
    );
    return s
        .copyWith(
          correction: CorrectionState(
            plan: r.plan,
            lastUpdateWeek: thisWeek,
            holdNext: false,
            history: [...c.history, CorrectionHistory(week: thisWeek, decision: r.decision, rate: rate, target: target)],
          ),
          inbox: [...s.inbox, info],
        )
        .bump();
  }

  /// 저장한 일정을 지금 입력으로 다시 짠다.
  void regenerate(String key) {
    final t = now();
    _set((s) => s.withPlan(key, regeneratePlan(s, key, t)));
  }

  /// 내일 일정을 지금 입력으로 고정한다(저녁 확인·취침 기록 때).
  AppState _lockTomorrow(AppState s, DateTime t) {
    final tomorrow = dateKey(addDays(t, 1));
    if (s.plans.containsKey(tomorrow)) return s;
    // 관찰 1일차(기록만 하는 날)에는 일정을 만들지 않는다.
    final obs = s.observation;
    if (obs != null && (obs.phase == ObservationPhase.recording || tomorrow.compareTo(obs.day1) <= 0)) return s;
    final today = s.plans[dateKey(t)];
    return s.withPlan(tomorrow, storedFrom(buildPlan(s, tomorrow, reservedBlocks: today?.blocks ?? const []), s));
  }

  // -------------------------------------------------------------------------
  // '지금' 버튼
  // -------------------------------------------------------------------------

  NowTracker? _tracker;
  List<ActivityLog>? _trackerSynced;

  NowTracker _syncedTracker() {
    if (_tracker == null || !identical(_trackerSynced, _state.logs)) {
      _tracker = NowTracker(logs: _state.logs, idGenerator: () => newId('log'));
      _trackerSynced = _state.logs;
    }
    return _tracker!;
  }

  AppState _commitLogs(AppState s, List<ActivityLog> logs) {
    _trackerSynced = logs;
    return s.copyWith(logs: logs);
  }

  TapOutcome tap(Activity activity, {LogSource source = LogSource.button}) {
    final t = now();
    final tr = _syncedTracker();
    final before = currentLog(_state);
    final r = tr.tap(activity, t, source: source);
    if (!r.changed) return const TapOutcome(changed: false);
    var s = _commitLogs(_state, tr.logs);
    s = _afterTap(s, t, activity, before, r.ended);
    _set((_) => s);
    return TapOutcome(changed: true, merged: r.merged);
  }

  AppState _afterTap(AppState s0, DateTime t, Activity activity, ActivityLog? before, ActivityLog? ended) {
    var s = s0;
    final todayKey = dateKey(t);
    // 아침에 수면 기록이 끝나면 기상으로 기록한다.
    if (before?.activity == Activity.sleep && ended != null && wakeRecord(s, todayKey) == null) {
      s = _recordWake(s, t, WakeSource.button, s.alarms['$todayKey|wake']?.snoozes ?? 0, ended);
    }
    // 저녁 식사 끝(R2), 업무 끝(R3)
    if (ended?.activity == Activity.meal && ended!.start.hour >= 17) {
      final bed = planFor(s, dateKey(addDays(t, 1)), t).bedTonight;
      s = _coach(s, DinnerLogged(end: t, bedtime: bed), t);
    }
    if (ended?.activity == Activity.work) {
      final plan = planFor(s, todayKey, t);
      final ends = [
        for (final b in plan.blocks)
          if ((b.kind == BlockKind.task || (b.kind == BlockKind.fixed && b.locked)) && b.end.hour < 22) b.end,
      ];
      if (ends.isNotEmpty) {
        final planned = ends.reduce((a, b) => a.isAfter(b) ? a : b);
        s = _coach(s, WorkEnded(planned: planned, actual: t), t);
      }
    }
    // 저녁에 잠들면 내일 일정과 알람을 고정한다(알람은 이후 앞당기기만).
    if (activity == Activity.sleep && t.hour >= 18) {
      s = _lockTomorrow(s, t);
      s = s.copyWith(alarms: {...s.alarms, '${dateKey(addDays(t, 1))}|bed': const AlarmState(done: true)});
    }
    return s;
  }

  /// 위젯·단축어·알림 버튼처럼 앱 밖에서 쌓인 탭을 시간순으로 반영한다(되돌리기 없음).
  int applyExternalTaps(List<({Activity activity, DateTime at})> events, {LogSource source = LogSource.widget}) {
    if (events.isEmpty) return 0;
    final tr = _syncedTracker();
    var s = _state;
    var n = 0;
    final sorted = stableSorted(events, (a, b) => a.at.compareTo(b.at));
    for (final e in sorted) {
      final before = tr.current;
      final r = tr.tap(e.activity, e.at, source: source, allowUndo: false);
      if (!r.changed) continue;
      n++;
      s = _commitLogs(s, tr.logs);
      s = _afterTap(s, e.at, e.activity, before, r.ended);
    }
    if (n > 0) _set((_) => s);
    return n;
  }

  bool canUndo() => _tracker != null && identical(_trackerSynced, _state.logs) && _tracker!.canUndo(now());

  bool undoTap() {
    final tr = _syncedTracker();
    if (!tr.undo(now())) return false;
    _set((s) => _commitLogs(s, tr.logs));
    return true;
  }

  void deleteLog(String id) => _set((s) => s.copyWith(logs: s.logs.where((l) => l.id != id).toList()));

  /// 지금 상태를 끝내기만 한다.
  void stopCurrent() {
    final tr = _syncedTracker();
    if (tr.stop(now()) == null) return;
    _set((s) => _commitLogs(s, tr.logs));
  }

  // -------------------------------------------------------------------------
  // 알람
  // -------------------------------------------------------------------------

  /// 지금 울려야 할 알람과 보낼 알림을 찾는다(앱이 열려 있을 때). 기기 알람 예약은 lib/platform이 맡는다.
  ({Ring? ring, List<Nudge> nudges}) dueAlarms([DateTime? at]) {
    final t = at ?? now();
    final s = _state;
    if (!s.onboarded || _recording(s)) return (ring: null, nudges: const []);
    final todayKey = dateKey(t);
    final obs = s.observation;
    final observing = obs != null && todayKey.compareTo(obs.day1) <= 0;
    final tomorrowKey = dateKey(addDays(t, 1));
    final cur = currentLog(s);
    bool ready(String key, DateTime at, int windowMin) {
      final a = s.alarms[key];
      if (a?.done ?? false) return false;
      final until = a?.snoozeUntil;
      if (until != null && t.isBefore(until)) return false;
      return !t.isBefore(at) && diffMin(t, at) < windowMin;
    }

    Ring? ring;
    final today = planFor(s, todayKey, t);
    final wakeKey = '$todayKey|wake';
    if (!observing && wakeRecord(s, todayKey) == null && ready(wakeKey, today.wake, 90)) ring = Ring(kind: RingKind.wake, key: wakeKey, at: today.wake);

    final tomorrow = planFor(s, tomorrowKey, t);
    final bedKey = '$tomorrowKey|bed';
    if (ring == null && cur?.activity != Activity.sleep && ready(bedKey, tomorrow.bedTonight, 60)) {
      ring = Ring(kind: RingKind.bed, key: bedKey, at: tomorrow.bedTonight);
    }

    final nudges = <Nudge>[];
    final windKey = '$tomorrowKey|windDown';
    final windAt = addMin(tomorrow.bedTonight, -s.settings.windDownMinutes);
    if (cur?.activity != Activity.sleep && ready(windKey, windAt, 20)) {
      nudges.add(Nudge(key: windKey, title: '마무리할 시간이에요', body: '${formatHm(tomorrow.bedTonight)} 취침 · 화면을 줄이고 씻을 준비를 해요'));
    }
    for (final b in observing ? const <ScheduleBlock>[] : today.blocks) {
      final before = b.activity == null ? null : s.reminders[b.activity];
      if (before == null || b.kind != BlockKind.habit) continue;
      final key = '$todayKey|remind|${b.id}';
      if (ready(key, addMin(b.start, -before), 10)) {
        nudges.add(Nudge(key: key, title: '$before분 뒤 ${b.title}', body: '${formatHm(b.start)}에 시작해요'));
      }
    }
    return (ring: ring, nudges: nudges);
  }

  void markNudged(List<String> keys) {
    if (keys.isEmpty) return;
    _set((s) => s.copyWith(alarms: {
          ...s.alarms,
          for (final k in keys) k: (s.alarms[k] ?? const AlarmState()).copyWith(done: true),
        }));
  }

  void snooze(Ring ring, int minutes) {
    final t = now();
    _set((s) {
      final a = s.alarms[ring.key] ?? const AlarmState();
      return s.copyWith(alarms: {...s.alarms, ring.key: a.copyWith(snoozes: a.snoozes + 1, snoozeUntil: addMin(t, minutes))});
    });
  }

  /// 기상 알람 끄기 = 기상 기록. 수면 기록이 열려 있으면 함께 끝낸다.
  void dismissWake(Ring ring) {
    final t = now();
    final tr = _syncedTracker();
    ActivityLog? ended;
    if (tr.current?.activity == Activity.sleep) ended = tr.stop(t);
    _set((s) {
      var next = ended != null ? _commitLogs(s, tr.logs) : s;
      final a = next.alarms[ring.key] ?? const AlarmState();
      next = next.copyWith(alarms: {...next.alarms, ring.key: a.copyWith(done: true, snoozeUntil: null)});
      return _recordWake(next, t, WakeSource.alarm, a.snoozes, ended);
    });
  }

  /// 취침 알람: '잘게요'는 수면 시작 기록, '오늘은 끄기'는 알람만 끈다.
  void dismissBed(Ring ring, {required bool sleepNow}) {
    _set((s) => s.copyWith(alarms: {...s.alarms, ring.key: (s.alarms[ring.key] ?? const AlarmState()).copyWith(done: true)}));
    if (sleepNow) tap(Activity.sleep, source: LogSource.alarm);
  }

  AppState _recordWake(AppState s, DateTime t, WakeSource source, int snoozes, ActivityLog? sleepLog) {
    final day = dateKey(t);
    if (wakeRecord(s, day) != null) return s;
    var next = s.copyWith(
      wakes: [...s.wakes, WakeRecord(day: day, at: t, snoozes: snoozes, source: source)],
      alarms: {...s.alarms, '$day|wake': (s.alarms['$day|wake'] ?? AlarmState(snoozes: snoozes)).copyWith(done: true)},
    );
    final end = sleepLog?.end;
    final minutes = sleepLog != null && end != null ? diffMin(end, sleepLog.start) : null;
    next = _coach(next, WakeLogged(sleepMinutes: minutes ?? next.goals.sleepMinutes, recentSnoozes: recentSnoozes(next, day)), t);
    return next;
  }

  // -------------------------------------------------------------------------
  // 코칭
  // -------------------------------------------------------------------------

  final _engine = CoachingEngine();

  AppState _coach(AppState s, CoachEvent event, DateTime t) {
    final day = dateKey(t);
    final obs = s.observation;
    if (obs != null && (obs.phase == ObservationPhase.recording || day.compareTo(obs.day1) <= 0)) return s;
    final today = s.plans[day]?.blocks ?? const <ScheduleBlock>[];
    final shownToday = s.inbox.where((i) => i.kind == InboxKind.coach && i.day == day && i.status == InboxStatus.pending).length;
    final out = _engine.evaluate(event, today: today, now: t, history: s.coachHistory, shownToday: shownToday);
    if (out.isEmpty) return s;
    return s.copyWith(inbox: [
      ...s.inbox,
      for (final sg in out) InboxItem(id: newId('coach'), day: day, createdAt: t, kind: InboxKind.coach, suggestion: sg, message: sg.message),
    ]);
  }

  InboxItem? pendingInbox([DateTime? at]) {
    final day = dateKey(at ?? now());
    return _state.inbox.where((i) => i.status == InboxStatus.pending && i.day == day).firstOrNull;
  }

  InboxItem? recentResolved([DateTime? at]) {
    final day = dateKey(at ?? now());
    return _state.inbox.where((i) => i.day == day && (i.status == InboxStatus.accepted || i.status == InboxStatus.kept)).lastOrNull;
  }

  void acceptSuggestion(String id) {
    final t = now();
    _set((s) {
      final item = s.inbox.where((i) => i.id == id).firstOrNull;
      final sg = item?.suggestion;
      if (item == null || sg == null) return s;
      final r = _applySuggestion(s, sg, t);
      return r.next.copyWith(
        coachHistory: [...r.next.coachHistory, CoachRecord(ruleId: sg.ruleId, at: t, decision: CoachDecision.accepted)],
        inbox: [for (final i in r.next.inbox) i.id == id ? i.copyWith(status: InboxStatus.accepted, resultText: r.text, action: r.action) : i],
      );
    });
  }

  void keepSuggestion(String id) {
    final t = now();
    _set((s) {
      final item = s.inbox.where((i) => i.id == id).firstOrNull;
      if (item == null) return s;
      final sg = item.suggestion;
      return s.copyWith(
        coachHistory: sg != null ? [...s.coachHistory, CoachRecord(ruleId: sg.ruleId, at: t, decision: CoachDecision.rejected)] : s.coachHistory,
        inbox: [
          for (final i in s.inbox)
            i.id == id ? i.copyWith(status: item.kind == InboxKind.info ? InboxStatus.seen : InboxStatus.kept, resultText: '일정을 그대로 둘게요.') : i,
        ],
      );
    });
  }

  ({AppState next, String text, String? action}) _applySuggestion(AppState s, CoachingSuggestion sg, DateTime t) {
    final todayKey = dateKey(t);
    final tomorrowKey = dateKey(addDays(t, 1));
    var next = s;
    var text = '자동 조정했어요.';
    String? action;

    final todayPlan = next.plans[todayKey];
    if (sg.changes.isNotEmpty && todayPlan != null) {
      final applied = applyChanges(todayPlan.blocks, sg.changes);
      next = next.withPlan(todayKey, todayPlan.withPlan(todayPlan.plan.copyWith(blocks: applied.blocks)));
      final ex = applied.blocks.where((b) => b.adjusted && b.activity == Activity.exercise).firstOrNull;
      final parts = <String>[
        if (ex != null) '오늘 운동은 ${formatHm(ex.start)}부터 ${formatDuration(ex.minutes)}이에요',
        if (applied.deferred.isNotEmpty) '집중 작업 ${applied.deferred.length}개는 내일로 넘겼어요',
      ];
      text = '자동 조정했어요. ${parts.join('. ')}.';
    }

    AppState regenTomorrow(AppState x) => x.plans.containsKey(tomorrowKey) ? x.withPlan(tomorrowKey, regeneratePlan(x, tomorrowKey, t)) : x;

    final p = sg.patch;
    var override = next.overrides[tomorrowKey] ?? const DayOverride();
    var overrideChanged = false;
    final dinnerShift = p['tomorrow_dinner_shift_minutes'];
    if (dinnerShift is num) {
      override = override.copyWith(dinnerShift: dinnerShift.round(), notes: [...override.notes, '아침은 가벼운 메뉴로 추천해요']);
      overrideChanged = true;
      final dinner = next.goals.meals.where((m) => m.title.contains('저녁')).firstOrNull;
      text = dinner != null ? '내일 저녁 식사를 ${formatClock(dinner.start.minutes + dinnerShift.round())}으로 앞당겼어요.' : '내일 저녁 식사를 앞당겼어요.';
    }
    if (p['next_meal_focus'] == 'protein') {
      override = override.copyWith(notes: [...override.notes, '첫 끼는 단백질 위주 메뉴로 추천해요']);
      overrideChanged = true;
      text = '내일 첫 끼는 단백질 위주 메뉴로 추천해요.';
    }
    if (overrideChanged) {
      next = regenTomorrow(next.copyWith(overrides: {...next.overrides, tomorrowKey: override}));
    }
    final bedShift = p['bedtime_shift_minutes'];
    if (bedShift is num) {
      final by = -bedShift.round();
      next = regenTomorrow(next.copyWith(settings: next.settings.copyWith(bedEarlierMinutes: next.settings.bedEarlierMinutes + by)).bump());
      final bed = planFor(next, tomorrowKey, t).bedTonight;
      text = '취침 알람을 $by분 앞당겼어요. 오늘 밤 ${formatHm(bed)}이에요.';
    }
    final remind = p['remind_before_minutes'];
    final habit = p['habit'];
    if (remind is num && habit is String) {
      next = next.copyWith(reminders: {...next.reminders, Activity.fromName(habit): remind.round()});
      text = '${remind.round()}분 전에 알림으로 알려드릴게요.';
    }
    if (p['suggest_move'] == true) {
      text = '설정의 습관 시간에서 옮길 시각을 골라주세요.';
      action = 'settings';
    }
    if (p['hold_correction_week'] == true) {
      final c = next.correction;
      if (c != null) next = next.copyWith(correction: c.copyWith(holdNext: true));
      text = '다음 주는 교정 단계를 그대로 두고 수면부터 지켜요.';
    }
    final moveHabit = p['move_habit'];
    final start = p['start'];
    if (moveHabit is String && start is num) {
      final g = next.goals;
      final st = ClockTime(start.round());
      final ex = g.exercise;
      next = regenTomorrow(next
          .copyWith(
            goals: g.copyWith(
              meals: [for (final m in g.meals) m.title == moveHabit ? m.copyWith(start: st) : m],
              exercise: ex != null && ex.title == moveHabit ? ex.copyWith(start: st) : ex,
            ),
          )
          .bump());
      text = '$moveHabit${objectParticle(moveHabit)} ${formatClock(st.minutes)}으로 옮겼어요. 내일 일정부터 반영해요.';
    }
    final shrink = p['shrink_to_minutes'];
    final ex = next.goals.exercise;
    if (shrink is num && habit == 'exercise' && ex != null) {
      next = next.copyWith(goals: next.goals.copyWith(exercise: ex.copyWith(minutes: shrink.round()))).bump();
      text = '운동을 ${shrink.round()}분으로 줄였어요. 다음 일정부터 반영해요.';
    }
    return (next: next, text: text, action: action);
  }

  // -------------------------------------------------------------------------
  // 저녁 확인
  // -------------------------------------------------------------------------

  static String _eveningLogId(String blockId) => 'ev-$blockId';

  AppState _clearMarks(AppState s, String day, ScheduleBlock b) {
    final credit = s.credits.where((c) => c.blockId == b.id).firstOrNull;
    return s.copyWith(
      logs: s.logs.where((l) => l.id != _eveningLogId(b.id)).toList(),
      misses: s.misses.where((m) => !(m.day == day && m.blockId == b.id)).toList(),
      skips: s.skips.where((m) => !(m.day == day && m.blockId == b.id)).toList(),
      credits: s.credits.where((c) => c.blockId != b.id).toList(),
      tasks: credit == null
          ? s.tasks
          : [for (final t in s.tasks) t.id == credit.taskId ? t.copyWith(doneMinutes: math.max(0, t.doneMinutes - credit.minutes), done: false) : t],
    );
  }

  AppState _credit(AppState s, String day, ScheduleBlock b) {
    final taskId = b.taskId;
    if (taskId == null || s.credits.any((c) => c.blockId == b.id)) return s;
    final minutes = b.minutes;
    return s.copyWith(
      credits: [...s.credits, TaskCredit(day: day, blockId: b.id, taskId: taskId, minutes: minutes)],
      tasks: [for (final t in s.tasks) t.id == taskId ? t.copyWith(doneMinutes: t.doneMinutes + minutes) : t],
    );
  }

  void markDid(String day, ScheduleBlock b) {
    _set((s) {
      var next = _clearMarks(s, day, b);
      final log = ActivityLog(id: _eveningLogId(b.id), activity: b.activity ?? Activity.work, start: b.start, end: b.end, source: LogSource.evening);
      next = _commitLogs(next, stableSorted([...next.logs, log], (a, c) => a.start.compareTo(c.start)));
      return _credit(next, day, b);
    });
  }

  void markMissed(String day, ScheduleBlock b, MissReason reason) {
    final t = now();
    _set((s) {
      var next = _clearMarks(s, day, b);
      final activity = b.activity ?? Activity.work;
      next = next.copyWith(misses: [...next.misses, MissMark(day: day, blockId: b.id, activity: activity, reason: reason, at: t)]);
      final week = weekKeys(fromKey(day));
      final weekCount = next.misses.where((m) => m.activity == activity && m.reason == reason && week.contains(m.day)).length;
      return _coach(next, MissReasonAdded(habit: activity, reason: reason, weekCount: weekCount, habitMinutes: b.minutes), t);
    });
  }

  void markSkipped(String day, ScheduleBlock b) {
    _set((s) {
      final next = _clearMarks(s, day, b);
      return next.copyWith(skips: [...next.skips, SkipMark(day: day, blockId: b.id)]);
    });
  }

  void clearAnswer(String day, ScheduleBlock b) => _set((s) => _clearMarks(s, day, b));

  void setRestDay(String day, bool rest) {
    _set((s) => s.copyWith(restDays: rest ? {...s.restDays, day}.toList() : s.restDays.where((d) => d != day).toList()));
  }

  /// 저녁 확인 끝: 달성한 할 일 반영, 식사 코칭(R5), 내일 일정 확정.
  void finishEvening(String day) {
    final t = now();
    _set((s) {
      var next = s;
      final view = evaluate(next, day, t);
      for (final o in view.outcomes) {
        if (o.block.kind == BlockKind.task && o.outcome == Outcome.achieved) next = _credit(next, day, o.block);
      }
      final missedMeals = view.outcomes.where((o) => o.block.activity == Activity.meal && o.outcome == Outcome.missed).length;
      next = _coach(next, EveningCheck(missedMeals: missedMeals), t);
      final obs = next.observation;
      if (obs != null && obs.phase == ObservationPhase.trial && obs.day2 == day) next = _endObservation(next, day, t);
      if (day == dateKey(t)) next = _lockTomorrow(next, t);
      return next.copyWith(eveningDone: {...next.eveningDone, day}.toList());
    });
  }

  // -------------------------------------------------------------------------
  // 할 일·캘린더가 바뀌면 오늘 남은 일정과 확정한 내일 일정을 바로 다시 짠다(되돌리기 15초).
  // -------------------------------------------------------------------------

  /// 저장해 둔 오늘·내일 일정을 지금 입력으로 다시 짠다. 첫날 기록 중에는 짜지 않는다.
  AppState _replan(AppState s, DateTime t) {
    if (!s.onboarded || _recording(s)) return s;
    var next = s;
    for (final key in [dateKey(t), dateKey(addDays(t, 1))]) {
      if (next.plans.containsKey(key)) next = next.withPlan(key, regeneratePlan(next, key, t));
    }
    return next;
  }

  /// 할 일 조각이 실제로 바뀌었는지 비교할 지문.
  String _taskSig(AppState s, DateTime t) => [dateKey(t), dateKey(addDays(t, 1))]
      .map((k) => (s.plans[k]?.blocks ?? const <ScheduleBlock>[])
          .where((b) => b.kind == BlockKind.task && b.end.isAfter(t))
          .map((b) => '${b.taskId}@${b.start.millisecondsSinceEpoch}-${b.end.millisecondsSinceEpoch}')
          .join(','))
      .join('|');

  Set<String> _deferredIds(AppState s, DateTime t) => {for (final d in s.plans[dateKey(t)]?.plan.deferred ?? const []) d.taskId};

  ({AppState state, DateTime at})? _planUndo;

  PlanChange _changeAndReplan(AppState Function(AppState s, DateTime t) fn) {
    final t = now();
    final before = _state;
    final next = _replan(fn(_state, t), t);
    final replanned = _taskSig(before, t) != _taskSig(next, t);
    final was = _deferredIds(before, t);
    final deferred = [
      for (final id in _deferredIds(next, t))
        if (!was.contains(id)) next.tasks.where((x) => x.id == id).firstOrNull?.title ?? '할 일',
    ];
    _set((_) => next);
    _planUndo = (state: before, at: _wall());
    return PlanChange(replanned: replanned, deferred: deferred);
  }

  bool canUndoPlan() {
    final u = _planUndo;
    return u != null && _wall().difference(u.at) < planUndoWindow;
  }

  /// 방금 바꾼 할 일·캘린더와 그에 따라 다시 짠 일정을 함께 되돌린다.
  bool undoPlanChange() {
    if (!canUndoPlan()) return false;
    replaceState(_planUndo!.state);
    _planUndo = null;
    return true;
  }

  PlanChange saveTask(TaskItem task) => _changeAndReplan((s, t) {
        final exists = s.tasks.any((x) => x.id == task.id);
        return s
            .copyWith(
              tasks: exists ? [for (final x in s.tasks) x.id == task.id ? task : x] : [...s.tasks, task],
              metrics: exists ? s.metrics : addEvent(s.metrics, t, 'task_add'),
            )
            .bump();
      });

  /// 지금까지 그 할 일에 쓴 시간(사실만): 반영한 조각 + 오늘 일정에서 이미 지났거나 진행 중인 조각.
  int spentMinutes(AppState s, TaskItem task, DateTime t) {
    final credited = {for (final c in s.credits) c.blockId};
    final missed = {for (final m in s.misses) if (m.day == dateKey(t)) m.blockId};
    var m = task.doneMinutes;
    for (final b in s.plans[dateKey(t)]?.blocks ?? const <ScheduleBlock>[]) {
      if (b.kind != BlockKind.task || b.taskId != task.id || credited.contains(b.id) || missed.contains(b.id) || !b.start.isBefore(t)) continue;
      m += diffMin(b.end.isBefore(t) ? b.end : t, b.start);
    }
    return m;
  }

  PlanChange toggleTaskDone(String id) => _changeAndReplan((s, t) {
        final open = s.tasks.where((x) => !x.done).toList();
        final idx = open.indexWhere((x) => x.id == id);
        final task = s.tasks.where((x) => x.id == id).firstOrNull;
        var learning = s.learning;
        var durations = s.durations;
        if (task != null && !task.done) {
          // 끝낸 일과 그 일이 목록에서 몇 번째였는지 배운다.
          if (idx >= 0 && open.length > 1) {
            final created = task.createdAt;
            final age = created == null ? 0.0 : t.difference(created).inMilliseconds / 86400000;
            final list = [...learning.completions, Completion(at: t, type: task.type, est: task.estMinutes, age: age, pos: idx / (open.length - 1))];
            learning = learning.copyWith(completions: list.length > 200 ? list.sublist(list.length - 200) : list);
          }
          // 예상 대비 실제로 쓴 시간을 남긴다(알 수 없으면 남기지 않는다).
          durations = addSample(
              durations, DurationSample(at: t, taskId: task.id, type: task.type, title: task.title, est: task.estMinutes, actual: spentMinutes(s, task, t)));
        } else if (task != null && task.done) {
          // 완료를 취소하면 그 기록도 지운다.
          durations = durations.copyWith(samples: durations.samples.where((x) => x.taskId != id).toList());
        }
        return s.copyWith(learning: learning, durations: durations, tasks: [for (final x in s.tasks) x.id == id ? x.copyWith(done: !x.done) : x]).bump();
      });

  /// 잡은 시간을 다 썼는데 덜 끝났을 때: 시간을 늘려 다시 배치한다.
  PlanChange extendTask(String id, int minutes) =>
      _changeAndReplan((s, _) => s.copyWith(tasks: [for (final x in s.tasks) x.id == id ? x.copyWith(extraMinutes: x.extraMinutes + minutes) : x]).bump());

  /// 일정에 잡을 시간(보정 + 늘린 시간)과 남은 시간.
  ({int planned, int remaining}) taskPlanMinutes(TaskItem t) {
    final planned = plannedMinutes(t, _state.durations);
    return (planned: planned, remaining: math.max(0, planned - t.doneMinutes));
  }

  PlanChange setDurationAuto(bool on) => _changeAndReplan((s, _) => s.copyWith(durations: s.durations.copyWith(on: on)).bump());

  /// 끌어서 바꾼 순서를 저장한다(진행 중인 할 일만, 완료한 일은 뒤에 그대로). byUser면 학습 기록에도 남긴다.
  PlanChange reorderTasks(List<String> ids, {bool byUser = true}) => _changeAndReplan((s, t) {
        final byId = {for (final x in s.tasks) x.id: x};
        final ordered = [for (final id in ids) if (byId[id] != null) byId[id]!];
        final rest = s.tasks.where((x) => !ids.contains(x.id)).toList();
        var learning = s.learning;
        if (byUser) {
          final list = [...learning.reorders, snapshot(ordered, t)];
          learning = learning.copyWith(reorders: list.length > 200 ? list.sublist(list.length - 200) : list);
        }
        return s.copyWith(tasks: [...ordered, ...rest], learning: learning).bump();
      });

  /// AI 추천을 오늘은 넘긴다.
  void dismissOrderSuggestion() {
    final day = dateKey(now());
    _set((s) => s.copyWith(learning: s.learning.copyWith(dismissedDay: day)));
  }

  PlanChange deleteTask(String id) => _changeAndReplan((s, _) => s.copyWith(tasks: s.tasks.where((t) => t.id != id).toList()).bump());

  /// 캘린더 일정 저장. 첫 일정이면 이동 시간도 함께 받는다(필요한 순간에 한 번만 묻기).
  PlanChange saveEvent(FixedEvent e, {int? travelMinutes}) => _changeAndReplan((s, _) {
        final exists = s.events.any((x) => x.id == e.id);
        var next = s.copyWith(events: exists ? [for (final x in s.events) x.id == e.id ? e : x] : [...s.events, e]).bump();
        if (travelMinutes != null) {
          next = next.copyWith(settings: next.settings.copyWith(travelMinutes: travelMinutes), asked: next.asked.copyWith(travel: true));
        }
        return next;
      });

  PlanChange deleteEvent(String id) => _changeAndReplan((s, _) => s.copyWith(events: s.events.where((e) => e.id != id).toList()).bump());

  // -------------------------------------------------------------------------
  // 외부 캘린더 가져오기(.ics 파일, 기기 캘린더)
  // -------------------------------------------------------------------------

  /// 가져올 범위: 오늘 0시부터 14일.
  ({DateTime from, DateTime to}) importWindow([DateTime? at]) {
    final from = dayStart(at ?? now());
    return (from: from, to: addDays(from, 14));
  }

  static String _noSpace(String s) => s.replaceAll(RegExp(r'\s+'), '');
  static bool _sameEvent(String at, DateTime as, DateTime ae, String bt, DateTime bs, DateTime be) =>
      _noSpace(at) == _noSpace(bt) && as.difference(bs).inMilliseconds.abs() < 60000 && ae.difference(be).inMilliseconds.abs() < 60000;

  /// 그 캘린더에서 가져온 일정을 통째로 바꾸고 남은 일정을 다시 짠다.
  ImportOutcome importCalendar(List<ImportedEvent> events, {required String id, required CalendarKind kind, required String name}) {
    var count = 0, dupes = 0, capped = 0;
    final r = _changeAndReplan((s, t) {
      final others = s.events.where((e) => e.source != id).toList();
      final fresh = events.where((e) {
        final dup = others.any((o) => _sameEvent(o.title, o.start, o.end, e.title, e.start, e.end));
        if (dup) dupes++;
        return !dup;
      }).toList();
      capped = math.max(0, fresh.length - maxImport);
      final mine = [
        for (final e in fresh.take(maxImport)) FixedEvent(id: '$id:${e.uid}@${e.start.millisecondsSinceEpoch}', title: e.title, start: e.start, end: e.end, source: id),
      ];
      count = mine.length;
      final sources = [...s.calendars.where((c) => c.id != id), CalendarSource(id: id, kind: kind, name: name, lastSync: t, count: count)];
      return s.copyWith(events: [...others, ...mine], calendars: sources).bump();
    });
    return ImportOutcome(replanned: r.replanned, deferred: r.deferred, count: count, dupes: dupes, capped: capped);
  }

  /// 동기화 실패를 남긴다. 이전에 가져온 일정은 그대로 두고 그것으로 계속 짠다.
  void markCalendarError(String id, String? error, {bool needsAuth = false}) {
    _set((s) => s.copyWith(calendars: [for (final c in s.calendars) c.id == id ? c.copyWith(error: error, needsAuth: needsAuth) : c]));
  }

  /// 가져온 캘린더 연결을 끊고 그 일정을 지운다.
  PlanChange removeCalendar(String id) => _changeAndReplan(
      (s, _) => s.copyWith(events: s.events.where((e) => e.source != id).toList(), calendars: s.calendars.where((c) => c.id != id).toList()).bump());

  void updateGoals(HabitGoals goals) => _set((s) => s.copyWith(goals: goals).bump());

  void updateSettings(PersonalSettings settings) => _set((s) => s.copyWith(settings: settings).bump());

  CorrectionState _newCorrection(int baseline, int target, DateTime t, [int stepSize = 30]) => CorrectionState(
        plan: CorrectionPlan.create(baseline: baseline, target: target, stepSize: stepSize),
        lastUpdateWeek: dateKey(mondayOf(t)),
      );

  /// 기상 교정 계획을 만든다. 지금 기상과 목표가 30분 이상 차이 나면 단계로 나눈다.
  void setCorrection(int? usualWake, [int stepSize = 30]) {
    final t = now();
    _set((s) {
      if (usualWake == null || (usualWake - s.goals.wake.minutes).abs() <= 30) return s.copyWith(correction: null).bump();
      return s.copyWith(correction: _newCorrection(usualWake, s.goals.wake.minutes, t, stepSize)).bump();
    });
  }

  void completeOnboarding({required HabitGoals goals, required PersonalSettings settings, int? usualWake}) {
    final t = now();
    var s = _carryOver(_state, AppState.initial(now: t)).copyWith(onboarded: true, goals: goals, settings: settings);
    if (usualWake != null && (usualWake - goals.wake.minutes).abs() > 30) {
      s = s.copyWith(correction: _newCorrection(usualWake, goals.wake.minutes, t));
    }
    replaceState(s);
    ensureDay(t);
  }

  void resetAll() => replaceState(AppState.initial(now: now()));

  /// 시연용 예시 데이터로 바꾼다(지금 데이터는 따로 보관한다).
  void loadDemo(AppState demo) {
    storage.keepCopy(serialize(_state), KeptReason.beforeImport);
    replaceState(demo);
  }

  /// 처음 화면에서 정한 것(목표·동의·알림)과 익명 번호·지표는 시작할 때 그대로 가져간다.
  AppState _carryOver(AppState from, AppState base) =>
      base.copyWith(profile: from.profile, intent: from.intent, consent: from.consent, notify: from.notify, metrics: _firstTouch(from, now()));

  /// 처음 무언가를 한 시각을 설치 시각으로 둔다(앱 시계 기준).
  MetricsLog _firstTouch(AppState s, DateTime t) => s.metrics.events.isNotEmpty || s.metrics.opens.isNotEmpty ? s.metrics : s.metrics.copyWith(installAt: t);

  // -------------------------------------------------------------------------
  // 처음 목표 · 동의 · 알림 · 일정 체크 · 지표 · 피드백
  // -------------------------------------------------------------------------

  void setIntent({required List<GoalFocus> focus, required int wake, required int sleepMinutes, required int exerciseMinutes}) {
    final t = now();
    _set((s) {
      // 고른 목표를 기본 목표에도 바로 반영한다(기록 없이 바로 설정하는 길에서도 쓰도록).
      var goals = s.goals.copyWith(wake: ClockTime(wake), sleepMinutes: sleepMinutes);
      if (focus.contains(GoalFocus.exercise)) {
        final ex = s.goals.exercise ?? defaultGoals.exercise!;
        goals = goals.copyWith(exercise: ex.copyWith(minutes: exerciseMinutes));
      }
      return s.copyWith(
        goals: goals,
        intent: GoalIntent(focus: focus, wake: wake, sleepMinutes: sleepMinutes, exerciseMinutes: exerciseMinutes, setAt: t),
        metrics: addEvent(_firstTouch(s, t), t, 'goal_set', focus.map((f) => f.name).join(',')),
      );
    });
  }

  void setConsent({required bool health, required bool metrics}) {
    final t = now();
    _set((s) => s.copyWith(
          consent: Consent(health: health, metrics: metrics, at: t),
          metrics: addEvent(_firstTouch(s, t), t, 'consent', metrics ? 'metrics' : 'health'),
        ));
  }

  void setNotify(NotifyPrefs Function(NotifyPrefs n) fn) => _set((s) => s.copyWith(notify: fn(s.notify)));

  /// 일정 체크에서 '지금은 안 해요': 그 조각은 다시 묻지 않는다.
  void skipCheck(String id) {
    final t = now();
    _set((s) {
      final list = [...s.checkSkips.where((x) => x != id), id];
      return s.copyWith(checkSkips: list.length > 60 ? list.sublist(list.length - 60) : list, metrics: addEvent(s.metrics, t, 'check_skip'));
    });
  }

  /// 베타 지표에 행동 하나를 남긴다(내용·제목은 남기지 않는다).
  void track(String k, [String? v]) {
    final t = now();
    _set((s) => s.copyWith(metrics: addEvent(s.metrics, t, k, v)));
  }

  /// 오늘 앱을 열었음을 남긴다(하루 한 번).
  void markOpen([DateTime? at]) {
    final t = at ?? now();
    if (_state.metrics.opens.contains(dateKey(t))) return;
    _set((s) => s.copyWith(metrics: addOpen(s.metrics, t)));
  }

  void answerSurvey({required String key, required String answer, String? best, String? worst}) {
    final t = now();
    _set((s) => s.copyWith(
          feedback: s.feedback.copyWith(surveys: [
            ...s.feedback.surveys.where((x) => x.key != key),
            SurveyAnswer(key: key, answer: answer, best: best, worst: worst, at: t),
          ]),
        ));
  }

  void surveyLater() {
    final day = dateKey(now());
    _set((s) => s.copyWith(feedback: s.feedback.copyWith(surveyLater: day)));
  }

  void addReport({required String kind, required String text, required String page}) {
    final t = now();
    _set((s) {
      final list = [...s.feedback.reports, FeedbackReport(at: t, kind: kind, text: text.length > 1000 ? text.substring(0, 1000) : text, page: page)];
      return s.copyWith(feedback: s.feedback.copyWith(reports: list.length > 50 ? list.sublist(list.length - 50) : list));
    });
  }

  // -------------------------------------------------------------------------
  // 2일 관찰
  // -------------------------------------------------------------------------

  /// 설정 없이 시작: 1일차는 기록만 한다. 오후 3시 이후에 시작하면 다음 날이 1일차다.
  void startObservation() {
    final t = now();
    final day1 = t.hour >= 15 ? dateKey(addDays(t, 1)) : dateKey(t);
    replaceState(_carryOver(_state, AppState.initial(now: t)).copyWith(
      onboarded: true,
      observation: Observation(phase: ObservationPhase.recording, day1: day1, startedAt: t),
    ));
  }

  /// 1일차 기록을 보고 바꿀 것만 고친 뒤 2일차 일정을 만든다.
  /// [recordedWake]: 1일차에 실제로 일어난 시각. 목표와 30분 넘게 차이 나면 단계적으로 옮긴다.
  void completeObservation({required HabitGoals goals, required PersonalSettings settings, int? recordedWake}) {
    final t = now();
    _set((s) {
      final obs = s.observation;
      if (obs == null) return s;
      final day2 = dateKey(addDays(fromKey(obs.day1), 1));
      var next = s.copyWith(
        goals: goals,
        settings: settings,
        correction: recordedWake != null && (recordedWake - goals.wake.minutes).abs() > 30 ? _newCorrection(recordedWake, goals.wake.minutes, t) : null,
      ).bump();
      next = next.copyWith(observation: obs.copyWith(phase: ObservationPhase.trial, day2: day2), eveningDone: {...next.eveningDone, obs.day1}.toList());
      final todayKey = dateKey(t);
      // 1일차 밤에 정리하면 2일차 일정을, 다음 날 정리하면 오늘 남은 일정을 만든다.
      final key = todayKey.compareTo(day2) >= 0 ? todayKey : day2;
      final plan = key == todayKey ? buildPlan(next, key, notBefore: t) : buildPlan(next, key);
      return next.withPlan(key, storedFrom(plan, next));
    });
  }

  /// 2일차 저녁: 정한 시각과 실제가 20분 넘게 어긋난 습관만 다시 묻고 관찰을 끝낸다.
  AppState _endObservation(AppState s, String day, DateTime t) {
    final view = evaluate(s, day, t);
    final items = <InboxItem>[];
    for (final b in view.plan.blocks) {
      if (b.kind != BlockKind.habit || b.activity == null || b.activity == Activity.sleep) continue;
      final logs = s.logs.where((l) => l.activity == b.activity && l.source != LogSource.evening && diffMin(l.start, b.start).abs() <= 120).toList();
      if (logs.isEmpty) continue;
      final actual = logs.reduce((a, c) => diffMin(c.start, b.start).abs() < diffMin(a.start, b.start).abs() ? c : a);
      final drift = diffMin(actual.start, b.start);
      if (drift.abs() < 20) continue;
      final start = ((actual.start.hour * 60 + actual.start.minute) / 5).round() * 5;
      final title = b.title;
      final message = '$title${objectParticle(title)} ${formatHm(b.start)}으로 정했는데 오늘은 ${formatHm(actual.start)}에 시작했어요. ${formatClock(start)}으로 옮길까요?';
      items.add(InboxItem(
        id: newId('obs'),
        day: day,
        createdAt: t,
        kind: InboxKind.coach,
        message: message,
        suggestion: CoachingSuggestion(ruleId: 'OBS', message: message, patch: {'move_habit': title, 'start': start}),
      ));
    }
    items.add(InboxItem(
      id: newId('info'),
      day: day,
      createdAt: t,
      kind: InboxKind.info,
      message: '이틀 관찰이 끝났어요. 이제 매일 밤 내일 일정과 알람을 자동으로 짜요.',
    ));
    final obs = s.observation;
    return s.copyWith(observation: obs?.copyWith(phase: ObservationPhase.done), inbox: [...s.inbox, ...items]);
  }

  /// 한 번만 보여 주는 안내를 봤다고 기록한다.
  void markAsked(Asked Function(Asked a) fn) => _set((s) => s.copyWith(asked: fn(s.asked)));

  // -------------------------------------------------------------------------
  // 친구와 겨루기
  // -------------------------------------------------------------------------

  void setProfileName(String name) {
    final n = name.trim();
    _set((s) => s.copyWith(profile: s.profile.copyWith(name: n.length > 12 ? n.substring(0, 12) : n)));
  }

  /// 친구 코드로 받은 기록을 넣는다. 같은 친구면 새 기록으로 바꾼다. 내 코드는 넣지 않는다.
  AddResult addFriend(Friend f) {
    if (f.id == _state.profile.id) return AddResult.self;
    final exists = _state.friends.any((x) => x.id == f.id);
    _set((s) => s.copyWith(friends: exists ? [for (final x in s.friends) x.id == f.id ? f : x] : [...s.friends, f]));
    return exists ? AddResult.updated : AddResult.added;
  }

  void removeFriend(String id) => _set((s) => s.copyWith(friends: s.friends.where((f) => f.id != id).toList()));

  // -------------------------------------------------------------------------
  // 근처 익명 보드
  // -------------------------------------------------------------------------

  void setNearbyOn(bool on, {String? cell}) {
    final t = now();
    _set((s) {
      var n = s.nearby.copyWith(on: on);
      if (cell != null) n = n.copyWith(cell: cell, cellAt: t);
      if (!on) n = n.copyWith(cell: null, cellAt: null);
      return s.copyWith(nearby: n);
    });
  }

  /// 가까운 사람의 익명 코드를 받아 근처 보드에 올린다.
  AddResult addNearby(Friend f) {
    if (f.id == _state.profile.id) return AddResult.self;
    final exists = _state.nearby.people.any((x) => x.id == f.id);
    _set((s) => s.copyWith(
          nearby: s.nearby.copyWith(people: exists ? [for (final x in s.nearby.people) x.id == f.id ? f : x] : [...s.nearby.people, f]),
        ));
    return exists ? AddResult.updated : AddResult.added;
  }

  void removeNearby(String id) => _set((s) => s.copyWith(nearby: s.nearby.copyWith(people: s.nearby.people.where((p) => p.id != id).toList())));
}
