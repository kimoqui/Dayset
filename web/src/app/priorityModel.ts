// 우선순위 학습(기기 안에서 동작). 사용자가 할 일 순서를 끌어서 바꾼 기록과
// 먼저 끝낸 할 일을 모아, 며칠 뒤부터 추천 순서를 제안한다.
//
// 배우는 것(사람이 읽을 수 있는 이유로 설명할 수 있는 것만):
//  - 종류 선호: 업무·과제·숙제·개인 중 무엇을 위에 두는지
//  - 길이 선호: 짧은 일을 먼저 하는지, 긴 일을 먼저 하는지
//  - 오래된 일: 오래 묵은 일을 위로 올리는지
// 앱 버전에서는 같은 자료를 서버 AI에 넘겨 더 많은 신호(시간대·마감·기분)로 넓힌다.

import { dateKey, TASK_TYPE, type TaskItem, type TaskType } from '../engine/models';

export interface OrderSample {
  type: TaskType;
  est: number;
  /** 만든 지 며칠 지났는지. */
  age: number;
  /** 0 = 맨 위, 1 = 맨 아래. */
  pos: number;
}

export interface LearningLog {
  /** 순서를 바꿀 때마다 그 순서를 남긴다. */
  reorders: { at: Date; items: Omit<OrderSample, 'pos'>[] }[];
  /** 할 일을 끝낼 때 그때의 순서 위치를 남긴다(먼저 끝낸 일 = 실제로 중요하게 다룬 일). */
  completions: { at: Date; type: TaskType; est: number; age: number; pos: number }[];
  /** 추천을 '그대로 두기'로 넘긴 날. 같은 날에는 다시 묻지 않는다. */
  dismissedDay?: string;
}

export const emptyLearning = (): LearningLog => ({ reorders: [], completions: [] });

export const LEARN_DAYS = 3;

export interface Prefs {
  days: number;
  samples: number;
  typePref: Record<TaskType, number>;
  /** +면 짧은 일을 먼저, −면 긴 일을 먼저. */
  lenSlope: number;
  /** +면 오래된 일을 먼저. */
  ageSlope: number;
}

const TYPES = Object.keys(TASK_TYPE) as TaskType[];
const TYPE_FIRST: Record<TaskType, string> = { work: '업무를', assignment: '과제를', homework: '숙제를', personal: '개인 일을' };

function corr(xs: number[], ys: number[]): number {
  const n = xs.length;
  if (n < 3) return 0;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let sxy = 0;
  let sxx = 0;
  let syy = 0;
  for (let i = 0; i < n; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) ** 2;
    syy += (ys[i] - my) ** 2;
  }
  return sxx === 0 || syy === 0 ? 0 : sxy / Math.sqrt(sxx * syy);
}

export function samplesOf(log: LearningLog): OrderSample[] {
  const out: OrderSample[] = [];
  for (const r of log.reorders) {
    const n = r.items.length;
    if (n < 2) continue;
    r.items.forEach((it, i) => out.push({ ...it, pos: i / (n - 1) }));
  }
  for (const c of log.completions) out.push({ type: c.type, est: c.est, age: c.age, pos: c.pos * 0.5 });
  return out;
}

/** 배운 선호. 며칠치가 모이기 전에는 null. */
export function learnPrefs(log: LearningLog): Prefs | null {
  const days = new Set([...log.reorders.map((r) => dateKey(r.at)), ...log.completions.map((c) => dateKey(c.at))]).size;
  const samples = samplesOf(log);
  if (days < LEARN_DAYS || samples.length < 6) return null;
  const typePref = {} as Record<TaskType, number>;
  for (const t of TYPES) {
    const xs = samples.filter((s) => s.type === t).map((s) => s.pos);
    // 자료가 적은 종류는 가운데(0.5) 쪽으로 당긴다.
    typePref[t] = (xs.reduce((a, b) => a + b, 0) + 0.5 * 2) / (xs.length + 2);
  }
  const pos = samples.map((s) => s.pos);
  const lenSlope = corr(samples.map((s) => Math.log(s.est + 1)), pos); // 길수록 아래 → 짧은 일 먼저(+)
  const ageSlope = -corr(samples.map((s) => s.age), pos); // 오래될수록 위 → +
  return { days, samples: samples.length, typePref, lenSlope, ageSlope };
}

export interface Suggestion {
  order: string[];
  reasons: string[];
  /** 지금 순서에서 자리가 바뀌는 할 일 수. */
  moved: number;
}

const ageDays = (t: TaskItem, now: Date) => (t.createdAt ? Math.max(0, (now.getTime() - t.createdAt.getTime()) / 86400000) : 0);

/** 추천 순서. 지금 순서와 같으면 null. */
export function suggestOrder(tasks: TaskItem[], prefs: Prefs, now: Date): Suggestion | null {
  if (tasks.length < 2) return null;
  const ests = tasks.map((t) => Math.log(t.estMinutes + 1));
  const lo = Math.min(...ests);
  const hi = Math.max(...ests);
  const ages = tasks.map((t) => ageDays(t, now));
  const maxAge = Math.max(1, ...ages);
  const score = (t: TaskItem, i: number) => {
    const len = hi > lo ? (ests[i] - lo) / (hi - lo) : 0.5;
    return prefs.typePref[t.type] + 0.35 * prefs.lenSlope * (len - 0.5) - 0.25 * prefs.ageSlope * (ages[i] / maxAge) + i * 0.001;
  };
  const order = tasks.map((t, i) => ({ id: t.id, s: score(t, i) })).sort((a, b) => a.s - b.s).map((x) => x.id);
  const moved = order.filter((id, i) => tasks[i].id !== id).length;
  if (moved === 0) return null;

  const reasons: string[] = [];
  const ranked = [...TYPES].sort((a, b) => prefs.typePref[a] - prefs.typePref[b]);
  const present = ranked.filter((t) => tasks.some((x) => x.type === t));
  if (present.length >= 2 && prefs.typePref[present[present.length - 1]] - prefs.typePref[present[0]] > 0.15) {
    reasons.push(`${TYPE_FIRST[present[0]]} 먼저 두는 편이에요`);
  }
  if (prefs.lenSlope > 0.2) reasons.push('짧은 일을 먼저 끝내는 편이에요');
  else if (prefs.lenSlope < -0.2) reasons.push('긴 일을 먼저 시작하는 편이에요');
  if (prefs.ageSlope > 0.2) reasons.push('오래된 일을 먼저 처리하는 편이에요');
  if (!reasons.length) reasons.push('최근 순서를 바꾼 방식과 비슷하게 맞췄어요');
  return { order, reasons, moved };
}

/** 순서를 바꿀 때 남길 기록. */
export function snapshot(tasks: TaskItem[], now: Date): LearningLog['reorders'][number] {
  return { at: now, items: tasks.map((t) => ({ type: t.type, est: t.estMinutes, age: Math.round(ageDays(t, now) * 10) / 10 })) };
}
