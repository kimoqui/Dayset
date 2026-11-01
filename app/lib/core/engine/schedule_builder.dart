import '../model/models.dart';

/// 다음 날 일정 생성 입력. 엔진·규칙 명세 1번.
class DayPlanInput {
  const DayPlanInput({
    required this.date,
    required this.goals,
    this.settings = const PersonalSettings(),
    this.fixedEvents = const [],
    this.lockedBlocks = const [],
    this.tasks = const [],
    this.notBefore,
  });

  /// 하루 중간에 다시 짤 때: 할 일은 이 시각 이후에만 넣는다.
  final DateTime? notBefore;

  /// 일정을 만들 날짜(시각은 무시한다).
  final DateTime date;
  final HabitGoals goals;
  final PersonalSettings settings;
  final List<FixedEvent> fixedEvents;
  final List<ScheduleBlock> lockedBlocks;
  final List<TaskItem> tasks;
}

/// 오늘 넣지 못하고 다음 날로 넘긴 할 일.
class DeferredTask {
  const DeferredTask({required this.taskId, required this.minutes, required this.reason});

  final String taskId;
  final int minutes;
  final DeferReason reason;

  Map<String, Object?> toJson() => {'taskId': taskId, 'minutes': minutes, 'reason': reason.name};

  factory DeferredTask.fromJson(Map<String, Object?> j) => DeferredTask(
        taskId: j['taskId'] as String,
        minutes: (j['minutes'] as num).round(),
        reason: j['reason'] == 'noSlot' ? DeferReason.noSlot : DeferReason.budget,
      );
}

enum DeferReason {
  /// 빈 시간의 75%를 이미 채움.
  budget,

  /// 마감 전에 들어갈 빈 시간이 없음.
  noSlot,
}

class DayPlan {
  const DayPlan({
    required this.date,
    required this.wake,
    required this.bedTonight,
    required this.dayEnd,
    required this.blocks,
    required this.alarms,
    required this.deferred,
    required this.notes,
    required this.freeMinutes,
    required this.taskMinutes,
  });

  final DateTime date;

  /// 그 날 기상 알람 시각.
  final DateTime wake;

  /// 전날 밤 취침 알람 시각.
  final DateTime bedTonight;

  /// 그 날 밤 취침 예정(하루 일정의 끝).
  final DateTime dayEnd;

  /// 시작 시각 순으로 정렬된 블록. 첫 블록은 전날 밤 수면이다.
  final List<ScheduleBlock> blocks;
  final List<PlannedAlarm> alarms;
  final List<DeferredTask> deferred;

  /// 사용자에게 보여줄 안내(예: 겹쳐서 뺀 습관).
  final List<String> notes;

  /// 할 일을 넣기 전 빈 시간 합계(분).
  final int freeMinutes;

  /// 실제로 배치한 할 일 시간(분).
  final int taskMinutes;

  DayPlan copyWith({
    DateTime? wake,
    DateTime? bedTonight,
    List<ScheduleBlock>? blocks,
    List<PlannedAlarm>? alarms,
    List<DeferredTask>? deferred,
    List<String>? notes,
  }) =>
      DayPlan(
        date: date,
        wake: wake ?? this.wake,
        bedTonight: bedTonight ?? this.bedTonight,
        dayEnd: dayEnd,
        blocks: blocks ?? this.blocks,
        alarms: alarms ?? this.alarms,
        deferred: deferred ?? this.deferred,
        notes: notes ?? this.notes,
        freeMinutes: freeMinutes,
        taskMinutes: taskMinutes,
      );

  Map<String, Object?> toJson() => {
        'date': encodeDate(date),
        'wake': encodeDate(wake),
        'bedTonight': encodeDate(bedTonight),
        'dayEnd': encodeDate(dayEnd),
        'blocks': [for (final b in blocks) b.toJson()],
        'alarms': [for (final a in alarms) a.toJson()],
        'deferred': [for (final d in deferred) d.toJson()],
        'notes': notes,
        'freeMinutes': freeMinutes,
        'taskMinutes': taskMinutes,
      };

