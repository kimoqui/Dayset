// 상태에서 화면에 필요한 값을 계산한다. 모두 순수 함수다.

import { type BlockOutcome, type HabitRate } from '../engine/achievement';
import { weekTarget } from '../engine/correction';
import {
  type Activity,
  type ActivityLog,
  addDays,
  addMin,
  dateKey,
  diffMin,
  formatClock,
  fromKey,
  type HabitGoals,
  type HabitSlot,
  isAfter,
  isBefore,
  isEstimate,
  isOpen,
  mondayOf,
  remainingMinutes,
  type ScheduleBlock,
  type TaskItem,
} from '../engine/models';
import { buildDay, type DayPlan, estimateMissing } from '../engine/scheduleBuilder';
import { type DayEvaluation, type DayMarks, evaluateDay } from '../engine/setDay';
import type { AppState, StoredPlan, WakeRecord } from './state';
import { plannedMinutes } from './duration';

/** 그 날 일정에 쓸 목표. 교정 중이면 이번 주 기상 목표, 코칭으로 바꾼 저녁 시각을 반영한다. */
export function effectiveGoals(s: AppState, key: string): HabitGoals {
  const g = s.goals;
  const c = s.correction;
  const o = s.overrides[key];
  const wake = o?.wake ?? (c && c.plan.status === 'active' ? weekTarget(c.plan) : g.wake);
  const shift = o?.dinnerShift ?? 0;
  const edit = (slot: HabitSlot): HabitSlot | null => {
    const e = o?.habits?.[slot.title];
    if (!e) return slot;
    if (e.skip) return null;
    return { ...slot, start: e.start ?? slot.start, minutes: e.minutes ?? slot.minutes };
  };
  const meals = g.meals
    .map((m) => (shift && m.title.includes('저녁') ? { ...m, start: m.start + shift } : m))
    .map(edit)
    .filter((m): m is HabitSlot => m != null);
  return { ...g, wake, meals, exercise: g.exercise ? edit(g.exercise) : null };
}

const creditedIds = (s: AppState): Set<string> => new Set(s.credits.map((c) => c.blockId));
const missedIds = (s: AppState): Set<string> => new Set(s.misses.map((m) => m.blockId));

/**
 * 다른 날 일정에 이미 잡힌 할 일 시간. 오늘 잡아 둔 조각을 내일 또 넣지 않도록 뺀다.
 * '했어요'로 반영한 조각은 doneMinutes에 이미 들어 있고, '못 했어요'는 다시 넣어야 하므로 뺀다.
 */
function reservedMinutes(s: AppState, blocks: ScheduleBlock[]): Map<string, number> {
  const credited = creditedIds(s);
  const missed = missedIds(s);
  const out = new Map<string, number>();
  for (const b of blocks) {
    if (b.kind !== 'task' || !b.taskId || credited.has(b.id) || missed.has(b.id)) continue;
    out.set(b.taskId, (out.get(b.taskId) ?? 0) + diffMin(b.end, b.start));
  }
  return out;
}

export function tasksForPlanning(s: AppState, reserved: Map<string, number>): TaskItem[] {
  // 목록 순서가 곧 우선순위다(사용자가 끌어서 정함).
  return s.tasks
    .filter((t) => !t.done)
    // 걸리는 시간은 지난 기록으로 보정한 시간(예상 × 비율 + 늘린 시간)으로 잡는다.
    .map((t, i) => ({ ...t, rank: i, estMinutes: plannedMinutes(t, s.durations), doneMinutes: t.doneMinutes + (reserved.get(t.id) ?? 0) }))
    .filter((t) => remainingMinutes(t) > 0);
}

/** 엔진으로 하루 일정을 새로 만든다(저장하지 않음). */
export function buildPlan(
  s: AppState,
  key: string,
  opts: { notBefore?: Date; reservedBlocks?: ScheduleBlock[] } = {},
): DayPlan {
  const plan = buildDay({
    date: fromKey(key),
    goals: effectiveGoals(s, key),
    settings: s.settings,
    fixedEvents: s.events,
    tasks: tasksForPlanning(s, reservedMinutes(s, opts.reservedBlocks ?? [])),
    notBefore: opts.notBefore,
  });
  const extra = s.overrides[key]?.notes ?? [];
  const c = s.correction;
  const alarms =
    c && c.plan.status === 'active' && plan.alarms[0].reason.startsWith('목표 기상')
      ? [
          { ...plan.alarms[0], reason: `단계적 교정: 이번 주 기상 목표 ${formatClock(weekTarget(c.plan))} (최종 ${formatClock(c.plan.target)})` },
          ...plan.alarms.slice(1),
        ]
      : plan.alarms;
  return { ...plan, alarms, notes: [...plan.notes, ...extra] };
}

