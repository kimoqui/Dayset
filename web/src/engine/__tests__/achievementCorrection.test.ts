import { AchievementCalculator, rateOf } from '../achievement';
import { createCorrection, nextTarget, weeklyUpdate, weekTarget, type WeeklyDecision } from '../correction';
import { evaluateDay } from '../setDay';
import { type Activity, ACTIVITY_LABEL, type ActivityLog, addMin, formatClock, type LogSource, type ScheduleBlock } from '../models';

const at = (h: number, m: number, day = 14) => new Date(2026, 9, day, h, m);

const block = (id: string, a: Activity, s: Date, minutes: number): ScheduleBlock => ({
  id,
  kind: 'habit',
  activity: a,
  title: ACTIVITY_LABEL[a],
  start: s,
  end: addMin(s, minutes),
});

const log = (a: Activity, s: Date, p: { end?: Date; source?: LogSource } = {}): ActivityLog => ({
  id: `${a}-${s.getTime()}`,
  activity: a,
  start: s,
  end: p.end ?? null,
  source: p.source ?? 'button',
  confirmed: true,
  snoozeCount: 0,
});

const calc = new AchievementCalculator();

describe('달성 판정', () => {
  test('예정 ±30분 안에 시작하면 달성', () => {
    expect(calc.judge(block('b', 'meal', at(12, 0), 60), [log('meal', at(12, 25))], at(14, 0))!.outcome).toBe('achieved');
  });

  test('30분이 지나도 기록이 없으면 놓침, 그 전이면 대기', () => {
    const b = block('b', 'meal', at(12, 0), 60);
    expect(calc.judge(b, [], at(12, 20))!.outcome).toBe('pending');
    expect(calc.judge(b, [], at(12, 31))!.outcome).toBe('missed');
  });

  test('추정 기록은 분모·분자에서 뺀다', () => {
    const outcomes = [
      calc.judge(block('1', 'meal', at(8, 0), 30), [log('meal', at(8, 5))], at(22, 0))!,
      calc.judge(block('2', 'meal', at(12, 0), 60), [log('meal', at(12, 0), { source: 'estimate' })], at(22, 0))!,
      calc.judge(block('3', 'meal', at(18, 30), 60), [], at(22, 0))!,
    ];
    const meal = calc.summarize(outcomes).byActivity.meal!;
    expect(meal.achieved).toBe(1);
    expect(meal.counted).toBe(2);
    expect(meal.estimated).toBe(1);
    expect(rateOf(meal)).toBe(0.5);
  });

  test('수면은 목표 수면시간의 90% 이상이어야 달성', () => {
    const b = block('s', 'sleep', at(23, 30, 13), 450);
    const short = log('sleep', at(23, 40, 13), { end: at(5, 30) }); // 350분
    const ok = log('sleep', at(23, 40, 13), { end: at(6, 50) }); // 430분
    expect(calc.judge(b, [short], at(9, 0), 420)!.outcome).toBe('missed');
    expect(calc.judge(b, [ok], at(9, 0), 420)!.outcome).toBe('achieved');
  });

  test('할 일 블록은 시작 시각에 이어지고 있는 업무 기록으로도 달성한다', () => {
    const task: ScheduleBlock = { id: 't', kind: 'task', activity: 'work', title: '보고서', start: at(10, 40), end: at(11, 30) };
    expect(calc.judge(task, [log('work', at(8, 0))], at(12, 0))!.outcome).toBe('achieved');
    // 습관(식사)은 시작 시각 ±30분만 본다
    expect(calc.judge(block('m', 'meal', at(12, 0), 60), [log('meal', at(11, 0))], at(13, 0))!.outcome).toBe('missed');
  });

  test('캘린더 고정 일정은 판정하지 않는다', () => {
    const fixed: ScheduleBlock = { id: 'f', kind: 'fixed', title: '회의', start: at(9, 0), end: at(10, 0) };
    expect(calc.judge(fixed, [], at(12, 0))).toBeNull();
  });
});

