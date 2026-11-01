import { buildDay, decideWakeChange, estimateMissing } from '../scheduleBuilder';
import { blockMinutes, DEFAULT_SETTINGS, type HabitGoals, isEstimate, overlaps, type TaskItem } from '../models';

const at = (h: number, m: number, day = 14) => new Date(2026, 9, day, h, m);

const goals: HabitGoals = {
  wake: 7 * 60,
  sleepMinutes: 420,
  meals: [
    { title: '아침 식사', activity: 'meal', start: 7 * 60 + 30, minutes: 30 },
    { title: '점심 식사', activity: 'meal', start: 12 * 60, minutes: 60 },
    { title: '저녁 식사', activity: 'meal', start: 18 * 60 + 30, minutes: 60 },
  ],
  exercise: { title: '운동', activity: 'exercise', start: 20 * 60 + 30, minutes: 30 },
};
const settings = DEFAULT_SETTINGS;

const task = (p: Partial<TaskItem> & Pick<TaskItem, 'id' | 'title' | 'estMinutes' | 'dueAt'>): TaskItem => ({
  type: 'work',
  priority: 'normal',
  focus: false,
  doneMinutes: 0,
  ...p,
});

describe('기상·취침 계산', () => {
  test('첫 일정이 늦으면 목표 기상을 그대로 쓴다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      fixedEvents: [{ id: 'e1', title: '출근', start: at(9, 0), end: at(18, 0) }],
    });
    expect(plan.wake).toEqual(at(7, 0));
    // 07:00 − 수면 420분 − 잠들기 15분 = 전날 23:45
    expect(plan.bedTonight).toEqual(at(23, 45, 13));
    expect(plan.alarms[0].reason).toContain('목표 기상');
  });

  test('첫 일정이 이르면 준비·이동 시간만큼 당긴다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      fixedEvents: [{ id: 'e1', title: '팀 회의', start: at(8, 0), end: at(9, 0) }],
    });
    // 08:00 − 준비 50분 − 이동 40분 = 06:30
    expect(plan.wake).toEqual(at(6, 30));
    expect(plan.alarms[0].reason).toContain('첫 일정 08:00');
    expect(plan.blocks.some((b) => b.title === '이동' && b.end.getTime() === at(8, 0).getTime())).toBe(true);
  });

  test('코칭으로 앞당긴 취침 시간을 반영한다', () => {
    const plan = buildDay({ date: at(0, 0), goals, settings: { ...settings, bedEarlierMinutes: 15 } });
    expect(plan.bedTonight).toEqual(at(23, 30, 13));
  });

  test('취침 기록 뒤 기상 알람은 앞당기기만 자동으로 한다', () => {
    expect(decideWakeChange({ current: at(7, 0), proposed: at(6, 40), sleepLogged: true })).toBe('apply');
    expect(decideWakeChange({ current: at(7, 0), proposed: at(7, 20), sleepLogged: true })).toBe('needsConfirmation');
    expect(decideWakeChange({ current: at(7, 0), proposed: at(7, 20), sleepLogged: false })).toBe('apply');
  });
});

describe('습관 뼈대', () => {
  test('고정 일정과 겹친 습관은 뒤로 민다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings: { ...settings, travelMinutes: 0 },
      fixedEvents: [{ id: 'e1', title: '점심 미팅', start: at(11, 30), end: at(12, 30) }],
    });
    const lunch = plan.blocks.find((b) => b.title === '점심 식사')!;
    expect(lunch.start).toEqual(at(12, 30));
    expect(lunch.end).toEqual(at(13, 30));
  });
});