/** 저장한 일정이 있으면 그것을, 없으면 지금 입력으로 만든 일정을 돌려준다. */
export function planFor(s: AppState, key: string, now: Date): DayPlan & { stored: boolean; outdated: boolean } {
  const stored = s.plans[key];
  if (stored) return { ...stored, stored: true, outdated: stored.inputsVersion < s.inputsVersion };
  const todayKey = dateKey(now);
  // 내일 일정은 오늘 남은 할 일 조각을 빼고 만든다.
  const reservedBlocks = key > todayKey ? (s.plans[todayKey]?.blocks ?? []) : [];
  return { ...buildPlan(s, key, { reservedBlocks }), stored: false, outdated: false };
}

export function storedFrom(plan: DayPlan, s: AppState, regen = 0): StoredPlan {
  return { ...plan, inputsVersion: s.inputsVersion, regen };
}

/** 하루 중간에 다시 짠다: 이미 지난 블록은 그대로 두고 남은 시간만 새로 채운다. */
export function regeneratePlan(s: AppState, key: string, now: Date): StoredPlan {
  const old = s.plans[key];
  const todayKey = dateKey(now);
  if (!old || key > todayKey) {
    const reservedBlocks = key > todayKey ? (s.plans[todayKey]?.blocks ?? []) : [];
    return storedFrom(buildPlan(s, key, { reservedBlocks }), s, (old?.regen ?? 0) + 1);
  }
  // 지금 하고 있는 할 일 조각은 끊지 않는다(그 할 일이 아직 남아 있을 때).
  const openIds = new Set(s.tasks.filter((t) => !t.done).map((t) => t.id));
  const current = old.blocks.filter((b) => b.kind === 'task' && !!b.taskId && openIds.has(b.taskId) && !isAfter(b.start, now) && isAfter(b.end, now));
  const kept = [...old.blocks.filter((b) => !isAfter(b.end, now)), ...current];
  const notBefore = current.reduce((m, b) => (isAfter(b.end, m) ? b.end : m), now);
  const fresh = buildPlan(s, key, { notBefore, reservedBlocks: kept });
  const regen = (old.regen ?? 0) + 1;
  const future = fresh.blocks
    .filter((b) => isAfter(b.end, now) && !(b.kind === 'task' && isBefore(b.start, notBefore)))
    .map((b) => ({ ...b, id: `r${regen}-${b.id}` }));
  const blocks = [...kept, ...future].sort((a, b) => a.start.getTime() - b.start.getTime());
  return {
    ...fresh,
    wake: old.wake,
    bedTonight: old.bedTonight,
    alarms: [old.alarms[0], ...fresh.alarms.slice(1)],
    blocks,
    inputsVersion: s.inputsVersion,
    regen,
  };
}

// ---------------------------------------------------------------------------
// 기록
// ---------------------------------------------------------------------------

export function currentLog(s: AppState): ActivityLog | null {
  for (let i = s.logs.length - 1; i >= 0; i--) if (isOpen(s.logs[i])) return s.logs[i];
  return null;
}

export function wakeRecord(s: AppState, key: string): WakeRecord | undefined {
  return s.wakes.find((w) => w.day === key);
}

/** 그 날 실제 기상 시각: 알람 끄기 기록, 없으면 기상 무렵에 끝난 수면 기록. */
export function wakeTime(s: AppState, key: string, plan: DayPlan): Date | null {
  const rec = wakeRecord(s, key);
  if (rec) return rec.at;
  const from = addMin(plan.wake, -180);
  const to = addMin(plan.wake, 240);
  const sleep = s.logs.find(
    (l) => l.activity === 'sleep' && l.end && !isEstimate(l) && !isBefore(l.end, from) && !isAfter(l.end, to),
  );
  return sleep?.end ?? null;
}

export function logsAround(s: AppState, key: string): ActivityLog[] {
  const day = fromKey(key);
  const from = addMin(day, -12 * 60);
  const to = addMin(addDays(day, 1), 6 * 60);
  return s.logs.filter((l) => !isBefore(l.start, from) && isBefore(l.start, to));
}