describe('셋 데이', () => {
  const blocks = [
    block('s', 'sleep', at(23, 45, 13), 435),
    block('m1', 'meal', at(7, 30), 30),
    block('m2', 'meal', at(12, 0), 60),
    block('m3', 'meal', at(18, 30), 60),
  ];
  const good = [
    log('sleep', at(23, 50, 13), { end: at(7, 5) }),
    log('meal', at(7, 35)),
    log('meal', at(12, 10)),
    log('meal', at(18, 40)),
  ];

  test('기상 ±30분 + 습관 70% 이상이면 셋 데이', () => {
    const e = evaluateDay({ blocks, logs: good, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420 });
    expect(e.wakeOk).toBe(true);
    expect(e.rate).toBe(1);
    expect(e.isSetDay).toBe(true);
  });

  test('기상이 30분 넘게 늦으면 셋 데이가 아니다', () => {
    const e = evaluateDay({ blocks, logs: good, wake: at(7, 0), wakeAt: at(7, 40), now: at(22, 0), goalSleepMinutes: 420 });
    expect(e.isSetDay).toBe(false);
  });

  test('못 했어요는 놓침, 쉬는 날 블록은 판정에서 뺀다', () => {
    const logs = good.slice(0, 2); // 점심·저녁 기록 없음
    const base = { blocks, logs, wake: at(7, 0), wakeAt: at(7, 5), now: at(22, 0), goalSleepMinutes: 420 };
    const missed = evaluateDay({ ...base, marks: { missed: new Set(['m2', 'm3']), skipped: new Set(), rest: false } });
    expect(missed.rate).toBe(0.5);
    expect(missed.isSetDay).toBe(false);
    const skipped = evaluateDay({ ...base, marks: { missed: new Set(), skipped: new Set(['m2', 'm3']), rest: false } });
    expect(skipped.rate).toBe(1);
    expect(skipped.isSetDay).toBe(true);
  });

  test('쉬는 날로 표시한 날은 셋 데이로 세지 않는다', () => {
    const e = evaluateDay({
      blocks,
      logs: good,
      wake: at(7, 0),
      wakeAt: at(7, 5),
      now: at(22, 0),
      goalSleepMinutes: 420,
      marks: { missed: new Set(), skipped: new Set(), rest: true },
    });
    expect(e.isSetDay).toBe(false);
    expect(e.rest).toBe(true);
  });
});

describe('단계적 교정', () => {
  // 취침 01:00(=1500) → 23:00(=1380), 30분씩
  const plan = createCorrection({ baseline: 1500, target: 1380, stepSize: 30 });

  test('간격을 단계로 나눠 주 수를 정한다', () => {
    expect(plan.totalWeeks).toBe(4);
    expect(formatClock(weekTarget(plan))).toBe('01:00');
    expect(formatClock(nextTarget(plan))).toBe('00:30');
  });

  test('달성률 80% 이상이면 한 단계 올린다', () => {
    const r = weeklyUpdate(plan, { achievementRate: 0.85 });
    expect(r.decision).toBe('stepUp');
    expect(formatClock(weekTarget(r.plan))).toBe('00:30');
  });

  test('피곤함이 2번 이상이면 달성률과 상관없이 한 주 유지한다', () => {
    const r = weeklyUpdate(weeklyUpdate(plan, { achievementRate: 0.9 }).plan, { achievementRate: 0.9, tiredCount: 2 });
    expect(r.decision).toBe('hold');
    expect(r.plan.currentStep).toBe(1);
  });

  test('50% 미만이면 한 단계 내린다', () => {
    const up = weeklyUpdate(plan, { achievementRate: 0.9 }).plan;
    const r = weeklyUpdate(up, { achievementRate: 0.4 });
    expect(r.decision).toBe('stepBack');
    expect(r.plan.currentStep).toBe(0);
  });

  test('마지막 단계를 넘기면 완료', () => {
    let p = plan;
    let d: WeeklyDecision | undefined;
    for (let i = 0; i < 4; i++) {
      const r = weeklyUpdate(p, { achievementRate: 0.9 });
      p = r.plan;
      d = r.decision;
    }
    expect(d).toBe('done');
    expect(p.status).toBe('done');
    expect(formatClock(weekTarget(p))).toBe('23:00');
  });
});
