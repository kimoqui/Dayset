// 예시 데이터: 직장인 한 명의 지난 3주. 통계·셋 데이 캘린더·코칭을 바로 볼 수 있다.
// 웹 버전 src/app/seed.ts와 같은 난수·같은 내용이라 같은 시각이면 같은 예시가 나온다.

import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import 'derive.dart';
import 'state.dart';

double Function() _rng(int seed) {
  var x = seed;
  return () {
    x = (x * 1664525 + 1013904223) % 4294967296;
    return x / 4294967296;
  };
}

AppState demoState(DateTime now) {
  final rand = _rng(20261019);
  int jitter(int min, int max) => (min + rand() * (max - min)).round();
  final today = dayStart(now);
  var n = 0;
  String id(String p) => '$p-demo-${n++}';
  DateTime d(int plus, int h, [int m = 0]) => DateTime(today.year, today.month, today.day + plus, h, m);

  final tasks = [
    TaskItem(id: 'task-report', title: '분기 보고서 작성', estMinutes: 180, dueAt: d(3, 18), type: TaskType.work, priority: TaskPriority.high, focus: true, createdAt: d(-2, 10)),
    TaskItem(id: 'task-english', title: '영어 숙제', estMinutes: 60, dueAt: d(2, 23), type: TaskType.homework, createdAt: d(-1, 20)),
    TaskItem(id: 'task-dentist', title: '치과 예약 전화', estMinutes: 10, dueAt: d(0, 18), type: TaskType.personal, createdAt: d(-3, 9)),
  ];
  final events = [
    FixedEvent(id: 'ev-1', title: '고객 미팅', start: d(0, 16), end: d(0, 17)),
    FixedEvent(id: 'ev-2', title: '팀 회의', start: d(1, 9), end: d(1, 10)),
  ];

  var s = AppState.initial(now: now).copyWith(onboarded: true, demo: true, goals: defaultGoals, events: events, tasks: const []);
  final plans = <String, StoredPlan>{};
  final wakes = <WakeRecord>[];
  final misses = <MissMark>[];
  final eveningDone = <String>[];
  final alarms = <String, AlarmState>{};
  final logs = <ActivityLog>[];
  final restDays = <String>[];
  const days = 20;

  // 지난 날: 일정 저장 + 기록 생성
  for (var i = days; i >= 1; i--) {
    final day = addDays(today, -i);
    final key = dateKey(day);
    final plan = buildPlan(s, key);
    plans[key] = storedFrom(plan, s);
    final weekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    if (weekend && rand() < 0.35) restDays.add(key);
    final good = rand() < 0.6; // 잘 지낸 날

    // 수면: 전날 밤 취침 ~ 기상
    final sleepBlock = plan.blocks.first;
    final bed = addMin(sleepBlock.start, good ? jitter(-10, 20) : jitter(10, 70));
    final wakeAt = addMin(plan.wake, good ? jitter(-5, 12) : jitter(15, 55));
    logs.add(ActivityLog(id: id('log'), activity: Activity.sleep, start: bed, end: wakeAt, source: LogSource.alarm));
    wakes.add(WakeRecord(day: key, at: wakeAt, snoozes: good ? jitter(0, 1) : jitter(1, 4), source: WakeSource.alarm));

    for (final b in plan.blocks.skip(1)) {
      final a = b.activity;
      if (b.kind != BlockKind.habit || a == null) continue;
      final p = a == Activity.exercise ? (good ? 0.75 : 0.25) : (good ? 0.93 : 0.5);
      if (rand() < p) {
        final start = addMin(b.start, jitter(-8, 18));
        final len = diffMin(b.end, b.start) + jitter(-10, 10);
        logs.add(ActivityLog(id: id('log'), activity: a, start: start, end: addMin(start, len < 10 ? 10 : len)));
      } else if (rand() < 0.85) {
        final reason = a == Activity.exercise ? const [MissReason.tired, MissReason.unwilling, MissReason.conflict][jitter(0, 2)] : MissReason.values[jitter(0, 3)];
        misses.add(MissMark(day: key, blockId: b.id, activity: a, reason: reason, at: b.end));
      }
    }
    // 업무 기록(그래프용)
    if (!weekend) {
      final ws = d(-i, 9, jitter(0, 20));
      logs.add(ActivityLog(id: id('log'), activity: Activity.work, start: ws, end: d(-i, 11, 50), source: LogSource.widget));
      logs.add(ActivityLog(id: id('log'), activity: Activity.work, start: d(-i, 13, jitter(0, 15)), end: d(-i, 18, jitter(0, 40)), source: LogSource.widget));
    }
    eveningDone.add(key);
  }

  // 오늘: 어젯밤 짧게 잔 날(코칭 R1 예시). 지금 시각까지 일정대로 기록한다.
  s = s.copyWith(tasks: tasks);
  final todayKey = dateKey(today);
  final todayPlan = buildPlan(s, todayKey);
  plans[todayKey] = storedFrom(todayPlan, s);
  final lastBed = d(0, 1, 20);
  final wakeAt = addMin(todayPlan.wake, 4);
  final sleepEnd = now.isAfter(wakeAt) ? wakeAt : null;
  logs.add(ActivityLog(id: id('log'), activity: Activity.sleep, start: lastBed, end: sleepEnd));
  var inbox = <InboxItem>[];
  if (sleepEnd != null) {
    wakes.add(WakeRecord(day: todayKey, at: wakeAt, snoozes: 1, source: WakeSource.alarm));
    alarms['$todayKey|wake'] = const AlarmState(snoozes: 1, done: true);
    int? lastIdx;
    for (final b in todayPlan.blocks.skip(1)) {
      final a = b.activity;
      if (a == null || b.kind == BlockKind.fixed || a == Activity.exercise) continue;
      final start = addMin(b.start, jitter(0, 4));
      if (!start.isBefore(now)) break;
      final end = b.end.isBefore(now) ? b.end : null;
      if (lastIdx != null && logs[lastIdx].activity == a) {
        // 같은 활동이 이어지면 한 기록으로 둔다('지금' 버튼은 같은 상태를 다시 눌러도 바뀌지 않는다).
        logs[lastIdx] = end == null ? logs[lastIdx].copyWith(clearEnd: true) : logs[lastIdx].copyWith(end: end);
        continue;
      }
      if (lastIdx != null && logs[lastIdx].end == null) logs[lastIdx] = logs[lastIdx].copyWith(end: start);
      logs.add(ActivityLog(id: id('log'), activity: a, start: start, end: end));
      lastIdx = logs.length - 1;
    }
    // 마지막 기록은 지금도 이어지는 중으로 둔다.
    if (lastIdx != null) {
      final e = logs[lastIdx].end;
      if (e != null && now.difference(e).inMilliseconds < 90 * 60000) logs[lastIdx] = logs[lastIdx].copyWith(clearEnd: true);
    }
    final sg = CoachingEngine().evaluate(WakeLogged(sleepMinutes: diffMin(wakeAt, lastBed)), today: todayPlan.blocks, now: now);
    inbox = [for (final x in sg) InboxItem(id: id('coach'), day: todayKey, createdAt: wakeAt, kind: InboxKind.coach, suggestion: x, message: x.message)];
  }

  final sorted = stableSorted(logs, (a, b) => a.start.compareTo(b.start));
  final week = dateKey(mondayOf(now));
  final friends = [
    Friend(id: 'demo-f1', name: '지민', streak: 12, best: 21, week: week, weekSetDays: 1, monthSetDays: 13, updatedAt: addMin(now, -95)),
    Friend(id: 'demo-f2', name: '현우', streak: 4, best: 9, week: week, weekSetDays: 1, monthSetDays: 8, updatedAt: addMin(now, -300)),
    Friend(id: 'demo-f3', name: '서연', streak: 0, best: 15, week: dateKey(addDays(mondayOf(now), -7)), weekSetDays: 5, monthSetDays: 6, updatedAt: addDays(now, -3)),
  ];
  // 우선순위 학습 예시: 4일 동안 '짧은 일·개인 일 먼저'로 순서를 바꿈 → AI 추천이 보인다.
  OrderItem l(TaskType t, int est, double age) => OrderItem(type: t, est: est, age: age);
  final learning = LearningLog(
    reorders: [
      Reorder(at: d(-4, 21), items: [l(TaskType.personal, 20, 1), l(TaskType.homework, 45, 2), l(TaskType.work, 120, 3), l(TaskType.assignment, 180, 1)]),
      Reorder(at: d(-3, 8), items: [l(TaskType.personal, 10, 0), l(TaskType.work, 30, 1), l(TaskType.homework, 60, 2), l(TaskType.work, 150, 2)]),
      Reorder(at: d(-2, 9), items: [l(TaskType.work, 20, 0), l(TaskType.personal, 30, 3), l(TaskType.homework, 90, 1), l(TaskType.assignment, 240, 4)]),
      Reorder(at: d(-1, 22), items: [l(TaskType.personal, 15, 1), l(TaskType.homework, 50, 0), l(TaskType.work, 180, 2)]),
    ],
    completions: [
      Completion(at: d(-3, 12), type: TaskType.personal, est: 10, age: 0.5, pos: 0),
      Completion(at: d(-2, 15), type: TaskType.work, est: 20, age: 0.2, pos: 0),
      Completion(at: d(-1, 11), type: TaskType.personal, est: 15, age: 1, pos: 0),
    ],
  );
  const cell = '37.38,126.94';
  Friend near(int i, String name, int streak, int wsd, [String c = cell]) => Friend(
      id: 'demo-n$i', name: name, streak: streak, best: streak + 3, week: week, weekSetDays: wsd, monthSetDays: wsd + 4, updatedAt: addMin(now, -30 * i), anon: true, cell: c, demo: true);
  final nearby = NearbyState(on: true, cell: cell, cellAt: now, people: [
    near(1, '꾸준한 거북이 #071', 18, 1),
    near(2, '새벽 참새 #512', 9, 1),
    near(3, '느긋한 판다 #233', 2, 0, '37.36,126.94'),
    near(4, '반짝이는 여우 #908', 5, 1, '37.40,126.96'),
    near(5, '포근한 고양이 #144', 0, 0),
  ]);
  // 걸리는 시간 보정 예시: 숙제는 예상보다 오래, 개인 일은 빨리 끝내는 편.
  DurationSample ds(String title, TaskType type, int est, int actual, int day) => DurationSample(at: d(day, 21), type: type, title: title, est: est, actual: actual);
  final durations = DurationLearning(samples: [
    ds('영어 숙제', TaskType.homework, 60, 80, -9),
    ds('수학 숙제', TaskType.homework, 40, 55, -7),
    ds('독후감', TaskType.homework, 45, 60, -5),
    ds('택배 반품', TaskType.personal, 20, 10, -8),
    ds('은행 업무', TaskType.personal, 30, 20, -6),
    ds('병원 예약', TaskType.personal, 15, 10, -4),
    ds('주간 보고', TaskType.work, 120, 125, -3),
    ds('메일 정리', TaskType.work, 30, 30, -2),
  ]);
  // 가져온 캘린더 예시(.ics 파일): 내일부터의 수업. 오늘 일정은 그대로 둔다.
  final school = [for (final p in [1, 3, 8]) FixedEvent(id: 'ics:학교 시간표:class@$p', title: '경영학원론', start: d(p, 13), end: d(p, 14, 30), source: 'ics:학교 시간표')];
  final calendars = [CalendarSource(id: 'ics:학교 시간표', kind: CalendarKind.ics, name: '학교 시간표', lastSync: d(-1, 21), count: school.length)];
  // 예시 데이터: 동의·목표·지표가 채워진 상태로 둘러본다.
  final consent = Consent(health: true, metrics: true, at: d(-days, 9));
  final intent = GoalIntent(focus: const [GoalFocus.wake, GoalFocus.breakfast, GoalFocus.tasks], wake: 7 * 60, sleepMinutes: 420, exerciseMinutes: 30, setAt: d(-days, 9));
  final opens = [
    for (var i = 0; i < days; i++)
      if (i % 5 != 3) dateKey(addDays(today, i - days)),
  ];
  return s.copyWith(
    plans: plans,
    wakes: wakes,
    misses: misses,
    alarms: alarms,
    eveningDone: eveningDone,
    inbox: inbox,
    logs: sorted,
    restDays: restDays,
    friends: friends,
    learning: learning,
    nearby: nearby,
    durations: durations,
    calendars: calendars,
    consent: consent,
    intent: intent,
    metrics: MetricsLog(installAt: d(-days, 9), opens: opens),
    events: [...s.events, ...school],
    profile: s.profile.copyWith(name: '나'),
  );
}