export function marksFor(s: AppState, key: string): DayMarks {
  return {
    missed: new Set(s.misses.filter((m) => m.day === key).map((m) => m.blockId)),
    skipped: new Set(s.skips.filter((m) => m.day === key).map((m) => m.blockId)),
    rest: s.restDays.includes(key),
  };
}

export interface DayView extends DayEvaluation {
  key: string;
  plan: DayPlan;
  hasData: boolean;
}

/** 하루 평가(달성·셋 데이). 일정이 저장되지 않은 지난 날은 데이터 없음으로 본다. */
export function evaluate(s: AppState, key: string, now: Date): DayView {
  const todayKey = dateKey(now);
  const plan = planFor(s, key, now);
  const observing = !!s.observation && (s.observation.phase === 'recording' || key <= s.observation.day1);
  const hasData = !observing && key <= todayKey && (plan.stored || key === todayKey);
  const logs = logsAround(s, key);
  const marks = marksFor(s, key);
  // 같은 활동을 다른 시각에 확정 기록했다면 '기록 없음(추정)'이 아니라 시각을 놓친 것이다.
  const loggedOffTime = (b: ScheduleBlock): boolean =>
    logs.some(
      (l) =>
        l.activity === b.activity &&
        !isEstimate(l) &&
        isBefore(l.start, addMin(b.end, 120)) &&
        isAfter(l.end ?? now, addMin(b.start, -120)),
    );
  const target = plan.blocks.filter((b) => !marks.skipped.has(b.id) && !loggedOffTime(b));
  const estimates = estimateMissing({ blocks: target, logs, now });
  const ev = evaluateDay({
    blocks: plan.blocks,
    logs: [...logs, ...estimates],
    wake: plan.wake,
    wakeAt: wakeTime(s, key, plan),
    now,
    goalSleepMinutes: s.goals.sleepMinutes,
    marks,
  });
  return { ...ev, key, plan, hasData };
}

/**
 * 저녁 확인에서 물을 일정: 시작한 습관·할 일 중 기록으로 달성이 확인되지 않은 것 + 이미 답한 것.
 * open은 아직 답하지 않은 것(‘남은 건 일정대로 했어요’로 한 번에 채울 대상).
 */
export function eveningAsk(s: AppState, key: string, now: Date): { blocks: ScheduleBlock[]; open: ScheduleBlock[] } {
  const view = evaluate(s, key, now);
  const missed = new Set(s.misses.filter((m) => m.day === key).map((m) => m.blockId));
  const skipped = new Set(s.skips.filter((m) => m.day === key).map((m) => m.blockId));
  const did = new Set(s.logs.filter((l) => l.source === 'evening').map((l) => l.id.replace(/^ev-/, '')));
  const answered = (b: ScheduleBlock) => did.has(b.id) || missed.has(b.id) || skipped.has(b.id);
  const blocks = view.plan.blocks.filter((b) => {
    if (!b.activity || b.kind === 'fixed' || b.activity === 'sleep') return false;
    if (isAfter(b.start, now)) return false;
    if (answered(b)) return true;
    const o = view.outcomes.find((x) => x.block.id === b.id);
    return o != null && o.outcome !== 'achieved' && o.outcome !== 'pending';
  });
  return { blocks, open: blocks.filter((b) => !answered(b)) };
}

/** 오늘 습관 진행도(기록 직후·위젯에 보여 준다). 저녁 확인 머리와 같은 숫자. */
export function todayProgress(s: AppState, now: Date): { achieved: number; total: number } {
  const v = evaluate(s, dateKey(now), now);
  return { achieved: v.achieved, total: v.total };
}

export function weekKeys(now: Date, offsetWeeks = 0): string[] {
  const mon = addDays(mondayOf(now), offsetWeeks * 7);
  return Array.from({ length: 7 }, (_, i) => dateKey(addDays(mon, i)));
}

export function monthKeys(year: number, month: number): string[] {
  const days = new Date(year, month + 1, 0).getDate();
  return Array.from({ length: days }, (_, i) => dateKey(new Date(year, month, i + 1)));
}

export interface PeriodStats {
  days: DayView[];
  setDays: number;
  rates: Partial<Record<Activity | 'task', HabitRate>>;
}

