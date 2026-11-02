// 기록을 이어 가게 하는 장치: 저녁 확인 '남은 건 일정대로 했어요', 오늘 진행도.
// Flutter test/app/habit_loop_test.dart와 같은 기대값.

import { eveningAsk, evaluate, todayProgress } from '../derive';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';

const at = (h: number, m = 0) => new Date(2026, 9, 19, h, m);
const day = '2026-10-19';

beforeEach(() => {
  store.resetAll();
  store.setFixedClock(at(6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
});

test('저녁에 기록 없는 일정은 한 번에 일정대로 채우고, 다르게 한 것만 남긴다', () => {
  store.setFixedClock(at(21, 0));
  const before = eveningAsk(store.getState(), day, store.now());
  expect(before.open.length).toBeGreaterThan(1);
  // 하나는 '못 했어요'로 먼저 답한다 → 한 번에 채울 때 건드리지 않는다
  const first = before.open[0];
  store.markMissed(day, first, 'conflict');
  const n = store.markRestAsPlanned(day);
  expect(n).toBe(before.open.length - 1);
  const after = eveningAsk(store.getState(), day, store.now());
  expect(after.open).toEqual([]);
  expect(store.getState().misses.some((m) => m.blockId === first.id)).toBe(true);
  const v = evaluate(store.getState(), day, store.now());
  expect(v.achieved).toBe(v.total - 1);
  // 다시 눌러도 더 채울 것이 없다
  expect(store.markRestAsPlanned(day)).toBe(0);
});

test('오늘 진행도는 저녁 확인 머리와 같은 숫자', () => {
  store.setFixedClock(at(12, 5));
  store.tap('meal');
  const p = todayProgress(store.getState(), store.now());
  const v = evaluate(store.getState(), day, store.now());
  expect(p).toEqual({ achieved: v.achieved, total: v.total });
  expect(p.achieved).toBeGreaterThanOrEqual(1);
});
