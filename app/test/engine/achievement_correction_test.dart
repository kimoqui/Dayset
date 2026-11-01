import 'package:dayset/core/engine/achievement.dart';
import 'package:dayset/core/engine/correction.dart';
import 'package:dayset/core/engine/set_day.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, int m, {int day = 14}) => DateTime(2026, 10, day, h, m);

ScheduleBlock block(String id, Activity a, DateTime s, int minutes) => ScheduleBlock(
      id: id,
      kind: BlockKind.habit,
      activity: a,
      title: a.label,
      start: s,
      end: s.add(Duration(minutes: minutes)),
    );

ActivityLog log(Activity a, DateTime s, {DateTime? end, LogSource source = LogSource.button}) =>
    ActivityLog(id: '${a.name}-$s', activity: a, start: s, end: end, source: source);

void main() {
  const calc = AchievementCalculator();

  group('달성 판정', () {
    test('예정 ±30분 안에 시작하면 달성', () {
      final o = calc.judge(block('b', Activity.meal, at(12, 0), 60),
          [log(Activity.meal, at(12, 25))], at(14, 0));
      expect(o!.outcome, Outcome.achieved);
    });

    test('30분이 지나도 기록이 없으면 놓침, 그 전이면 대기', () {
      final b = block('b', Activity.meal, at(12, 0), 60);
      expect(calc.judge(b, const [], at(12, 20))!.outcome, Outcome.pending);
      expect(calc.judge(b, const [], at(12, 31))!.outcome, Outcome.missed);
    });

    test('추정 기록은 분모·분자에서 뺀다', () {
      final outcomes = [
        calc.judge(block('1', Activity.meal, at(8, 0), 30), [log(Activity.meal, at(8, 5))], at(22, 0))!,
        calc.judge(block('2', Activity.meal, at(12, 0), 60),
            [log(Activity.meal, at(12, 0), source: LogSource.estimate)], at(22, 0))!,
        calc.judge(block('3', Activity.meal, at(18, 30), 60), const [], at(22, 0))!,
      ];
      final s = calc.summarize(outcomes);
      final meal = s.byActivity[Activity.meal]!;
      expect(meal.achieved, 1);
      expect(meal.counted, 2);
      expect(meal.estimated, 1);
      expect(meal.rate, 0.5);
    });

    test('수면은 목표 수면시간의 90% 이상이어야 달성', () {
      final b = block('s', Activity.sleep, at(23, 30, day: 13), 450);
      final short = log(Activity.sleep, at(23, 40, day: 13), end: at(5, 30)); // 350분
      final ok = log(Activity.sleep, at(23, 40, day: 13), end: at(6, 50)); // 430분
      expect(calc.judge(b, [short], at(9, 0), goalSleepMinutes: 420)!.outcome, Outcome.missed);
      expect(calc.judge(b, [ok], at(9, 0), goalSleepMinutes: 420)!.outcome, Outcome.achieved);
    });

    test('캘린더 고정 일정은 판정하지 않는다', () {
      final fixed = ScheduleBlock(
          id: 'f', kind: BlockKind.fixed, title: '회의', start: at(9, 0), end: at(10, 0));
      expect(calc.judge(fixed, const [], at(12, 0)), isNull);
    });
  });

  test('할 일 블록은 시작 시각에 이어지고 있는 업무 기록으로도 달성한다', () {
    final task = ScheduleBlock(id: 't', kind: BlockKind.task, activity: Activity.work, title: '보고서', start: at(10, 40), end: at(11, 30));
    expect(calc.judge(task, [log(Activity.work, at(8, 0))], at(12, 0))!.outcome, Outcome.achieved);
    // 습관(식사)은 시작 시각 ±30분만 본다
    expect(calc.judge(block('m', Activity.meal, at(12, 0), 60), [log(Activity.meal, at(11, 0))], at(13, 0))!.outcome, Outcome.missed);
  });

  group('셋 데이', () {
    final blocks = [
      block('s', Activity.sleep, at(23, 45, day: 13), 435),
      block('m1', Activity.meal, at(7, 30), 30),
      block('m2', Activity.meal, at(12, 0), 60),
      block('m3', Activity.meal, at(18, 30), 60),
    ];
    final good = [
      log(Activity.sleep, at(23, 50, day: 13), end: at(7, 5)),
      log(Activity.meal, at(7, 35)),
      log(Activity.meal, at(12, 10)),
      log(Activity.meal, at(18, 40)),
    ];

    test('기상 ±30분 + 습관 70% 이상이면 셋 데이', () {
      final e = evaluateDay(blocks: blocks, logs: good, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420);
      expect(e.wakeOk, isTrue);
      expect(e.rate, 1.0);
      expect(e.isSetDay, isTrue);
    });

    test('기상이 30분 넘게 늦으면 셋 데이가 아니다', () {
      final e = evaluateDay(blocks: blocks, logs: good, wake: at(7, 0), wakeAt: at(7, 40), now: at(22, 0), goalSleepMinutes: 420);
      expect(e.isSetDay, isFalse);
    });

    test('못 했어요는 놓침, 쉬는 날 블록은 판정에서 뺀다', () {
      final logs = good.sublist(0, 2);
      final missed = evaluateDay(blocks: blocks, logs: logs, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420, marks: const DayMarks(missed: {'m2', 'm3'}));
      expect(missed.rate, 0.5);
      expect(missed.isSetDay, isFalse);
      final skipped = evaluateDay(blocks: blocks, logs: logs, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420, marks: const DayMarks(skipped: {'m2', 'm3'}));
      expect(skipped.rate, 1.0);
      expect(skipped.isSetDay, isTrue);
    });

    test('쉬는 날로 표시한 날은 셋 데이로 세지 않는다', () {
      final e = evaluateDay(blocks: blocks, logs: good, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420, marks: const DayMarks(rest: true));
      expect(e.isSetDay, isFalse);
      expect(e.rest, isTrue);
    });
  });

  group('단계적 교정', () {
    // 취침 01:00(=1500) → 23:00(=1380), 30분씩
    final plan = CorrectionPlan.create(baseline: 1500, target: 1380, stepSize: 30);

    test('간격을 단계로 나눠 주 수를 정한다', () {
      expect(plan.totalWeeks, 4);
      expect(formatClockMinutes(plan.weekTarget), '01:00');
      expect(formatClockMinutes(plan.nextTarget), '00:30');
    });

    test('달성률 80% 이상이면 한 단계 올린다', () {
      final r = plan.weeklyUpdate(achievementRate: 0.85);
      expect(r.decision, WeeklyDecision.stepUp);
      expect(formatClockMinutes(r.plan.weekTarget), '00:30');
    });

    test('피곤함이 2번 이상이면 달성률과 상관없이 한 주 유지한다', () {
      final r = plan
          .weeklyUpdate(achievementRate: 0.9)
          .plan
          .weeklyUpdate(achievementRate: 0.9, tiredCount: 2);
      expect(r.decision, WeeklyDecision.hold);
      expect(r.plan.currentStep, 1);
    });

    test('50% 미만이면 한 단계 내린다', () {
      final up = plan.weeklyUpdate(achievementRate: 0.9).plan;
      final r = up.weeklyUpdate(achievementRate: 0.4);
      expect(r.decision, WeeklyDecision.stepBack);
      expect(r.plan.currentStep, 0);
    });

    test('마지막 단계를 넘기면 완료', () {
      var p = plan;
      WeeklyDecision? d;
      for (var i = 0; i < 4; i++) {
        final r = p.weeklyUpdate(achievementRate: 0.9);
        p = r.plan;
        d = r.decision;
      }
      expect(d, WeeklyDecision.done);
      expect(p.status, CorrectionStatus.done);
      expect(formatClockMinutes(p.weekTarget), '23:00');
    });
  });
}