/** 기간 통계: 셋 데이 수와 습관별 달성률. 할 일 블록은 'task'로 따로 센다. */
export function periodStats(s: AppState, keys: string[], now: Date): PeriodStats {
  const todayKey = dateKey(now);
  const days = keys.filter((k) => k <= todayKey).map((k) => evaluate(s, k, now)).filter((d) => d.hasData);
  const outcomes: BlockOutcome[] = days.flatMap((d) => d.outcomes);
  const rates: PeriodStats['rates'] = {};
  for (const o of outcomes) {
    const k = o.block.kind === 'task' ? 'task' : o.block.activity!;
    const r = rates[k] ?? { activity: o.block.activity!, achieved: 0, counted: 0, estimated: 0 };
    rates[k] = {
      ...r,
      achieved: r.achieved + (o.outcome === 'achieved' ? 1 : 0),
      counted: r.counted + (o.outcome === 'achieved' || o.outcome === 'missed' ? 1 : 0),
      estimated: r.estimated + (o.outcome === 'estimated' ? 1 : 0),
    };
  }
  return { days, setDays: days.filter((d) => d.isSetDay).length, rates };
}

/** 저녁 확인에서 물어볼 블록: 이미 끝났고, 달성으로 확인되지 않은 습관·할 일. */
export function openQuestions(view: DayView, now: Date): BlockOutcome[] {
  return view.outcomes.filter(
    (o) => !isAfter(o.block.start, now) && o.outcome !== 'achieved' && o.outcome !== 'pending' && o.block.activity !== 'sleep',
  );
}

export function weekMonday(key: string): string {
  return dateKey(mondayOf(fromKey(key)));
}

/** 최근 기상 기록의 스누즈 횟수(오래된 것부터, 마지막이 오늘). */
export function recentSnoozes(s: AppState, todayKey: string, days = 7): number[] {
  const today = fromKey(todayKey);
  const out: number[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const rec = wakeRecord(s, dateKey(addDays(today, -i)));
    if (rec) out.push(rec.snoozes);
  }
  return out;
}

// ---------------------------------------------------------------------------
// 1일차 관찰: 기록에서 하루 모습을 읽는다
// ---------------------------------------------------------------------------

export type MealSlot = '아침 식사' | '점심 식사' | '저녁 식사';
export const MEAL_SLOTS: MealSlot[] = ['아침 식사', '점심 식사', '저녁 식사'];

export interface ObservedDay {
  key: string;
  /** 일어난 시각(그날 아침 끝난 수면 기록, 없으면 기상 기록). */
  wakeAt: Date | null;
  /** 그날 밤 잠든 시각(이미 기록했으면). */
  bedAt: Date | null;
  /** 첫 기록 시각. 일어난 시각을 모를 때 기본값으로 쓴다. */
  firstLogAt: Date | null;
  meals: Partial<Record<MealSlot, { start: Date; minutes: number }>>;
  exercise: { start: Date; minutes: number } | null;
  work: { start: Date; end: Date; minutes: number } | null;
  logCount: number;
}

const mealSlotOf = (d: Date): MealSlot => {
  const m = d.getHours() * 60 + d.getMinutes();
  return m < 10 * 60 + 30 ? '아침 식사' : m < 15 * 60 ? '점심 식사' : '저녁 식사';
};

