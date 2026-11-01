import { leaderboard, makeFriendCode, readFriendCode } from '../social';
import { computeStreak, reachedMilestone } from '../streak';
import { demoState } from '../seed';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';

const at = (day: number, h: number, m = 0) => new Date(2026, 9, day, h, m);

describe('연속 셋 데이', () => {
  test('예시 데이터: 연속 기록은 최고 기록을 넘지 않고, 이번 주 7칸을 돌려준다', () => {
    const now = at(19, 22, 0);
    const info = computeStreak(demoState(now), now);
    expect(info.week).toHaveLength(7);
    expect(info.best).toBeGreaterThanOrEqual(info.current);
    expect(info.best).toBeGreaterThan(0);
  });

  test('매일 셋 데이를 채우면 하루씩 늘고, 쉬는 날은 끊지 않는다', () => {
    store.setFixedClock(at(12, 6, 0));
    store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: { travelMinutes: 0 }, usualWake: 7 * 60 });
    const perfectDay = (d: number) => {
      store.setFixedClock(at(d, 7, 2));
      store.ensureDay(store.now());
      const r = store.dueAlarms(store.now()).ring;
      if (r) store.dismissWake(r);
      for (const [h, m, a] of [[7, 32, 'meal'], [8, 10, 'work'], [12, 3, 'meal'], [13, 0, 'work'], [18, 35, 'meal'], [19, 30, 'rest'], [20, 31, 'exercise'], [21, 5, 'rest'], [23, 46, 'sleep']] as const) {
        store.setFixedClock(at(d, h, m));
        store.tap(a);
      }
    };
    perfectDay(13);
    perfectDay(14);
    store.setFixedClock(at(15, 9, 0));
    store.ensureDay(store.now());
    store.setRestDay('2026-10-15', true); // 쉬는 날
    perfectDay(16);
    store.setFixedClock(at(16, 23, 50));
    const info = computeStreak(store.getState(), store.now());
    expect(info.current).toBe(3); // 13·14·16 (15일은 쉬는 날이라 끊기지 않음)
    expect(info.todayDone).toBe(true);
    expect(reachedMilestone(info, '2026-10-16', undefined)).toBe(3);
    expect(reachedMilestone(info, '2026-10-16', '3@2026-10-16')).toBeNull();
    store.setFixedClock(null);
  });
});

describe('친구 코드와 순위', () => {
  const info = { current: 5, best: 9, todayDone: true, week: [], weekSetDays: 3, monthSetDays: 7, nextMilestone: 2 };

  test('코드를 만들고 메시지 전체에서 다시 읽는다(한글 이름 포함)', () => {
    const code = makeFriendCode({ id: 'u-abc', name: '대희' }, info, at(19, 21));
    const f = readFriendCode(`같이 겨뤄요!\n${code}\n`)!;
    expect(f).toMatchObject({ id: 'u-abc', name: '대희', streak: 5, best: 9, weekSetDays: 3, week: '2026-10-19' });
    expect(readFriendCode('아무 글')).toBeNull();
    expect(readFriendCode('DS1-망가진코드입니다아아아아')).toBeNull();
  });

  test('이번 주 셋 데이 → 연속 기록 순으로 정렬하고, 지난주 코드는 0일로 본다', () => {
    const now = at(21, 12);
    const rows = leaderboard({ id: 'me', name: '나' }, info, [
      { id: 'a', name: '지민', streak: 12, best: 20, week: '2026-10-19', weekSetDays: 3, monthSetDays: 10, updatedAt: now },
      { id: 'b', name: '현우', streak: 2, best: 4, week: '2026-10-19', weekSetDays: 4, monthSetDays: 4, updatedAt: now },
      { id: 'c', name: '서연', streak: 9, best: 9, week: '2026-10-12', weekSetDays: 7, monthSetDays: 9, updatedAt: now },
    ], now);
    expect(rows.map((r) => r.name)).toEqual(['현우', '지민', '나', '서연']);
    expect(rows[3]).toMatchObject({ stale: true, weekSetDays: 0 });
  });
});