describe('할 일 배치', () => {
  test('50분 조각으로 나누고 블록끼리 겹치지 않는다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [task({ id: 't1', title: '분기 보고서', estMinutes: 180, dueAt: at(18, 0, 16), focus: true })],
    });
    const chunks = plan.blocks.filter((b) => b.taskId === 't1');
    expect(chunks.reduce((s, b) => s + blockMinutes(b), 0)).toBe(180);
    expect(chunks.every((b) => blockMinutes(b) <= 50)).toBe(true);
    expect(plan.deferred).toHaveLength(0);

    const dayBlocks = plan.blocks.slice(1); // 첫 블록은 전날 밤 수면
    for (let i = 0; i < dayBlocks.length; i++) {
      for (let j = i + 1; j < dayBlocks.length; j++) {
        expect(overlaps(dayBlocks[i], dayBlocks[j].start, dayBlocks[j].end)).toBe(false);
      }
    }
  });

  test('집중 작업은 집중 시간대(09~12시)에 먼저 넣는다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [task({ id: 't1', title: '기획서', estMinutes: 50, dueAt: at(23, 0), focus: true })],
    });
    expect(plan.blocks.find((b) => b.taskId === 't1')!.start).toEqual(at(9, 0));
  });

  test('빈 시간의 75%를 넘기면 다음 날로 넘긴다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [task({ id: 't1', title: '큰 과제', estMinutes: 900, dueAt: at(23, 0, 20) })],
    });
    expect(plan.taskMinutes).toBeLessThanOrEqual(Math.floor(plan.freeMinutes * 0.75));
    expect(plan.deferred).toHaveLength(1);
    expect(plan.deferred[0].reason).toBe('budget');
    expect(plan.deferred[0].minutes).toBe(900 - plan.taskMinutes);
  });

  test('마감 전에 들어갈 자리가 없으면 다음 날로 넘긴다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [task({ id: 't1', title: '아침 보고', estMinutes: 50, dueAt: at(7, 30) })],
    });
    expect(plan.deferred[0].reason).toBe('noSlot');
  });

  test('마감이 빠른 할 일을 먼저 넣는다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [
        task({ id: 'late', title: '나중 마감', estMinutes: 50, dueAt: at(23, 0, 18) }),
        task({ id: 'soon', title: '오늘 마감', estMinutes: 50, dueAt: at(17, 0) }),
      ],
    });
    const soon = plan.blocks.find((b) => b.taskId === 'soon')!;
    const late = plan.blocks.find((b) => b.taskId === 'late')!;
    expect(soon.start.getTime()).toBeLessThan(late.start.getTime());
  });

  test('사용자가 끌어서 정한 순서가 마감보다 먼저다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      tasks: [
        task({ id: 'soon', title: '마감 빠름', estMinutes: 50, dueAt: at(23, 0, 18), rank: 1 }),
        task({ id: 'top', title: '내가 맨 위에 둔 일', estMinutes: 50, dueAt: at(23, 0, 25), rank: 0 }),
      ],
    });
    const top = plan.blocks.find((b) => b.taskId === 'top')!;
    const soon = plan.blocks.find((b) => b.taskId === 'soon')!;
    expect(top.start.getTime()).toBeLessThan(soon.start.getTime());
  });

  test('하루 중간에 다시 짜면 지금 이후에만 할 일을 넣는다', () => {
    const plan = buildDay({
      date: at(0, 0),
      goals,
      settings,
      notBefore: at(14, 0),
      tasks: [task({ id: 't1', title: '정리', estMinutes: 50, dueAt: at(23, 0), focus: true })],
    });
    expect(plan.blocks.find((b) => b.taskId === 't1')!.start.getTime()).toBeGreaterThanOrEqual(at(14, 0).getTime());
  });
});

describe('추정 기록', () => {
  test('블록 시작 10분 뒤까지 기록이 없으면 추정 기록을 만든다', () => {
    const plan = buildDay({ date: at(0, 0), goals, settings });
    const est = estimateMissing({ blocks: plan.blocks, logs: [], now: at(7, 45) });
    expect(est.some((l) => l.activity === 'meal' && l.start.getTime() === at(7, 30).getTime())).toBe(true);
    expect(est.every(isEstimate)).toBe(true);
  });
});
