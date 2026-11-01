// 연속 셋 데이(스트릭). 듀오링고처럼 매일 이어 가는 기록이다.
//
// - 오늘은 아직 끝나지 않았으므로, 오늘이 셋 데이가 아니어도 어제까지의 연속은 이어진다.
// - 쉬는 날은 연속을 끊지 않지만 날짜 수에도 세지 않는다(듀오링고의 '스트릭 프리즈'와 같은 역할).
// - 일정이 없던 날(앱을 쓰기 전, 관찰 기간)에서 멈춘다.

import { addDays, dateKey, fromKey } from '../engine/models';
import { evaluate, monthKeys, weekKeys } from './derive';
import type { AppState } from './state';

export const MILESTONES = [3, 7, 14, 30, 50, 100, 200, 365];

export type DayMark = 'set' | 'rest' | 'miss' | 'today' | 'none' | 'future';

export interface StreakInfo {
  current: number;
  best: number;
  /** 오늘 셋 데이를 이미 채웠는지. */
  todayDone: boolean;
  /** 이번 주 월~일 표시. */
  week: { key: string; mark: DayMark }[];
  weekSetDays: number;
  monthSetDays: number;
  /** 다음 기념일까지 남은 날. */
  nextMilestone: number | null;
}

function markOf(s: AppState, key: string, now: Date): DayMark {
  const todayKey = dateKey(now);
  if (key > todayKey) return 'future';
  const v = evaluate(s, key, now);
  if (!v.hasData) return 'none';
  if (v.isSetDay) return 'set';
  if (v.rest) return 'rest';
  return key === todayKey ? 'today' : 'miss';
}

export function computeStreak(s: AppState, now: Date): StreakInfo {
  const todayKey = dateKey(now);
  const cache = new Map<string, DayMark>();
  const mark = (k: string): DayMark => {
    let m = cache.get(k);
    if (!m) {
      m = markOf(s, k, now);
      cache.set(k, m);
    }
    return m;
  };

  // 현재 연속
  const todayMark = mark(todayKey);
  let current = todayMark === 'set' ? 1 : 0;
  for (let i = 1; i < 800; i++) {
    const m = mark(dateKey(addDays(now, -i)));
    if (m === 'set') current++;
    else if (m === 'rest') continue;
    else break;
  }

  // 최고 기록: 일정이 있는 날만 시간순으로 훑는다.
  const keys = Object.keys(s.plans).filter((k) => k <= todayKey).sort();
  let best = 0;
  let run = 0;
  let prev: string | null = null;
  for (const k of keys) {
    // 날짜가 비면(일정 없는 날) 연속이 끊긴다.
    if (prev && dateKey(addDays(fromKey(prev), 1)) !== k) run = 0;
    const m = mark(k);
    if (m === 'set') run++;
    else if (m !== 'rest' && m !== 'today') run = 0;
    best = Math.max(best, run);
    prev = k;
  }
  best = Math.max(best, current);

  const week = weekKeys(now).map((key) => ({ key, mark: mark(key) }));
  const month = monthKeys(now.getFullYear(), now.getMonth()).filter((k) => k <= todayKey);
  const next = MILESTONES.find((m) => m > current) ?? null;
  return {
    current,
    best,
    todayDone: todayMark === 'set',
    week,
    weekSetDays: week.filter((d) => d.mark === 'set').length,
    monthSetDays: month.filter((k) => mark(k) === 'set').length,
    nextMilestone: next == null ? null : next - current,
  };
}

/** 오늘 새로 도달한 기념일. 같은 날 같은 기념일은 한 번만 축하한다(celebrated = '7@2026-10-19'). */
export function reachedMilestone(info: StreakInfo, todayKey: string, celebrated: string | undefined): number | null {
  if (!info.todayDone || !MILESTONES.includes(info.current)) return null;
  return celebrated === `${info.current}@${todayKey}` ? null : info.current;
}