export function observedDay(s: AppState, key: string, now: Date): ObservedDay {
  const day = fromKey(key);
  const from = addMin(day, 3 * 60);
  const to = addMin(addDays(day, 1), 3 * 60);
  const confirmed = s.logs.filter((l) => !isEstimate(l));
  const inDay = confirmed.filter((l) => !isBefore(l.start, from) && isBefore(l.start, to));
  const end = (l: ActivityLog): Date => l.end ?? now;
  const minutes = (l: ActivityLog): number => Math.max(1, diffMin(end(l), l.start));

  const morningSleep = confirmed.find(
    (l) => l.activity === 'sleep' && l.end && !isBefore(l.end, from) && isBefore(l.end, addMin(day, 15 * 60)),
  );
  const wakeAt = morningSleep?.end ?? s.wakes.find((w) => w.day === key)?.at ?? null;
  // 그날 밤 수면: 저녁 6시 이후 ~ 다음 날 새벽 3시 사이에 시작한 수면 기록
  const night = inDay.find((l) => l.activity === 'sleep' && !isBefore(l.start, addMin(day, 18 * 60)));

  const meals: ObservedDay['meals'] = {};
  for (const l of inDay.filter((x) => x.activity === 'meal')) {
    const slot = mealSlotOf(l.start);
    if (!meals[slot]) meals[slot] = { start: l.start, minutes: minutes(l) };
  }
  const ex = inDay.find((l) => l.activity === 'exercise');
  const works = inDay.filter((l) => l.activity === 'work');
  const work =
    works.length > 0
      ? {
          start: works[0].start,
          end: works.map(end).reduce((a, b) => (isAfter(a, b) ? a : b)),
          minutes: works.reduce((n, l) => n + minutes(l), 0),
        }
      : null;
  return {
    key,
    wakeAt,
    bedAt: night?.start ?? null,
    firstLogAt: inDay.filter((l) => l.activity !== 'sleep')[0]?.start ?? null,
    meals,
    exercise: ex ? { start: ex.start, minutes: minutes(ex) } : null,
    work,
    logCount: inDay.length,
  };
}

/** 시각을 5분 단위로 맞춘 자정 기준 분. */
export function roundedClock(d: Date): number {
  return Math.round((d.getHours() * 60 + d.getMinutes()) / 5) * 5;
}

// ---------------------------------------------------------------------------
// 일정이 어떻게 바뀌는지(캘린더 일정 추가 미리보기, 시연 비교)
// ---------------------------------------------------------------------------

export interface PlanChange {
  kind: 'wake' | 'bed' | 'moved' | 'dropped' | 'tasks' | 'deferred';
  text: string;
}

const hm = (d: Date): string => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
const dur = (m: number): string => {
  const h = Math.trunc(m / 60);
  const r = m % 60;
  return h === 0 ? `${r}분` : r === 0 ? `${h}시간` : `${h}시간 ${r}분`;
};

/** 두 일정의 차이를 사람이 읽는 문장으로. */
export function comparePlans(before: DayPlan, after: DayPlan): PlanChange[] {
  const out: PlanChange[] = [];
  if (before.wake.getTime() !== after.wake.getTime()) {
    out.push({ kind: 'wake', text: `기상 알람 ${hm(before.wake)} → ${hm(after.wake)} (${after.alarms[0].reason})` });
  }
  if (before.bedTonight.getTime() !== after.bedTonight.getTime()) {
    out.push({ kind: 'bed', text: `전날 밤 취침 ${hm(before.bedTonight)} → ${hm(after.bedTonight)}` });
  }
  const habits = (p: DayPlan) => p.blocks.filter((b) => b.kind === 'habit' && b.activity !== 'sleep');
  for (const b of habits(before)) {
    const a = habits(after).find((x) => x.title === b.title);
    if (!a) out.push({ kind: 'dropped', text: `${b.title}: 겹쳐서 이날은 빠져요` });
    else if (a.start.getTime() !== b.start.getTime()) out.push({ kind: 'moved', text: `${b.title} ${hm(b.start)} → ${hm(a.start)} (겹쳐서 뒤로)` });
  }
  if (before.taskMinutes !== after.taskMinutes) {
    out.push({ kind: 'tasks', text: `할 일 ${dur(before.taskMinutes)} → ${dur(after.taskMinutes)}` });
  }
  const deferredMin = (p: DayPlan) => p.deferred.reduce((n, d) => n + d.minutes, 0);
  if (deferredMin(after) > deferredMin(before)) {
    out.push({ kind: 'deferred', text: `다음 날로 넘기는 할 일 ${dur(deferredMin(after) - deferredMin(before))} 늘어요` });
  }
  return out;
}

/** 이 캘린더 일정을 넣으면 그 날 일정이 어떻게 바뀌는지. */
export function eventImpact(s: AppState, ev: { id: string; title: string; start: Date; end: Date }, now: Date): PlanChange[] {
  const key = dateKey(ev.start);
  const todayKey = dateKey(now);
  const reservedBlocks = key > todayKey ? (s.plans[todayKey]?.blocks ?? []) : [];
  const opts = key === todayKey ? { notBefore: now } : { reservedBlocks };
  const before = buildPlan(s, key, opts);
  const after = buildPlan({ ...s, events: [...s.events.filter((e) => e.id !== ev.id), ev] }, key, opts);
  return comparePlans(before, after);
}
