import { applyChanges, CoachingEngine, CoachingPolicy, type CoachRecord, parseRules } from '../coaching';
import { type Activity, ACTIVITY_LABEL, addMin, blockMinutes, type BlockKind, type ScheduleBlock } from '../models';

const at = (h: number, m: number, day = 14) => new Date(2026, 9, day, h, m);

const b = (id: string, a: Activity, s: Date, minutes: number, kind: BlockKind = 'habit', focus = false): ScheduleBlock => ({
  id,
  kind,
  activity: a,
  title: ACTIVITY_LABEL[a],
  start: s,
  end: addMin(s, minutes),
  focus,
});

const engine = new CoachingEngine();
const today = [
  b('ex', 'exercise', at(20, 30), 30),
  b('f1', 'work', at(9, 0), 50, 'task', true),
  b('f2', 'work', at(10, 0), 50, 'task', true),
  b('f3', 'work', at(14, 0), 50, 'task', true),
];

test('R1: 6시간 미만 수면이면 운동을 줄이고 집중 작업을 2개로 제한한다', () => {
  const s = engine.evaluate({ type: 'wakeLogged', sleepMinutes: 340 }, { today, now: at(7, 0) });
  expect(s).toHaveLength(1);
  expect(s[0].ruleId).toBe('R1');
  expect(s[0].message).toBe('어젯밤 5시간 40분 잤어요. 오늘 운동을 15분 가벼운 루틴으로 바꿀까요?');
  expect(s[0].changes.filter((c) => c.deferToTomorrow).map((c) => c.blockId)).toEqual(['f3']);

  const applied = applyChanges(today, s[0].changes);
  const ex = applied.blocks.find((x) => x.id === 'ex')!;
  expect(blockMinutes(ex)).toBe(15);
  expect(ex.adjusted).toBe(true);
  expect(applied.deferred.map((x) => x.id)).toEqual(['f3']);
});

test('R1: 잠을 충분히 잤으면 제안하지 않는다', () => {
  expect(engine.evaluate({ type: 'wakeLogged', sleepMinutes: 400 }, { today, now: at(7, 0) })).toHaveLength(0);
});

test('R3: 업무가 60분 이상 늦게 끝나면 운동을 줄인다', () => {
  const s = engine.evaluate({ type: 'workEnded', planned: at(18, 0), actual: at(19, 10) }, { today, now: at(19, 10) });
  expect(s[0].message.startsWith('업무가 예정보다 1시간 10분 늦게 끝났어요.')).toBe(true);
});

test('R4: 3일 연속 스누즈 3회 이상이면 취침을 앞당긴다', () => {
  const s = engine.evaluate({ type: 'wakeLogged', sleepMinutes: 420, recentSnoozes: [1, 3, 4, 3] }, { today, now: at(7, 0) });
  expect(s).toHaveLength(1);
  expect(s[0].ruleId).toBe('R4');
  expect(s[0].patch.bedtime_shift_minutes).toBe(-15);
});

test('R2: 저녁을 취침 3시간 안에 마치면 내일 저녁을 앞당긴다', () => {
  const s = engine.evaluate({ type: 'dinnerLogged', end: at(21, 30), bedtime: at(23, 30) }, { today, now: at(21, 30) });
  expect(s[0].message.startsWith('저녁을 취침 2시간 전에 마쳤어요.')).toBe(true);
});

test('R6·R7: 조사(을/를, 이/가)를 받침에 맞춘다', () => {
  const r6 = engine.evaluate({ type: 'missReason', habit: 'exercise', reason: 'forgot', weekCount: 2 }, { today, now: at(21, 0) });
  expect(r6[0].message.startsWith('이번 주 운동을 깜빡해서 2번 놓쳤어요.')).toBe(true);
  const r7 = engine.evaluate({ type: 'missReason', habit: 'meal', reason: 'conflict', weekCount: 2 }, { today, now: at(21, 0) });
  expect(r7[0].message.startsWith('이번 주 식사가 일·약속과 2번 겹쳤어요.')).toBe(true);
});

test('실패 이유가 한 번뿐이면 제안하지 않는다', () => {
  expect(engine.evaluate({ type: 'missReason', habit: 'sleep', reason: 'tired', weekCount: 1 }, { today, now: at(21, 0) })).toHaveLength(0);
});

describe('제안 빈도 제한', () => {
  const policy = new CoachingPolicy();

  test('하루 3건까지만 보여준다', () => {
    const history: CoachRecord[] = [0, 1, 2].map((i) => ({ ruleId: `R${i}`, at: at(8 + i, 0), decision: 'accepted' }));
    expect(policy.allows('R5', at(21, 0), history)).toBe(false);
    expect(policy.allows('R5', at(9, 0, 15), history)).toBe(true);
  });

  test('같은 규칙을 2번 연속 거절하면 7일 쉰다', () => {
    const history: CoachRecord[] = [
      { ruleId: 'R1', at: at(7, 0, 10), decision: 'rejected' },
      { ruleId: 'R1', at: at(7, 0, 11), decision: 'rejected' },
    ];
    expect(policy.allows('R1', at(7, 0, 14), history)).toBe(false);
    expect(policy.allows('R1', at(7, 0, 18), history)).toBe(true);
  });

  test('규칙을 끄면 제안하지 않는다', () => {
    const off = new CoachingEngine(parseRules([{ id: 'R1', enabled: false }]));
    expect(off.evaluate({ type: 'wakeLogged', sleepMinutes: 300 }, { today, now: at(7, 0) })).toHaveLength(0);
  });
});
