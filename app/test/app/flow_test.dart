// 하루 흐름 시나리오: 온보딩 → 기상 알람 → '지금' 버튼 → 코칭 → 저녁 확인 → 셋 데이.
// 웹 버전 src/app/__tests__/flow.test.ts를 옮겼다.

import 'package:dayset/app/derive.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/engine/achievement.dart';
import 'package:dayset/core/engine/correction.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

void main() {
  late Store store;
  void goTo(DateTime d) => store.setFixedClock(d);
  void onboard({PersonalSettings settings = const PersonalSettings(), HabitGoals goals = defaultGoals, int? usualWake = 7 * 60}) =>
      store.completeOnboarding(goals: goals, settings: settings, usualWake: usualWake);

  setUp(() {
    store = Store(storage: StateStorage(MemoryStore()));
  });

  test('온보딩 뒤 오늘 일정을 고정하고, 알람 끄기로 기상을 기록한다', () {
    goTo(at(19, 6, 0));
    onboard();
    expect(store.state.plans['2026-10-19'], isNotNull);

    goTo(at(19, 7, 1));
    final due = store.dueAlarms(store.now());
    expect(due.ring?.kind, RingKind.wake);
    store.dismissWake(due.ring!);
    final w = store.state.wakes.first;
    expect(w.day, '2026-10-19');
    expect(w.source, WakeSource.alarm);
    expect(store.dueAlarms(store.now()).ring, isNull);
  });

  test('스누즈하면 5분 동안 울리지 않고 횟수를 센다', () {
    goTo(at(19, 6, 0));
    onboard();
    goTo(at(19, 7, 0));
    final r = store.dueAlarms(store.now()).ring!;
    store.snooze(r, 5);
    goTo(at(19, 7, 3));
    expect(store.dueAlarms(store.now()).ring, isNull);
    goTo(at(19, 7, 6));
    final again = store.dueAlarms(store.now()).ring!;
    store.dismissWake(again);
    expect(store.state.wakes.first.snoozes, 1);
  });

  test('하루를 일정대로 보내면 셋 데이가 된다', () {
    goTo(at(18, 22, 0));
    onboard(settings: const PersonalSettings(travelMinutes: 0));
    goTo(at(18, 23, 46));
    store.tap(Activity.sleep); // 18일 밤 취침 → 19일 일정 확정
    expect(store.state.plans['2026-10-19'], isNotNull);

    goTo(at(19, 7, 2));
    store.dismissWake(store.dueAlarms(store.now()).ring!);
    for (final (h, m, a) in [
      (7, 32, Activity.meal),
      (8, 10, Activity.work),
      (12, 3, Activity.meal),
      (13, 0, Activity.work),
      (18, 35, Activity.meal),
      (19, 30, Activity.rest),
      (20, 31, Activity.exercise),
      (21, 5, Activity.rest),
    ]) {
      goTo(at(19, h, m));
      store.tap(a);
    }

    final v = evaluate(store.state, '2026-10-19', store.now());
    expect(v.wakeOk, isTrue);
    expect(v.rate, 1);
    expect(v.isSetDay, isTrue);
  });

  test('적게 자면 운동을 줄이자는 코칭이 뜨고, 승인하면 오늘 일정이 바뀐다', () {
    goTo(at(19, 1, 0));
    onboard();
    store.tap(Activity.sleep);
    goTo(at(19, 6, 40)); // 5시간 40분
    store.tap(Activity.meal); // 버튼으로 일어나도 기상 기록
    expect(store.state.wakes.first.source, WakeSource.button);
    final item = store.pendingInbox(store.now())!;
    expect(item.message, '어젯밤 5시간 40분 잤어요. 오늘 운동을 15분 가벼운 루틴으로 바꿀까요?');
    store.acceptSuggestion(item.id);
    final ex = store.state.plans['2026-10-19']!.blocks.firstWhere((b) => b.activity == Activity.exercise);
    expect(ex.adjusted, isTrue);
    expect(ex.end.difference(ex.start).inMinutes, 15);
  });

  test('저녁 확인: 못 했어요 + 이유가 두 번이면 다음 행동을 제안하고, 확인 끝에 내일을 확정한다', () {
    goTo(at(19, 6, 0));
    onboard();
    goTo(at(19, 22, 0));
    final plan = store.state.plans['2026-10-19']!;
    final meals = plan.blocks.where((b) => b.activity == Activity.meal).toList();
    store.markMissed('2026-10-19', meals[0], MissReason.forgot);
    store.markMissed('2026-10-19', meals[1], MissReason.forgot);
    final pend = store.state.inbox.where((i) => i.status == InboxStatus.pending);
    expect(pend.any((i) => i.suggestion?.ruleId == 'R6'), isTrue);

    store.markDid('2026-10-19', meals[2]);
    final v = evaluate(store.state, '2026-10-19', store.now());
    expect(v.outcomes.firstWhere((o) => o.block.id == meals[2].id).outcome, Outcome.achieved);
    expect(v.outcomes.firstWhere((o) => o.block.id == meals[0].id).outcome, Outcome.missed);

    store.finishEvening('2026-10-19');
    expect(store.state.plans['2026-10-20'], isNotNull);
    expect(store.state.eveningDone, contains('2026-10-19'));
  });

  test('오늘 잡은 할 일 조각은 내일 일정에 다시 넣지 않는다', () {
    goTo(at(19, 6, 0));
    onboard();
    store.saveTask(TaskItem(id: 't1', title: '보고서', estMinutes: 100, dueAt: at(25, 18)));
    store.regenerate('2026-10-19');
    final s = store.state;
    final todayMin = s.plans['2026-10-19']!.blocks.where((b) => b.taskId == 't1').fold<int>(0, (n, b) => n + b.end.difference(b.start).inMinutes);
    expect(todayMin, 100);
    final tomorrow = planFor(s, '2026-10-20', store.now());
    expect(tomorrow.blocks.where((b) => b.taskId == 't1').toList(), hasLength(0));
  });

  test('첫 일정이 이르면 내일 기상 알람이 당겨지고 근거를 남긴다', () {
    goTo(at(19, 6, 0));
    onboard();
    store.saveEvent(FixedEvent(id: 'e1', title: '팀 회의', start: at(20, 8, 0), end: at(20, 9, 0)));
    final p = planFor(store.state, '2026-10-20', store.now());
    expect(formatHm(p.wake), '06:30');
    expect(p.plan.alarms.first.reason, contains('첫 일정 08:00'));
  });

  test('교정 계획: 지난주 기상 달성률로 이번 주 목표를 정한다', () {
    goTo(at(12, 6, 0)); // 월요일
    onboard(usualWake: 8 * 60);
    expect(formatHm(store.state.plans['2026-10-12']!.plan.wake), '08:00');
    // 일주일 동안 매일 08:00 기상
    for (var d = 12; d <= 18; d++) {
      goTo(at(d, 8, 2));
      store.ensureDay(store.now());
      final r = store.dueAlarms(store.now()).ring;
      if (r != null) store.dismissWake(r);
    }
    goTo(at(19, 5, 0)); // 다음 주 월요일
    store.ensureDay(store.now());
    final s = store.state;
    expect(s.correction!.history.last.decision, WeeklyDecision.stepUp);
    expect(formatHm(s.plans['2026-10-19']!.plan.wake), '07:30');
  });

  test('예시 데이터로 통계와 셋 데이 캘린더를 계산할 수 있다', () {
    final now = at(19, 10, 0);
    goTo(now);
    final s = demoState(now);
    final week = periodStats(s, weekKeys(addDays(now, -7)), now);
    expect(week.days, hasLength(7));
    expect(week.setDays, greaterThan(0));
    expect(week.setDays, lessThan(7));
    expect(s.inbox.firstOrNull?.suggestion?.ruleId, 'R1');
    expect(dateKey(s.wakes.last.at), '2026-10-19');
  });

  group('2일 관찰', () {
    test('오후에 시작하면 다음 날이 1일차, 1일차에는 일정·알람·코칭이 없다', () {
      goTo(at(19, 20, 45));
      store.startObservation();
      expect(store.state.observation!.phase, ObservationPhase.recording);
      expect(store.state.observation!.day1, '2026-10-20');
      store.tap(Activity.sleep);
      goTo(at(20, 7, 40));
      store.ensureDay(store.now());
      expect(store.state.plans.keys.toList(), hasLength(0));
      expect(store.dueAlarms(store.now()).ring, isNull);
      store.tap(Activity.meal); // 수면 끝 → 기상 기록
      expect(store.state.wakes.first.day, '2026-10-20');
      expect(store.state.inbox, hasLength(0));
    });

    test('1일차 기록을 읽고, 바꾼 것만 반영해 2일차 일정을 만든다', () {
      goTo(at(19, 23, 50));
      store.startObservation();
      store.tap(Activity.sleep);
      for (final (h, m, a) in [
        (8, 10, Activity.meal),
        (8, 35, Activity.work),
        (12, 40, Activity.meal),
        (13, 30, Activity.work),
        (19, 5, Activity.meal),
      ]) {
        goTo(at(20, h, m));
        store.tap(a);
      }
      goTo(at(20, 21, 0));

      final o = observedDay(store.state, '2026-10-20', store.now());
      expect(formatHm(o.wakeAt!), '08:10');
      expect(formatHm(o.meals['점심 식사']!.start), '12:40');
      expect(o.exercise, isNull);
      expect(formatHm(o.work!.start), '08:35');

      // 바꾸고 싶은 것: 기상 07:00, 점심 12:00. 나머지는 기록 그대로.
      store.completeObservation(
        goals: const HabitGoals(
          wake: ClockTime(7 * 60),
          sleepMinutes: 420,
          meals: [
            HabitSlot(title: '아침 식사', activity: Activity.meal, start: ClockTime(8 * 60 + 10), minutes: 25),
            HabitSlot(title: '점심 식사', activity: Activity.meal, start: ClockTime(12 * 60), minutes: 50),
            HabitSlot(title: '저녁 식사', activity: Activity.meal, start: ClockTime(19 * 60 + 5), minutes: 60),
          ],
        ),
        settings: store.state.settings.copyWith(focusStart: const ClockTime(8 * 60 + 35), focusEnd: const ClockTime(11 * 60 + 35)),
        recordedWake: 8 * 60 + 10,
      );
      final s = store.state;
      expect(s.observation!.phase, ObservationPhase.trial);
      expect(s.observation!.day2, '2026-10-21');
      expect(s.plans['2026-10-20'], isNull); // 1일차는 일정 없음
      final day2 = s.plans['2026-10-21']!;
      // 70분 차이 → 단계적 교정: 첫 주는 기록한 08:10
      expect(formatHm(day2.plan.wake), '08:10');
      expect(s.correction!.plan.totalWeeks, 3);
      expect(formatHm(day2.blocks.firstWhere((b) => b.title == '점심 식사').start), '12:00');
    });

    test('2일차 저녁: 20분 넘게 어긋난 습관만 다시 묻고 관찰을 끝낸다', () {
      goTo(at(19, 23, 50));
      store.startObservation();
      goTo(at(20, 21, 0));
      store.completeObservation(goals: defaultGoals, settings: const PersonalSettings(), recordedWake: 7 * 60);
      goTo(at(21, 12, 45));
      store.tap(Activity.meal); // 점심 12:00 예정 → 12:45
      goTo(at(21, 18, 35));
      store.tap(Activity.meal); // 저녁 18:30 예정 → 18:35 (5분, 묻지 않음)
      goTo(at(21, 21, 30));
      store.finishEvening('2026-10-21');
      final s = store.state;
      expect(s.observation!.phase, ObservationPhase.done);
      final asks = s.inbox.where((i) => i.suggestion?.ruleId == 'OBS').toList();
      expect(asks, hasLength(1));
      expect(asks.first.message, '점심 식사를 12:00으로 정했는데 오늘은 12:45에 시작했어요. 12:45으로 옮길까요?');
      store.acceptSuggestion(asks.first.id);
      expect(store.state.goals.meals.firstWhere((m) => m.title == '점심 식사').start.minutes, 12 * 60 + 45);
    });

    test('첫 캘린더 일정 때 이동 시간을 한 번만 묻고 저장한다', () {
      goTo(at(19, 9, 0));
      store.startObservation();
      store.saveEvent(FixedEvent(id: 'e1', title: '수업', start: at(22, 9), end: at(22, 10)), travelMinutes: 20);
      expect(store.state.settings.travelMinutes, 20);
      expect(store.state.asked.travel, isTrue);
    });
  });
}