  factory DayPlan.fromJson(Map<String, Object?> j) => DayPlan(
        date: decodeDate(j['date'])!,
        wake: decodeDate(j['wake'])!,
        bedTonight: decodeDate(j['bedTonight'])!,
        dayEnd: decodeDate(j['dayEnd'])!,
        blocks: [for (final b in (j['blocks'] as List? ?? const [])) ScheduleBlock.fromJson((b as Map).cast<String, Object?>())],
        alarms: [for (final a in (j['alarms'] as List? ?? const [])) PlannedAlarm.fromJson((a as Map).cast<String, Object?>())],
        deferred: [for (final d in (j['deferred'] as List? ?? const [])) DeferredTask.fromJson((d as Map).cast<String, Object?>())],
        notes: [for (final n in (j['notes'] as List? ?? const [])) n as String],
        freeMinutes: (j['freeMinutes'] as num? ?? 0).round(),
        taskMinutes: (j['taskMinutes'] as num? ?? 0).round(),
      );
}

class _Gap {
  _Gap(this.start, this.end);
  DateTime start;
  DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

/// 하루 일정 엔진. 엔진·규칙 명세 2번과 3번을 구현한다.
///
/// - 기상 = min(목표 기상, 첫 고정 일정 − 준비 − 이동)
/// - 오늘 취침 = 내일 기상 − 목표 수면 − 잠들기까지 걸리는 시간
/// - 할 일은 빈 시간의 75%까지만, 최대 50분 조각 + 10분 휴식으로 넣는다.
class ScheduleBuilder {
  const ScheduleBuilder();

  /// 예전 이름. [buildDay]와 같다.
  DayPlan buildTomorrow(DayPlanInput input) => buildDay(input);

