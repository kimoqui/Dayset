// 하루 흐름 시나리오: 온보딩 → 기상 알람 → '지금' 버튼 → 코칭 → 저녁 확인 → 셋 데이.

import { evaluate, observedDay, periodStats, planFor, weekKeys } from '../derive';
import { demoState } from '../seed';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';
import { addDays, dateKey, formatHm } from '../../engine/models';

const at = (day: number, h: number, m = 0) => new Date(2026, 9, day, h, m);
const goTo = (d: Date) => store.setFixedClock(d);

beforeEach(() => {
  store.resetAll();
});

test('온보딩 뒤 오늘 일정을 고정하고, 알람 끄기로 기상을 기록한다', () => {
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  const s0 = store.getState();
  expect(s0.plans['2026-10-19']).toBeDefined();

  goTo(at(19, 7, 1));
  const due = store.dueAlarms(store.now());
  expect(due.ring?.kind).toBe('wake');
  store.dismissWake(due.ring!);
  const s1 = store.getState();
  expect(s1.wakes[0]).toMatchObject({ day: '2026-10-19', source: 'alarm' });
  expect(store.dueAlarms(store.now()).ring).toBeNull();
});

test('스누즈하면 5분 동안 울리지 않고 횟수를 센다', () => {
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  goTo(at(19, 7, 0));
  const r = store.dueAlarms(store.now()).ring!;
  store.snooze(r, 5);
  goTo(at(19, 7, 3));
  expect(store.dueAlarms(store.now()).ring).toBeNull();
  goTo(at(19, 7, 6));
  const again = store.dueAlarms(store.now()).ring!;
  store.dismissWake(again);
  expect(store.getState().wakes[0].snoozes).toBe(1);
});

test('하루를 일정대로 보내면 셋 데이가 된다', () => {
  goTo(at(18, 22, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: { travelMinutes: 0 }, usualWake: 7 * 60 });
  goTo(at(18, 23, 46));
  store.tap('sleep'); // 18일 밤 취침 → 19일 일정 확정
  expect(store.getState().plans['2026-10-19']).toBeDefined();

  goTo(at(19, 7, 2));
  store.dismissWake(store.dueAlarms(store.now()).ring!);
  goTo(at(19, 7, 32));
  store.tap('meal');
  goTo(at(19, 8, 10));
  store.tap('work');
  goTo(at(19, 12, 3));
  store.tap('meal');
  goTo(at(19, 13, 0));
  store.tap('work');
  goTo(at(19, 18, 35));
  store.tap('meal');
  goTo(at(19, 19, 30));
  store.tap('rest');
  goTo(at(19, 20, 31));
  store.tap('exercise');
  goTo(at(19, 21, 5));
  store.tap('rest');

  const v = evaluate(store.getState(), '2026-10-19', store.now());
  expect(v.wakeOk).toBe(true);
  expect(v.rate).toBe(1);
  expect(v.isSetDay).toBe(true);
});