  DayPlan buildDay(DayPlanInput input) {
    final day = DateTime(input.date.year, input.date.month, input.date.day);
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    final s = input.settings;
    final g = input.goals;
    var seq = 0;
    String nid(String prefix) => '$prefix-${++seq}';

    final fixed = input.fixedEvents.where((e) => _sameDay(e.start, day)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // 1) 기상과 취침
    var wake = g.wake.on(day);
    var wakeReason = '목표 기상 ${formatClock(g.wake.minutes)}';
    if (fixed.isNotEmpty) {
      final latest = fixed.first.start
          .subtract(Duration(minutes: s.prepMinutes + s.travelMinutes));
      if (latest.isBefore(wake)) {
        wake = latest;
        wakeReason = '첫 일정 ${formatHm(fixed.first.start)} − 준비 ${s.prepMinutes}분'
            ' − 이동 ${s.travelMinutes}분';
      }
    }
    final sleepTotal = g.sleepMinutes + s.sleepLatencyMinutes + s.bedEarlierMinutes;
    final bedTonight = wake.subtract(Duration(minutes: sleepTotal));
    final dayEnd = g.wake.on(nextDay).subtract(Duration(minutes: sleepTotal));

    // 2) 움직일 수 없는 블록
    final blocks = <ScheduleBlock>[
      ScheduleBlock(
        id: nid('sleep'),
        kind: BlockKind.habit,
        activity: Activity.sleep,
        title: '수면',
        start: bedTonight,
        end: wake,
      ),
    ];
    if (fixed.isNotEmpty && s.travelMinutes > 0) {
      final first = fixed.first.start;
      blocks.add(ScheduleBlock(
        id: nid('travel'),
        kind: BlockKind.fixed,
        title: '이동',
        start: first.subtract(Duration(minutes: s.travelMinutes)),
        end: first,
      ));
    }
    for (final e in fixed) {
      blocks.add(ScheduleBlock(
        id: nid('event'),
        kind: BlockKind.fixed,
        title: e.title,
        start: e.start,
        end: e.end,
        locked: true,
      ));
    }
    blocks.addAll(input.lockedBlocks.where((b) => _sameDay(b.start, day)));

    // 3) 습관 뼈대(식사·운동). 겹치면 2시간 안에서 뒤로 민다.
    final notes = <String>[];
    final habits = [...g.meals, if (g.exercise != null) g.exercise!];
    for (final h in habits) {
      final placed = _placeHabit(h.start.on(day), h.minutes, blocks, dayEnd);
      if (placed == null) {
        notes.add('${h.title}: 겹치는 일정이 있어 넣지 못했어요');
        continue;
      }
      blocks.add(ScheduleBlock(
        id: nid('habit'),
        kind: BlockKind.habit,
        activity: h.activity,
        title: h.title,
        start: placed,
        end: placed.add(Duration(minutes: h.minutes)),
      ));
    }

    // 4) 빈 시간 계산. 할 일은 기상 후 준비 시간이 지난 뒤부터, 취침 준비 전까지.
    var windowStart = wake.add(Duration(minutes: s.prepMinutes));
    final nb = input.notBefore;
    if (nb != null && nb.isAfter(windowStart)) windowStart = nb;
    final windowEnd = dayEnd.subtract(Duration(minutes: s.windDownMinutes));
    final gaps = _gaps(blocks, windowStart, windowEnd);
    final freeMinutes = gaps.fold<int>(0, (sum, x) => sum + x.minutes);
    final budget = (freeMinutes * s.fillRatio).floor();

    // 5) 할 일 배치: 사용자가 정한 순서(rank) → 마감 → 우선순위 순.
    final tasks = [...input.tasks]..sort((a, b) {
        final ra = a.rank, rb = b.rank;
        if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
        final d = a.dueAt.compareTo(b.dueAt);
        return d != 0 ? d : a.priority.index.compareTo(b.priority.index);
      });
    final deferred = <DeferredTask>[];
    var used = 0;
    for (final t in tasks) {
      var remaining = t.remainingMinutes;
      while (remaining > 0) {
        final chunk = remaining < s.chunkMinutes ? remaining : s.chunkMinutes;
        if (used + chunk > budget) {
          deferred.add(DeferredTask(taskId: t.id, minutes: remaining, reason: DeferReason.budget));
          break;
        }
        final start = _bestSlot(gaps, chunk, t.dueAt, t.focus ? s : null, day);
        if (start == null) {
          deferred.add(DeferredTask(taskId: t.id, minutes: remaining, reason: DeferReason.noSlot));
          break;
        }
        final end = start.add(Duration(minutes: chunk));
        blocks.add(ScheduleBlock(
          id: nid('task'),
          kind: BlockKind.task,
          activity: Activity.work,
          title: t.title,
          start: start,
          end: end,
          focus: t.focus,
          taskId: t.id,
        ));
        _consume(gaps, start, end.add(Duration(minutes: s.restMinutes)));
        used += chunk;
        remaining -= chunk;
      }
    }

    blocks.sort((a, b) => a.start.compareTo(b.start));

    final alarms = [
      PlannedAlarm(kind: AlarmKind.wake, at: wake, reason: wakeReason),
      PlannedAlarm(
        kind: AlarmKind.bed,
        at: bedTonight,
        reason: '기상 ${formatHm(wake)} − 수면 ${formatDuration(g.sleepMinutes)}'
            ' − 잠들기까지 ${s.sleepLatencyMinutes}분${s.bedEarlierMinutes > 0 ? ' − 일찍 자기 ${s.bedEarlierMinutes}분' : ''}',
      ),
      PlannedAlarm(
        kind: AlarmKind.windDown,
        at: bedTonight.subtract(Duration(minutes: s.windDownMinutes)),
        reason: '취침 ${s.windDownMinutes}분 전 마무리',
      ),
    ];

    return DayPlan(
      date: day,
      wake: wake,
      bedTonight: bedTonight,
      dayEnd: dayEnd,
      blocks: blocks,
      alarms: alarms,
      deferred: deferred,
      notes: notes,
      freeMinutes: freeMinutes,
      taskMinutes: used,
    );
  }

  /// 습관을 원래 시각에 두고, 겹치면 겹친 블록 끝으로 옮긴다(최대 120분 뒤까지).
  DateTime? _placeHabit(
      DateTime start, int minutes, List<ScheduleBlock> blocks, DateTime dayEnd) {
    final limit = start.add(const Duration(minutes: 120));
    var candidate = start;
    for (var i = 0; i < blocks.length + 1; i++) {
      final end = candidate.add(Duration(minutes: minutes));
      if (end.isAfter(dayEnd) || candidate.isAfter(limit)) return null;
      final clash = blocks.where((b) => b.overlaps(candidate, end)).toList();
      if (clash.isEmpty) return candidate;
      candidate = clash.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return null;
  }

  List<_Gap> _gaps(List<ScheduleBlock> blocks, DateTime from, DateTime to) {
    final busy = blocks
        .where((b) => b.end.isAfter(from) && b.start.isBefore(to))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final gaps = <_Gap>[];
    var cursor = from;
    for (final b in busy) {
      if (b.start.isAfter(cursor)) gaps.add(_Gap(cursor, b.start));
      if (b.end.isAfter(cursor)) cursor = b.end;
    }
    if (to.isAfter(cursor)) gaps.add(_Gap(cursor, to));
    return gaps.where((x) => x.minutes > 0).toList();
  }

  /// 조각이 들어갈 시작 시각. 집중 작업이면 집중 시간대를 먼저 찾는다.
  DateTime? _bestSlot(List<_Gap> gaps, int minutes, DateTime due,
      PersonalSettings? focus, DateTime day) {
    bool fits(DateTime s, _Gap g) {
      final e = s.add(Duration(minutes: minutes));
      return !s.isBefore(g.start) && !e.isAfter(g.end) && !e.isAfter(due);
    }

    if (focus != null) {
      final fs = focus.focusStart.on(day);
      final fe = focus.focusEnd.on(day);
      for (final g in gaps) {
        final s = g.start.isAfter(fs) ? g.start : fs;
        if (s.isBefore(fe) && fits(s, g)) return s;
      }
    }
    for (final g in gaps) {
      if (fits(g.start, g)) return g.start;
    }
    return null;
  }

  void _consume(List<_Gap> gaps, DateTime start, DateTime end) {
    for (var i = 0; i < gaps.length; i++) {
      final g = gaps[i];
      if (!g.start.isBefore(end) || !start.isBefore(g.end)) continue;
      final pieces = <_Gap>[
        if (start.isAfter(g.start)) _Gap(g.start, start),
        if (end.isBefore(g.end)) _Gap(end, g.end),
      ];
      gaps
        ..removeAt(i)
        ..insertAll(i, pieces);
      return;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

enum AlarmDecision { apply, needsConfirmation }

/// 알람 변경 제한(엔진 명세 3번): 취침 기록 뒤에는 기상 알람을 앞당기기만 한다.
AlarmDecision decideWakeChange({
  required DateTime current,
  required DateTime proposed,
  required bool sleepLogged,
}) {
  if (!proposed.isAfter(current)) return AlarmDecision.apply;
  return sleepLogged ? AlarmDecision.needsConfirmation : AlarmDecision.apply;
}

/// 블록 시작 후 10분 동안 기록이 없으면 예정 시각으로 추정 기록을 만든다(명세 4번).
List<ActivityLog> estimateMissing({
  required List<ScheduleBlock> blocks,
  required List<ActivityLog> logs,
  required DateTime now,
  int graceMinutes = 10,
}) {
  final out = <ActivityLog>[];
  for (final b in blocks) {
    final a = b.activity;
    if (a == null || b.kind == BlockKind.fixed) continue;
    if (now.difference(b.start).inMinutes < graceMinutes) continue;
    final hasLog = logs.any((l) =>
        l.activity == a && (l.start.difference(b.start).inMinutes).abs() <= 30);
    if (hasLog) continue;
    out.add(ActivityLog(
      id: 'est-${b.id}',
      activity: a,
      start: b.start,
      end: b.end.isBefore(now) ? b.end : null,
      source: LogSource.estimate,
      confirmed: false,
    ));
  }
  return out;
}