test('적게 자면 운동을 줄이자는 코칭이 뜨고, 승인하면 오늘 일정이 바뀐다', () => {
  goTo(at(19, 1, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  store.tap('sleep');
  goTo(at(19, 6, 40)); // 5시간 40분
  store.tap('meal'); // 버튼으로 일어나도 기상 기록
  const s = store.getState();
  expect(s.wakes[0].source).toBe('button');
  const item = store.pendingInbox(s, store.now())!;
  expect(item.message).toBe('어젯밤 5시간 40분 잤어요. 오늘 운동을 15분 가벼운 루틴으로 바꿀까요?');
  store.acceptSuggestion(item.id);
  const ex = store.getState().plans['2026-10-19'].blocks.find((b) => b.activity === 'exercise')!;
  expect(ex.adjusted).toBe(true);
  expect((ex.end.getTime() - ex.start.getTime()) / 60000).toBe(15);
});

test('저녁 확인: 못 했어요 + 이유가 두 번이면 다음 행동을 제안하고, 확인 끝에 내일을 확정한다', () => {
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  goTo(at(19, 22, 0));
  const plan = store.getState().plans['2026-10-19'];
  const meals = plan.blocks.filter((b) => b.activity === 'meal');
  store.markMissed('2026-10-19', meals[0], 'forgot');
  store.markMissed('2026-10-19', meals[1], 'forgot');
  const pend = store.getState().inbox.filter((i) => i.status === 'pending');
  expect(pend.some((i) => i.suggestion?.ruleId === 'R6')).toBe(true);

  store.markDid('2026-10-19', meals[2]);
  const v = evaluate(store.getState(), '2026-10-19', store.now());
  expect(v.outcomes.find((o) => o.block.id === meals[2].id)?.outcome).toBe('achieved');
  expect(v.outcomes.find((o) => o.block.id === meals[0].id)?.outcome).toBe('missed');

  store.finishEvening('2026-10-19');
  const s = store.getState();
  expect(s.plans['2026-10-20']).toBeDefined();
  expect(s.eveningDone).toContain('2026-10-19');
});

test('오늘 잡은 할 일 조각은 내일 일정에 다시 넣지 않는다', () => {
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  store.saveTask({ id: 't1', title: '보고서', estMinutes: 100, dueAt: at(25, 18), type: 'work', priority: 'normal', focus: false, doneMinutes: 0 });
  store.regenerate('2026-10-19');
  const s = store.getState();
  const todayMin = s.plans['2026-10-19'].blocks.filter((b) => b.taskId === 't1').reduce((n, b) => n + (b.end.getTime() - b.start.getTime()) / 60000, 0);
  expect(todayMin).toBe(100);
  const tomorrow = planFor(s, '2026-10-20', store.now());
  expect(tomorrow.blocks.filter((b) => b.taskId === 't1')).toHaveLength(0);
});

test('첫 일정이 이르면 내일 기상 알람이 당겨지고 근거를 남긴다', () => {
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
  store.saveEvent({ id: 'e1', title: '팀 회의', start: at(20, 8, 0), end: at(20, 9, 0) });
  const p = planFor(store.getState(), '2026-10-20', store.now());
  expect(formatHm(p.wake)).toBe('06:30');
  expect(p.alarms[0].reason).toContain('첫 일정 08:00');
});

test('교정 계획: 지난주 기상 달성률로 이번 주 목표를 정한다', () => {
  goTo(at(12, 6, 0)); // 월요일
  store.completeOnboarding({ goals: { ...structuredClone(DEFAULT_GOALS), wake: 7 * 60 }, settings: {}, usualWake: 8 * 60 });
  expect(formatHm(store.getState().plans['2026-10-12'].wake)).toBe('08:00');
  // 일주일 동안 매일 08:00 기상
  for (let d = 12; d <= 18; d++) {
    goTo(at(d, 8, 2));
    store.ensureDay(store.now());
    const r = store.dueAlarms(store.now()).ring;
    if (r) store.dismissWake(r);
  }
  goTo(at(19, 5, 0)); // 다음 주 월요일
  store.ensureDay(store.now());
  const s = store.getState();
  expect(s.correction!.history.at(-1)!.decision).toBe('stepUp');
  expect(formatHm(s.plans['2026-10-19'].wake)).toBe('07:30');
});

test('예시 데이터로 통계와 셋 데이 캘린더를 계산할 수 있다', () => {
  const now = at(19, 10, 0);
  goTo(now);
  const s = demoState(now);
  const week = periodStats(s, weekKeys(addDays(now, -7)), now);
  expect(week.days).toHaveLength(7);
  expect(week.setDays).toBeGreaterThan(0);
  expect(week.setDays).toBeLessThan(7);
  expect(s.inbox[0]?.suggestion?.ruleId).toBe('R1');
  expect(dateKey(s.wakes.at(-1)!.at)).toBe('2026-10-19');
});

describe('2일 관찰', () => {
  test('오후에 시작하면 다음 날이 1일차, 1일차에는 일정·알람·코칭이 없다', () => {
    goTo(at(19, 20, 45));
    store.startObservation();
    expect(store.getState().observation).toMatchObject({ phase: 'recording', day1: '2026-10-20' });
    store.tap('sleep');
    goTo(at(20, 7, 40));
    store.ensureDay(store.now());
    expect(Object.keys(store.getState().plans)).toHaveLength(0);
    expect(store.dueAlarms(store.now()).ring).toBeNull();
    store.tap('meal'); // 수면 끝 → 기상 기록
    expect(store.getState().wakes[0].day).toBe('2026-10-20');
    expect(store.getState().inbox).toHaveLength(0);
  });

  test('1일차 기록을 읽고, 바꾼 것만 반영해 2일차 일정을 만든다', () => {
    goTo(at(19, 23, 50));
    store.startObservation();
    store.tap('sleep');
    goTo(at(20, 8, 10));
    store.tap('meal');
    goTo(at(20, 8, 35));
    store.tap('work');
    goTo(at(20, 12, 40));
    store.tap('meal');
    goTo(at(20, 13, 30));
    store.tap('work');
    goTo(at(20, 19, 5));
    store.tap('meal');
    goTo(at(20, 21, 0));

    const o = observedDay(store.getState(), '2026-10-20', store.now());
    expect(formatHm(o.wakeAt!)).toBe('08:10');
    expect(formatHm(o.meals['점심 식사']!.start)).toBe('12:40');
    expect(o.exercise).toBeNull();
    expect(formatHm(o.work!.start)).toBe('08:35');

    // 바꾸고 싶은 것: 기상 07:00, 점심 12:00. 나머지는 기록 그대로.
    store.completeObservation({
      goals: {
        wake: 7 * 60,
        sleepMinutes: 420,
        meals: [
          { title: '아침 식사', activity: 'meal', start: 8 * 60 + 10, minutes: 25 },
          { title: '점심 식사', activity: 'meal', start: 12 * 60, minutes: 50 },
          { title: '저녁 식사', activity: 'meal', start: 19 * 60 + 5, minutes: 60 },
        ],
        exercise: null,
      },
      settings: { focusStart: 8 * 60 + 35, focusEnd: 11 * 60 + 35 },
      recordedWake: 8 * 60 + 10,
    });
    const s = store.getState();
    expect(s.observation).toMatchObject({ phase: 'trial', day2: '2026-10-21' });
    expect(s.plans['2026-10-20']).toBeUndefined(); // 1일차는 일정 없음
    const day2 = s.plans['2026-10-21'];
    // 70분 차이 → 단계적 교정: 첫 주는 기록한 08:10
    expect(formatHm(day2.wake)).toBe('08:10');
    expect(s.correction!.plan.totalWeeks).toBe(3);
    expect(formatHm(day2.blocks.find((b) => b.title === '점심 식사')!.start)).toBe('12:00');
  });

  test('2일차 저녁: 20분 넘게 어긋난 습관만 다시 묻고 관찰을 끝낸다', () => {
    goTo(at(19, 23, 50));
    store.startObservation();
    goTo(at(20, 21, 0));
    store.completeObservation({ goals: structuredClone(DEFAULT_GOALS), settings: {}, recordedWake: 7 * 60 });
    goTo(at(21, 12, 45));
    store.tap('meal'); // 점심 12:00 예정 → 12:45
    goTo(at(21, 18, 35));
    store.tap('meal'); // 저녁 18:30 예정 → 18:35 (5분, 묻지 않음)
    goTo(at(21, 21, 30));
    store.finishEvening('2026-10-21');
    const s = store.getState();
    expect(s.observation!.phase).toBe('done');
    const asks = s.inbox.filter((i) => i.suggestion?.ruleId === 'OBS');
    expect(asks).toHaveLength(1);
    expect(asks[0].message).toBe('점심 식사를 12:00으로 정했는데 오늘은 12:45에 시작했어요. 12:45으로 옮길까요?');
    store.acceptSuggestion(asks[0].id);
    expect(store.getState().goals.meals.find((m) => m.title === '점심 식사')!.start).toBe(12 * 60 + 45);
  });

  test('첫 캘린더 일정 때 이동 시간을 한 번만 묻고 저장한다', () => {
    goTo(at(19, 9, 0));
    store.startObservation();
    store.saveEvent({ id: 'e1', title: '수업', start: at(22, 9), end: at(22, 10) }, 20);
    const s = store.getState();
    expect(s.settings.travelMinutes).toBe(20);
    expect(s.asked.travel).toBe(true);
  });
});
