// 앱 상태 저장소와 동작. 화면은 여기 있는 함수만 부른다.

import { useSyncExternalStore } from 'react';
import { applyChanges, CoachingEngine, type CoachEvent, type CoachingSuggestion, objectParticle } from '../engine/coaching';
import { createCorrection, DECISION_LABEL, weeklyUpdate, weekTarget } from '../engine/correction';
import {
  type Activity,
  type ActivityLog,
  addDays,
  addMin,
  blockMinutes,
  dateKey,
  diffMin,
  type FixedEvent,
  formatClock,
  formatDuration,
  formatHm,
  fromKey,
  type HabitGoals,
  isAfter,
  isBefore,
  type MissReason,
  mondayOf,
  type PersonalSettings,
  type ScheduleBlock,
  type TaskItem,
} from '../engine/models';
import { NowTracker } from '../engine/nowTracker';
import {
  buildPlan,
  currentLog,
  evaluate,
  eveningAsk,
  planFor,
  recentSnoozes,
  regeneratePlan,
  storedFrom,
  wakeRecord,
  weekKeys,
} from './derive';
import { type AppState, type CalendarSource, type Consent, type FeedbackReport, type GoalIntent, type InboxItem, initialState, loadState, type NotifyPrefs, type SaveResult, saveState, type SurveyAnswer } from './state';
import { addSample, plannedMinutes } from './duration';
import { addEvent, addOpen } from './metrics';
import type { ImportedEvent } from './ics';
import type { Friend } from './social';
import { snapshot } from './priorityModel';
import { applyEdit, type ScheduleEdit } from './edits';
import { retimeLogs } from './logEdit';

// ---------------------------------------------------------------------------
// 시계. 주소에 ?t=2026-10-19T07:00 을 붙이면 그 시각부터 흐른다(시험용).
// ---------------------------------------------------------------------------

let clockOffset = 0;
try {
  const t = new URLSearchParams(location.search).get('t');
  if (t) {
    const d = new Date(t);
    if (!Number.isNaN(d.getTime())) clockOffset = d.getTime() - Date.now();
  }
} catch {
  // 주소를 읽을 수 없는 환경
}

let fixedClock: number | null = null;
export const now = (): Date => new Date(fixedClock ?? Date.now() + clockOffset);
/** 테스트용: 시계를 멈춘 시각으로 고정한다(null이면 해제). */
export const setFixedClock = (d: Date | null): void => {
  fixedClock = d ? d.getTime() : null;
};
export const setClockOffset = (ms: number): void => {
  clockOffset = ms;
  emit();
};
export const getClockOffset = (): number => clockOffset;

// ---------------------------------------------------------------------------
// 저장소
// ---------------------------------------------------------------------------

let state: AppState = loadState();
let saveResult: SaveResult = 'ok';
const listeners = new Set<() => void>();

function emit(): void {
  for (const l of listeners) l();
}

export function getState(): AppState {
  return state;
}

export function storageAvailable(): boolean {
  return saveResult === 'ok';
}

/** 마지막 저장 결과: 'quota'면 저장 공간이 가득 찼다. */
export function storageProblem(): SaveResult {
  return saveResult;
}

function set(fn: (s: AppState) => AppState): void {
  state = fn(state);
  saveResult = saveState(state);
  emit();
}

export function replaceState(next: AppState): void {
  state = next;
  tracker = null;
  saveResult = saveState(state);
  emit();
}

/** 상태가 바뀔 때마다 부른다(계정 동기화 등 화면 밖에서 듣는 곳). */
export function subscribe(l: () => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function useAppState(): AppState {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => state,
  );
}

let idSeq = 0;
export const newId = (prefix: string): string => `${prefix}-${Date.now().toString(36)}-${(idSeq++).toString(36)}`;

const bump = (s: AppState): AppState => ({ ...s, inputsVersion: s.inputsVersion + 1 });

// ---------------------------------------------------------------------------
// 하루 시작·일정 확정
// ---------------------------------------------------------------------------

/** 오늘 일정이 없으면 지금 입력으로 만들어 고정한다. 주간 교정 판정도 여기서 한다. */
export function ensureDay(t = now()): void {
  if (!state.onboarded || state.observation?.phase === 'recording') return;
  const key = dateKey(t);
  // 관찰 1일차까지는 일정이 없다.
  if (state.observation && key <= state.observation.day1) return;
  let changed = false;
  let s = state;
  const weekly = runWeeklyCorrection(s, t);
  if (weekly) {
    s = weekly;
    changed = true;
  }
  if (!s.plans[key]) {
    s = { ...s, plans: { ...s.plans, [key]: storedFrom(buildPlan(s, key, { notBefore: t }), s) } };
    changed = true;
  }
  if (changed) set(() => s);
}

function runWeeklyCorrection(s: AppState, t: Date): AppState | null {
  const c = s.correction;
  const thisWeek = dateKey(mondayOf(t));
  if (!c || c.plan.status !== 'active' || c.lastUpdateWeek >= thisWeek) return null;
  const lastWeek = weekKeys(addDays(t, -7));
  const days = lastWeek.map((k) => evaluate(s, k, t)).filter((d) => d.hasData && !d.rest);
  const rate = days.length ? days.filter((d) => d.wakeOk).length / days.length : null;
  const tired = s.misses.filter((m) => m.reason === 'tired' && lastWeek.includes(m.day)).length;
  if (rate == null) return { ...s, correction: { ...c, lastUpdateWeek: thisWeek } };
  const r = weeklyUpdate(c.plan, { achievementRate: rate, tiredCount: c.holdNext ? Math.max(2, tired) : tired });
  const target = weekTarget(r.plan);
  const info: InboxItem = {
    id: newId('info'),
    day: dateKey(t),
    createdAt: t,
    kind: 'info',
    status: 'pending',
    message:
      r.decision === 'done'
        ? `기상 목표 ${formatClock(target)}에 도달했어요. 지난주 기상 달성 ${Math.round(rate * 100)}%.`
        : `이번 주 기상 목표는 ${formatClock(target)}이에요. 지난주 기상 달성 ${Math.round(rate * 100)}% · ${DECISION_LABEL[r.decision]}.`,
  };
  return bump({
    ...s,
    correction: {
      plan: r.plan,
      lastUpdateWeek: thisWeek,
      holdNext: false,
      history: [...c.history, { week: thisWeek, decision: r.decision, rate, target }],
    },
    inbox: [...s.inbox, info],
  });
}

/** 저장한 일정을 지금 입력으로 다시 짠다. */
export function regenerate(key: string): void {
  const t = now();
  set((s) => ({ ...s, plans: { ...s.plans, [key]: regeneratePlan(s, key, t) } }));
}

/** 내일 일정을 지금 입력으로 고정한다(저녁 확인·취침 기록 때). */
function lockTomorrow(s: AppState, t: Date): AppState {
  const tomorrow = dateKey(addDays(t, 1));
  if (s.plans[tomorrow]) return s;
  // 관찰 1일차(기록만 하는 날)에는 일정을 만들지 않는다.
  if (s.observation && (s.observation.phase === 'recording' || tomorrow <= s.observation.day1)) return s;
  const today = s.plans[dateKey(t)];
  return {
    ...s,
    plans: { ...s.plans, [tomorrow]: storedFrom(buildPlan(s, tomorrow, { reservedBlocks: today?.blocks ?? [] }), s) },
  };
}

// ---------------------------------------------------------------------------
// '지금' 버튼
// ---------------------------------------------------------------------------

let tracker: NowTracker | null = null;
let trackerSynced: ActivityLog[] | null = null;

function syncedTracker(): NowTracker {
  if (!tracker || trackerSynced !== state.logs) {
    tracker = new NowTracker({ logs: state.logs, idGenerator: () => newId('log') });
  }
  return tracker;
}

function commitLogs(s: AppState, logs: ActivityLog[]): AppState {
  trackerSynced = logs;
  return { ...s, logs };
}

export interface TapOutcome {
  changed: boolean;
  merged?: boolean;
}

export function tap(activity: Activity, source: ActivityLog['source'] = 'button'): TapOutcome {
  const t = now();
  const tr = syncedTracker();
  const before = currentLog(state);
  const r = tr.tap(activity, t, { source });
  if (!r.changed) return { changed: false };
  let s = commitLogs(state, tr.logs);
  const todayKey = dateKey(t);

  // 아침에 수면 기록이 끝나면 기상으로 기록한다.
  if (before?.activity === 'sleep' && r.ended && !wakeRecord(s, todayKey)) {
    s = recordWake(s, t, 'button', s.alarms[`${todayKey}|wake`]?.snoozes ?? 0, r.ended);
  }
  // 저녁 식사 끝(R2), 업무 끝(R3)
  if (r.ended?.activity === 'meal' && r.ended.start.getHours() >= 17) {
    const bed = planFor(s, dateKey(addDays(t, 1)), t).bedTonight;
    s = coach(s, { type: 'dinnerLogged', end: t, bedtime: bed }, t);
  }
  if (r.ended?.activity === 'work') {
    const plan = planFor(s, todayKey, t);
    const ends = plan.blocks
      .filter((b) => b.kind === 'task' || (b.kind === 'fixed' && b.locked))
      .map((b) => b.end)
      .filter((e) => e.getHours() < 22);
    if (ends.length) {
      const planned = ends.reduce((a, b) => (isAfter(a, b) ? a : b));
      s = coach(s, { type: 'workEnded', planned, actual: t }, t);
    }
  }
  // 저녁에 잠들면 내일 일정과 알람을 고정한다(알람은 이후 앞당기기만).
  if (activity === 'sleep' && t.getHours() >= 18) {
    s = lockTomorrow(s, t);
    s = { ...s, alarms: { ...s.alarms, [`${dateKey(addDays(t, 1))}|bed`]: { snoozes: 0, done: true } } };
  }
  set(() => s);
  return { changed: true, merged: r.merged };
}

export function canUndo(): boolean {
  return !!tracker && trackerSynced === state.logs && tracker.canUndo(now());
}

export function undoTap(): boolean {
  const tr = syncedTracker();
  if (!tr.undo(now())) return false;
  set((s) => commitLogs(s, tr.logs));
  return true;
}

/** 기록 시각 고치기. 고치지 못하면 이유를 돌려준다. */
export function retimeLog(id: string, start: Date, end: Date | null): string | null {
  const r = retimeLogs(state.logs, id, start, end, now());
  if (!r.ok) return r.error;
  tracker = null; // 바꾼 기록으로 '지금' 버튼 상태를 새로 만든다(되돌리기는 끝난다).
  set((s) => ({ ...s, logs: r.logs }));
  track('log_retime');
  return null;
}

/**
 * 제때 누르지 못했을 때: at 시각부터 그 활동을 한 것으로 기록한다(앞 기록은 at에 끝난다).
 * at이 앞 기록보다 이르면 지금부터로 남기고 이유를 돌려준다.
 */
export function tapAt(activity: Activity, at: Date, source: ActivityLog['source'] = 'button'): TapOutcome & { error?: string } {
  const r = tap(activity, source);
  const cur = currentLog(state);
  if (!r.changed || !cur || cur.activity !== activity || diffMin(cur.start, at) < 1) return r;
  const err = retimeLog(cur.id, at, null);
  return err ? { ...r, error: err } : r;
}

export function deleteLog(id: string): void {
  set((s) => ({ ...s, logs: s.logs.filter((l) => l.id !== id) }));
}

/** 지금 상태를 끝내기만 한다. */
export function stopCurrent(): void {
  const tr = syncedTracker();
  if (!tr.stop(now())) return;
  set((s) => commitLogs(s, tr.logs));
}

// ---------------------------------------------------------------------------
// 알람
// ---------------------------------------------------------------------------

export type RingKind = 'wake' | 'bed';

export interface Ring {
  kind: RingKind;
  key: string;
  at: Date;
}

export interface Nudge {
  key: string;
  title: string;
  body: string;
}

/** 지금 울려야 할 알람과 보낼 알림을 찾는다. 앱 화면이 열려 있을 때만 동작한다. */
export function dueAlarms(t = now()): { ring: Ring | null; nudges: Nudge[] } {
  const s = state;
  if (!s.onboarded || s.observation?.phase === 'recording') return { ring: null, nudges: [] };
  const todayKey = dateKey(t);
  const observing = !!s.observation && todayKey <= s.observation.day1;
  const tomorrowKey = dateKey(addDays(t, 1));
  const cur = currentLog(s);
  const ready = (key: string, at: Date, windowMin: number): boolean => {
    const a = s.alarms[key];
    if (a?.done) return false;
    if (a?.snoozeUntil && isBefore(t, a.snoozeUntil)) return false;
    return !isBefore(t, at) && diffMin(t, at) < windowMin;
  };

  let ring: Ring | null = null;
  const today = planFor(s, todayKey, t);
  const wakeKey = `${todayKey}|wake`;
  if (!observing && !wakeRecord(s, todayKey) && ready(wakeKey, today.wake, 90)) ring = { kind: 'wake', key: wakeKey, at: today.wake };

  const tomorrow = planFor(s, tomorrowKey, t);
  const bedKey = `${tomorrowKey}|bed`;
  if (!ring && cur?.activity !== 'sleep' && ready(bedKey, tomorrow.bedTonight, 60)) {
    ring = { kind: 'bed', key: bedKey, at: tomorrow.bedTonight };
  }

  const nudges: Nudge[] = [];
  const windKey = `${tomorrowKey}|windDown`;
  const windAt = addMin(tomorrow.bedTonight, -s.settings.windDownMinutes);
  if (cur?.activity !== 'sleep' && ready(windKey, windAt, 20)) {
    nudges.push({ key: windKey, title: '마무리할 시간이에요', body: `${formatHm(tomorrow.bedTonight)} 취침 · 화면을 줄이고 씻을 준비를 해요` });
  }
  for (const b of observing ? [] : today.blocks) {
    const before = b.activity ? s.reminders[b.activity] : undefined;
    if (before == null || b.kind !== 'habit') continue;
    const key = `${todayKey}|remind|${b.id}`;
    if (ready(key, addMin(b.start, -before), 10)) {
      nudges.push({ key, title: `${before}분 뒤 ${b.title}`, body: `${formatHm(b.start)}에 시작해요` });
    }
  }
  return { ring, nudges };
}

export function markNudged(keys: string[]): void {
  if (!keys.length) return;
  set((s) => {
    const alarms = { ...s.alarms };
    for (const k of keys) alarms[k] = { ...(alarms[k] ?? { snoozes: 0 }), done: true };
    return { ...s, alarms };
  });
}

export function snooze(ring: Ring, minutes: number): void {
  const t = now();
  set((s) => {
    const a = s.alarms[ring.key] ?? { snoozes: 0 };
    return { ...s, alarms: { ...s.alarms, [ring.key]: { ...a, snoozes: a.snoozes + 1, snoozeUntil: addMin(t, minutes) } } };
  });
}

/** 기상 알람 끄기 = 기상 기록. 수면 기록이 열려 있으면 함께 끝낸다. */
export function dismissWake(ring: Ring): void {
  const t = now();
  const tr = syncedTracker();
  const cur = tr.current;
  let ended: ActivityLog | null = null;
  if (cur?.activity === 'sleep') ended = tr.stop(t);
  set((s) => {
    let next = ended ? commitLogs(s, tr.logs) : s;
    const a = next.alarms[ring.key] ?? { snoozes: 0 };
    next = { ...next, alarms: { ...next.alarms, [ring.key]: { ...a, done: true, snoozeUntil: null } } };
    return recordWake(next, t, 'alarm', a.snoozes, ended);
  });
}

/** 취침 알람: '잘게요'는 수면 시작 기록, '오늘은 끄기'는 알람만 끈다. */
export function dismissBed(ring: Ring, sleepNow: boolean): void {
  set((s) => ({ ...s, alarms: { ...s.alarms, [ring.key]: { ...(s.alarms[ring.key] ?? { snoozes: 0 }), done: true } } }));
  if (sleepNow) tap('sleep', 'alarm');
}

function recordWake(s: AppState, t: Date, source: 'alarm' | 'button', snoozes: number, sleepLog: ActivityLog | null): AppState {
  const day = dateKey(t);
  if (wakeRecord(s, day)) return s;
  let next: AppState = {
    ...s,
    wakes: [...s.wakes, { day, at: t, snoozes, source }],
    alarms: { ...s.alarms, [`${day}|wake`]: { ...(s.alarms[`${day}|wake`] ?? { snoozes }), done: true } },
  };
  const minutes = sleepLog?.end ? diffMin(sleepLog.end, sleepLog.start) : null;
  next = coach(
    next,
    { type: 'wakeLogged', sleepMinutes: minutes ?? next.goals.sleepMinutes, recentSnoozes: recentSnoozes(next, day) },
    t,
  );
  return next;
}

// ---------------------------------------------------------------------------
// 코칭
// ---------------------------------------------------------------------------

const engine = new CoachingEngine();

function coach(s: AppState, event: CoachEvent, t: Date): AppState {
  const day = dateKey(t);
  if (s.observation && (s.observation.phase === 'recording' || day <= s.observation.day1)) return s;
  const today = s.plans[day]?.blocks ?? [];
  const shownToday = s.inbox.filter((i) => i.kind === 'coach' && i.day === day && i.status === 'pending').length;
  const out = engine.evaluate(event, { today, now: t, history: s.coachHistory, shownToday });
  if (!out.length) return s;
  const items: InboxItem[] = out.map((sg) => ({
    id: newId('coach'),
    day,
    createdAt: t,
    kind: 'coach',
    suggestion: sg,
    message: sg.message,
    status: 'pending',
  }));
  return { ...s, inbox: [...s.inbox, ...items] };
}

export function pendingInbox(s: AppState, t = now()): InboxItem | null {
  const day = dateKey(t);
  return s.inbox.find((i) => i.status === 'pending' && i.day === day) ?? null;
}

export function recentResolved(s: AppState, t = now()): InboxItem | null {
  const day = dateKey(t);
  const done = s.inbox.filter((i) => i.day === day && (i.status === 'accepted' || i.status === 'kept'));
  return done.length ? done[done.length - 1] : null;
}

export function acceptSuggestion(id: string): void {
  const t = now();
  set((s) => {
    const item = s.inbox.find((i) => i.id === id);
    if (!item?.suggestion) return s;
    const { next, text, action } = applySuggestion(s, item.suggestion, t);
    return {
      ...next,
      coachHistory: [...next.coachHistory, { ruleId: item.suggestion.ruleId, at: t, decision: 'accepted' }],
      inbox: next.inbox.map((i) => (i.id === id ? { ...i, status: 'accepted', resultText: text, action } : i)),
    };
  });
}

export function keepSuggestion(id: string): void {
  const t = now();
  set((s) => {
    const item = s.inbox.find((i) => i.id === id);
    if (!item) return s;
    const history = item.suggestion
      ? [...s.coachHistory, { ruleId: item.suggestion.ruleId, at: t, decision: 'rejected' as const }]
      : s.coachHistory;
    return {
      ...s,
      coachHistory: history,
      inbox: s.inbox.map((i) =>
        i.id === id ? { ...i, status: item.kind === 'info' ? 'seen' : 'kept', resultText: '일정을 그대로 둘게요.' } : i,
      ),
    };
  });
}

function applySuggestion(
  s: AppState,
  sg: CoachingSuggestion,
  t: Date,
): { next: AppState; text: string; action?: 'settings' } {
  const todayKey = dateKey(t);
  const tomorrowKey = dateKey(addDays(t, 1));
  let next = s;
  let text = '자동 조정했어요.';
  let action: 'settings' | undefined;

  if (sg.changes.length && next.plans[todayKey]) {
    const plan = next.plans[todayKey];
    const applied = applyChanges(plan.blocks, sg.changes);
    next = { ...next, plans: { ...next.plans, [todayKey]: { ...plan, blocks: applied.blocks } } };
    const ex = applied.blocks.find((b) => b.adjusted && b.activity === 'exercise');
    const parts: string[] = [];
    if (ex) parts.push(`오늘 운동은 ${formatHm(ex.start)}부터 ${formatDuration(blockMinutes(ex))}이에요`);
    if (applied.deferred.length) parts.push(`집중 작업 ${applied.deferred.length}개는 내일로 넘겼어요`);
    text = `자동 조정했어요. ${parts.join('. ')}.`;
  }

  const p = sg.patch;
  const override = { ...(next.overrides[tomorrowKey] ?? {}) };
  let overrideChanged = false;
  if (typeof p.tomorrow_dinner_shift_minutes === 'number') {
    override.dinnerShift = p.tomorrow_dinner_shift_minutes;
    override.notes = [...(override.notes ?? []), '아침은 가벼운 메뉴로 추천해요'];
    overrideChanged = true;
    const dinner = next.goals.meals.find((m) => m.title.includes('저녁'));
    text = dinner
      ? `내일 저녁 식사를 ${formatClock(dinner.start + p.tomorrow_dinner_shift_minutes)}으로 앞당겼어요.`
      : '내일 저녁 식사를 앞당겼어요.';
  }
  if (p.next_meal_focus === 'protein') {
    override.notes = [...(override.notes ?? []), '첫 끼는 단백질 위주 메뉴로 추천해요'];
    overrideChanged = true;
    text = '내일 첫 끼는 단백질 위주 메뉴로 추천해요.';
  }
  if (overrideChanged) {
    next = { ...next, overrides: { ...next.overrides, [tomorrowKey]: override } };
    if (next.plans[tomorrowKey]) {
      next = { ...next, plans: { ...next.plans, [tomorrowKey]: regeneratePlan(next, tomorrowKey, t) } };
    }
  }
  if (typeof p.bedtime_shift_minutes === 'number') {
    const by = -p.bedtime_shift_minutes;
    next = bump({ ...next, settings: { ...next.settings, bedEarlierMinutes: next.settings.bedEarlierMinutes + by } });
    if (next.plans[tomorrowKey]) {
      next = { ...next, plans: { ...next.plans, [tomorrowKey]: regeneratePlan(next, tomorrowKey, t) } };
    }
    const bed = planFor(next, tomorrowKey, t).bedTonight;
    text = `취침 알람을 ${by}분 앞당겼어요. 오늘 밤 ${formatHm(bed)}이에요.`;
  }
  if (typeof p.remind_before_minutes === 'number' && typeof p.habit === 'string') {
    next = { ...next, reminders: { ...next.reminders, [p.habit as Activity]: p.remind_before_minutes } };
    text = `${p.remind_before_minutes}분 전에 알림으로 알려드릴게요.`;
  }
  if (p.suggest_move) {
    text = '설정의 습관 시간에서 옮길 시각을 골라주세요.';
    action = 'settings';
  }
  if (p.hold_correction_week) {
    if (next.correction) next = { ...next, correction: { ...next.correction, holdNext: true } };
    text = '다음 주는 교정 단계를 그대로 두고 수면부터 지켜요.';
  }
  if (typeof p.move_habit === 'string' && typeof p.start === 'number') {
    const title = p.move_habit;
    const start = p.start;
    const g = next.goals;
    next = bump({
      ...next,
      goals: {
        ...g,
        meals: g.meals.map((m) => (m.title === title ? { ...m, start } : m)),
        exercise: g.exercise && g.exercise.title === title ? { ...g.exercise, start } : g.exercise,
      },
    });
    if (next.plans[tomorrowKey]) {
      next = { ...next, plans: { ...next.plans, [tomorrowKey]: regeneratePlan(next, tomorrowKey, t) } };
    }
    text = `${title}${objectParticle(title)} ${formatClock(start)}으로 옮겼어요. 내일 일정부터 반영해요.`;
  }
  if (typeof p.shrink_to_minutes === 'number' && p.habit === 'exercise' && next.goals.exercise) {
    next = bump({ ...next, goals: { ...next.goals, exercise: { ...next.goals.exercise, minutes: p.shrink_to_minutes } } });
    text = `운동을 ${p.shrink_to_minutes}분으로 줄였어요. 다음 일정부터 반영해요.`;
  }
  return { next, text, action };
}

// ---------------------------------------------------------------------------
// 저녁 확인
// ---------------------------------------------------------------------------

const eveningLogId = (blockId: string): string => `ev-${blockId}`;

function clearMarks(s: AppState, day: string, b: ScheduleBlock): AppState {
  const credit = s.credits.find((c) => c.blockId === b.id);
  return {
    ...s,
    logs: s.logs.filter((l) => l.id !== eveningLogId(b.id)),
    misses: s.misses.filter((m) => !(m.day === day && m.blockId === b.id)),
    skips: s.skips.filter((m) => !(m.day === day && m.blockId === b.id)),
    credits: s.credits.filter((c) => c.blockId !== b.id),
    tasks: credit
      ? s.tasks.map((t) => (t.id === credit.taskId ? { ...t, doneMinutes: Math.max(0, t.doneMinutes - credit.minutes), done: false } : t))
      : s.tasks,
  };
}

function credit(s: AppState, day: string, b: ScheduleBlock): AppState {
  if (!b.taskId || s.credits.some((c) => c.blockId === b.id)) return s;
  const minutes = blockMinutes(b);
  return {
    ...s,
    credits: [...s.credits, { day, blockId: b.id, taskId: b.taskId, minutes }],
    tasks: s.tasks.map((t) =>
      t.id === b.taskId
        ? { ...t, doneMinutes: t.doneMinutes + minutes }
        : t,
    ),
  };
}

export function markDid(day: string, b: ScheduleBlock): void {
  set((s) => {
    let next = clearMarks(s, day, b);
    const log: ActivityLog = {
      id: eveningLogId(b.id),
      activity: b.activity ?? 'work',
      start: b.start,
      end: b.end,
      source: 'evening',
      confirmed: true,
      snoozeCount: 0,
    };
    next = commitLogs(next, [...next.logs, log].sort((a, c) => a.start.getTime() - c.start.getTime()));
    return credit(next, day, b);
  });
}

/**
 * 저녁 확인 '남은 건 일정대로 했어요': 아직 답하지 않은 일정을 모두 '했어요'로 채운다.
 * 다르게 한 것만 골라 고치면 되도록(기본값 = 일정대로). 채운 개수를 돌려준다.
 */
export function markRestAsPlanned(day: string): number {
  const t = now();
  const open = eveningAsk(state, day, t).open;
  if (!open.length) return 0;
  set((s) => {
    let next = s;
    for (const b of open) {
      next = clearMarks(next, day, b);
      const log: ActivityLog = { id: eveningLogId(b.id), activity: b.activity ?? 'work', start: b.start, end: b.end, source: 'evening', confirmed: true, snoozeCount: 0 };
      next = commitLogs(next, [...next.logs, log].sort((a, c) => a.start.getTime() - c.start.getTime()));
      next = credit(next, day, b);
    }
    return { ...next, metrics: addEvent(next.metrics, t, 'evening_all_planned') };
  });
  return open.length;
}

export function markMissed(day: string, b: ScheduleBlock, reason: MissReason): void {
  const t = now();
  set((s) => {
    let next = clearMarks(s, day, b);
    const activity = b.activity ?? 'work';
    next = { ...next, misses: [...next.misses, { day, blockId: b.id, activity, reason, at: t }] };
    const week = weekKeys(fromKey(day));
    const weekCount = next.misses.filter((m) => m.activity === activity && m.reason === reason && week.includes(m.day)).length;
    return coach(next, { type: 'missReason', habit: activity, reason, weekCount, habitMinutes: blockMinutes(b) }, t);
  });
}

export function markSkipped(day: string, b: ScheduleBlock): void {
  set((s) => {
    const next = clearMarks(s, day, b);
    return { ...next, skips: [...next.skips, { day, blockId: b.id }] };
  });
}

export function clearAnswer(day: string, b: ScheduleBlock): void {
  set((s) => clearMarks(s, day, b));
}

export function setRestDay(day: string, rest: boolean): void {
  set((s) => ({ ...s, restDays: rest ? [...new Set([...s.restDays, day])] : s.restDays.filter((d) => d !== day) }));
}

/** 저녁 확인 끝: 달성한 할 일 반영, 식사 코칭(R5), 내일 일정 확정. */
export function finishEvening(day: string): void {
  const t = now();
  set((s) => {
    let next = s;
    const view = evaluate(next, day, t);
    for (const o of view.outcomes) {
      if (o.block.kind === 'task' && o.outcome === 'achieved') next = credit(next, day, o.block);
    }
    const missedMeals = view.outcomes.filter((o) => o.block.activity === 'meal' && o.outcome === 'missed').length;
    next = coach(next, { type: 'eveningCheck', missedMeals }, t);
    if (next.observation?.phase === 'trial' && next.observation.day2 === day) next = endObservation(next, day, t);
    if (day === dateKey(t)) next = lockTomorrow(next, t);
    return { ...next, eveningDone: [...new Set([...next.eveningDone, day])] };
  });
}

// ---------------------------------------------------------------------------
// 할 일·캘린더·설정
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 할 일·캘린더가 바뀌면 오늘 남은 일정과 확정한 내일 일정을 바로 다시 짠다(되돌리기 15초).
// ---------------------------------------------------------------------------

/** 저장해 둔 오늘·내일 일정을 지금 입력으로 다시 짠다. 첫날 기록 중에는 짜지 않는다. */
function replan(s: AppState, t: Date): AppState {
  if (!s.onboarded || s.observation?.phase === 'recording') return s;
  let next = s;
  for (const key of [dateKey(t), dateKey(addDays(t, 1))]) {
    if (next.plans[key]) next = { ...next, plans: { ...next.plans, [key]: regeneratePlan(next, key, t) } };
  }
  return next;
}

/** 할 일 조각이 실제로 바뀌었는지 비교할 지문. */
function taskSig(s: AppState, t: Date): string {
  return [dateKey(t), dateKey(addDays(t, 1))]
    .map((k) => (s.plans[k]?.blocks ?? []).filter((b) => b.kind === 'task' && isAfter(b.end, t)).map((b) => `${b.taskId}@${b.start.getTime()}-${b.end.getTime()}`).join(','))
    .join('|');
}

export interface PlanChange {
  /** 남은 일정의 할 일 조각이 바뀌었는지. */
  replanned: boolean;
  /** 이번 변경으로 빈 시간이 모자라 오늘에서 밀려난 할 일 이름. */
  deferred: string[];
}

function deferredIds(s: AppState, t: Date): Set<string> {
  return new Set((s.plans[dateKey(t)]?.deferred ?? []).map((d) => d.taskId));
}

let planUndo: { state: AppState; at: number } | null = null;

function changeAndReplan(fn: (s: AppState, t: Date) => AppState): PlanChange {
  const t = now();
  const before = state;
  let replanned = false;
  let deferred: string[] = [];
  set((s) => {
    const next = replan(fn(s, t), t);
    replanned = taskSig(before, t) !== taskSig(next, t);
    const was = deferredIds(before, t);
    deferred = [...deferredIds(next, t)].filter((id) => !was.has(id)).map((id) => next.tasks.find((x) => x.id === id)?.title ?? '할 일');
    return next;
  });
  planUndo = { state: before, at: Date.now() };
  return { replanned, deferred };
}

export function canUndoPlan(): boolean {
  return !!planUndo && Date.now() - planUndo.at < 15000;
}

/** 방금 바꾼 할 일·캘린더와 그에 따라 다시 짠 일정을 함께 되돌린다. */
export function undoPlanChange(): boolean {
  if (!canUndoPlan()) return false;
  replaceState(planUndo!.state);
  planUndo = null;
  return true;
}

/** 일정 탭·채팅에서 고른 바꾸기를 적용하고 남은 일정을 다시 짠다(15초 되돌리기). */
export function applyEdits(edits: ScheduleEdit[]): PlanChange {
  return changeAndReplan((s, t) => {
    let next = s;
    for (const e of edits) next = applyEdit(next, e, t);
    return { ...next, metrics: addEvent(next.metrics, t, 'schedule_edit', edits.map((e) => e.kind).join(',')) };
  });
}

export function saveTask(task: TaskItem): PlanChange {
  return changeAndReplan((s, t) => {
    const exists = s.tasks.some((x) => x.id === task.id);
    return bump({ ...s, tasks: exists ? s.tasks.map((x) => (x.id === task.id ? task : x)) : [...s.tasks, task], metrics: exists ? s.metrics : addEvent(s.metrics, t, 'task_add') });
  });
}

/** 지금까지 그 할 일에 쓴 시간(사실만): 반영한 조각 + 오늘 일정에서 이미 지났거나 진행 중인 조각. */
export function spentMinutes(s: AppState, task: TaskItem, t: Date): number {
  const credited = new Set(s.credits.map((c) => c.blockId));
  const missed = new Set(s.misses.filter((m) => m.day === dateKey(t)).map((m) => m.blockId));
  const today = s.plans[dateKey(t)]?.blocks ?? [];
  let m = task.doneMinutes;
  for (const b of today) {
    if (b.kind !== 'task' || b.taskId !== task.id || credited.has(b.id) || missed.has(b.id) || !isBefore(b.start, t)) continue;
    m += diffMin(isBefore(b.end, t) ? b.end : t, b.start);
  }
  return Math.round(m);
}

export function toggleTaskDone(id: string): PlanChange {
  return changeAndReplan((s, t) => {
    const open = s.tasks.filter((x) => !x.done);
    const idx = open.findIndex((x) => x.id === id);
    const task = s.tasks.find((x) => x.id === id);
    let learning = s.learning;
    let durations = s.durations;
    if (task && !task.done) {
      // 끝낸 일과 그 일이 목록에서 몇 번째였는지 배운다.
      if (idx >= 0 && open.length > 1) {
        const age = task.createdAt ? (t.getTime() - task.createdAt.getTime()) / 86400000 : 0;
        learning = { ...learning, completions: [...learning.completions, { at: t, type: task.type, est: task.estMinutes, age, pos: idx / (open.length - 1) }].slice(-200) };
      }
      // 예상 대비 실제로 쓴 시간을 남긴다(알 수 없으면 남기지 않는다).
      durations = addSample(durations, { at: t, taskId: task.id, type: task.type, title: task.title, est: task.estMinutes, actual: spentMinutes(s, task, t) });
    } else if (task?.done) {
      // 완료를 취소하면 그 기록도 지운다.
      durations = { ...durations, samples: durations.samples.filter((x) => x.taskId !== id) };
    }
    return bump({ ...s, learning, durations, tasks: s.tasks.map((x) => (x.id === id ? { ...x, done: !x.done } : x)) });
  });
}

/** 잡은 시간을 다 썼는데 덜 끝났을 때: 시간을 늘려 다시 배치한다. */
export function extendTask(id: string, minutes: number): PlanChange {
  return changeAndReplan((s) => bump({ ...s, tasks: s.tasks.map((x) => (x.id === id ? { ...x, extraMinutes: (x.extraMinutes ?? 0) + minutes } : x)) }));
}

/** 일정에 잡을 시간(보정 + 늘린 시간)과 남은 시간. */
export function taskPlanMinutes(s: AppState, t: TaskItem): { planned: number; remaining: number } {
  const planned = plannedMinutes(t, s.durations);
  return { planned, remaining: Math.max(0, planned - t.doneMinutes) };
}

export function setDurationAuto(on: boolean): PlanChange {
  return changeAndReplan((s) => bump({ ...s, durations: { ...s.durations, on } }));
}

/** 끌어서 바꾼 순서를 저장한다(진행 중인 할 일만, 완료한 일은 뒤에 그대로). byUser면 학습 기록에도 남긴다. */
export function reorderTasks(ids: string[], byUser = true): PlanChange {
  return changeAndReplan((s, t) => {
    const byId = new Map(s.tasks.map((x) => [x.id, x]));
    const ordered = ids.map((id) => byId.get(id)).filter((x): x is TaskItem => !!x);
    const rest = s.tasks.filter((x) => !ids.includes(x.id));
    const learning = byUser ? { ...s.learning, reorders: [...s.learning.reorders, snapshot(ordered, t)].slice(-200) } : s.learning;
    return bump({ ...s, tasks: [...ordered, ...rest], learning });
  });
}

/** AI 추천을 오늘은 넘긴다. */
export function dismissOrderSuggestion(): void {
  const day = dateKey(now());
  set((s) => ({ ...s, learning: { ...s.learning, dismissedDay: day } }));
}

export function deleteTask(id: string): PlanChange {
  return changeAndReplan((s) => bump({ ...s, tasks: s.tasks.filter((t) => t.id !== id) }));
}

/** 캘린더 일정 저장. 첫 일정이면 이동 시간도 함께 받는다(필요한 순간에 한 번만 묻기). */
export function saveEvent(e: FixedEvent, travelMinutes?: number): PlanChange {
  return changeAndReplan((s) => {
    const exists = s.events.some((x) => x.id === e.id);
    let next = bump({ ...s, events: exists ? s.events.map((x) => (x.id === e.id ? e : x)) : [...s.events, e] });
    if (travelMinutes != null) {
      next = { ...next, settings: { ...next.settings, travelMinutes }, asked: { ...next.asked, travel: true } };
    }
    return next;
  });
}

export function deleteEvent(id: string): PlanChange {
  return changeAndReplan((s) => bump({ ...s, events: s.events.filter((e) => e.id !== id) }));
}

// ---------------------------------------------------------------------------
// 외부 캘린더 가져오기(구글 연결·.ics 파일)
// ---------------------------------------------------------------------------

/** 가져올 범위: 오늘 0시부터 14일. */
export function importWindow(t = now()): { from: Date; to: Date } {
  const from = new Date(t.getFullYear(), t.getMonth(), t.getDate());
  return { from, to: addDays(from, 14) };
}

/** 한 캘린더에서 가져오는 일정 최대 수(저장 공간 보호). */
export const MAX_IMPORT = 400;

const sameEvent = (a: { title: string; start: Date; end: Date }, b: { title: string; start: Date; end: Date }) =>
  a.title.replace(/\s+/g, '') === b.title.replace(/\s+/g, '') && Math.abs(a.start.getTime() - b.start.getTime()) < 60000 && Math.abs(a.end.getTime() - b.end.getTime()) < 60000;

export interface ImportOutcome extends PlanChange {
  count: number;
  /** 이미 직접 넣은(또는 다른 캘린더에서 가져온) 같은 일정이라 뺀 수. */
  dupes: number;
  /** 너무 많아 뺀 수. */
  capped: number;
}

/** 그 캘린더에서 가져온 일정을 통째로 바꾸고 남은 일정을 다시 짠다. */
export function importCalendar(src: Omit<CalendarSource, 'lastSync' | 'count'>, events: ImportedEvent[]): ImportOutcome {
  let count = 0;
  let dupes = 0;
  let capped = 0;
  const r = changeAndReplan((s, t) => {
    const others = s.events.filter((e) => e.source !== src.id);
    const fresh = events.filter((e) => {
      const dup = others.some((o) => sameEvent(o, e));
      if (dup) dupes++;
      return !dup;
    });
    capped = Math.max(0, fresh.length - MAX_IMPORT);
    const mine: FixedEvent[] = fresh.slice(0, MAX_IMPORT).map((e) => ({ id: `${src.id}:${e.uid}@${e.start.getTime()}`, title: e.title, start: e.start, end: e.end, source: src.id }));
    count = mine.length;
    const sources = [...s.calendars.filter((c) => c.id !== src.id), { ...src, lastSync: t, count }];
    return bump({ ...s, events: [...others, ...mine], calendars: sources });
  });
  return { ...r, count, dupes, capped };
}

/** 동기화 실패를 남긴다. 이전에 가져온 일정은 그대로 두고 그것으로 계속 짠다. */
export function markCalendarError(id: string, error: string | null, needsAuth = false): void {
  set((s) => ({ ...s, calendars: s.calendars.map((c) => (c.id === id ? { ...c, error: error ?? undefined, needsAuth: needsAuth || undefined } : c)) }));
}

/** 가져온 캘린더 연결을 끊고 그 일정을 지운다. */
export function removeCalendar(id: string): PlanChange {
  return changeAndReplan((s) => bump({ ...s, events: s.events.filter((e) => e.source !== id), calendars: s.calendars.filter((c) => c.id !== id) }));
}

export function setGoogleClientId(id: string): void {
  set((s) => ({ ...s, googleClientId: id.trim() }));
}

export function updateGoals(goals: HabitGoals): void {
  set((s) => bump({ ...s, goals }));
}

export function updateSettings(patch: Partial<PersonalSettings>): void {
  set((s) => bump({ ...s, settings: { ...s.settings, ...patch } }));
}

/** 기상 교정 계획을 만든다. 지금 기상과 목표가 30분 이상 차이 나면 단계로 나눈다. */
export function setCorrection(usualWake: number | null, stepSize = 30): void {
  const t = now();
  set((s) => {
    if (usualWake == null || Math.abs(usualWake - s.goals.wake) <= 30) return bump({ ...s, correction: null });
    const plan = createCorrection({ baseline: usualWake, target: s.goals.wake, stepSize });
    return bump({ ...s, correction: { plan, lastUpdateWeek: dateKey(mondayOf(t)), holdNext: false, history: [] } });
  });
}

export function completeOnboarding(p: {
  goals: HabitGoals;
  settings: Partial<PersonalSettings>;
  usualWake: number | null;
}): void {
  const t = now();
  const base = initialState();
  let s: AppState = { ...base, ...carryOver(state), onboarded: true, goals: p.goals, settings: { ...base.settings, ...p.settings } };
  if (p.usualWake != null && Math.abs(p.usualWake - p.goals.wake) > 30) {
    s.correction = {
      plan: createCorrection({ baseline: p.usualWake, target: p.goals.wake, stepSize: 30 }),
      lastUpdateWeek: dateKey(mondayOf(t)),
      holdNext: false,
      history: [],
    };
  }
  replaceState(s);
  ensureDay(t);
}

export function resetAll(): void {
  replaceState(initialState());
}

/** 처음 화면에서 정한 것(목표·동의·알림)과 익명 번호·지표는 시작할 때 그대로 가져간다. */
function carryOver(s: AppState): Partial<AppState> {
  return { profile: s.profile, intent: s.intent, consent: s.consent, notify: s.notify, metrics: firstTouch(s, now()) };
}

/** 처음 무언가를 한 시각을 설치 시각으로 둔다(앱 시계 기준). */
function firstTouch(s: AppState, t: Date): AppState['metrics'] {
  return s.metrics.events.length || s.metrics.opens.length ? s.metrics : { ...s.metrics, installAt: t };
}

// ---------------------------------------------------------------------------
// 처음 목표 · 동의 · 알림 · 일정 체크 · 지표 · 피드백
// ---------------------------------------------------------------------------

export function setIntent(intent: Omit<GoalIntent, 'setAt'>): void {
  const t = now();
  set((s) => {
    // 고른 목표를 기본 목표에도 바로 반영한다(기록 없이 바로 설정하는 길에서도 쓰도록).
    const goals = { ...s.goals, wake: intent.wake, sleepMinutes: intent.sleepMinutes };
    if (intent.focus.includes('exercise')) {
      const base = s.goals.exercise ?? { title: '운동', activity: 'exercise' as const, start: 20 * 60 + 30, minutes: 30 };
      goals.exercise = { ...base, minutes: intent.exerciseMinutes, title: intent.exerciseTitle ?? base.title, start: intent.exerciseStart ?? base.start };
    }
    return { ...s, goals, intent: { ...intent, setAt: t }, metrics: addEvent(firstTouch(s, t), t, 'goal_set', intent.focus.join(',')) };
  });
}

export function setConsent(p: { health: boolean; metrics: boolean }): void {
  const t = now();
  set((s) => ({ ...s, consent: { ...p, at: t, version: 1 } as Consent, metrics: addEvent(firstTouch(s, t), t, 'consent', p.metrics ? 'metrics' : 'health') }));
}

export function setNotify(patch: Partial<NotifyPrefs>): void {
  set((s) => ({ ...s, notify: { ...s.notify, ...patch } }));
}

/** 일정 체크에서 '지금은 안 해요': 그 조각은 다시 묻지 않는다. */
export function skipCheck(id: string): void {
  const t = now();
  set((s) => ({ ...s, checkSkips: [...s.checkSkips.filter((x) => x !== id), id].slice(-60), metrics: addEvent(s.metrics, t, 'check_skip') }));
}

/** 베타 지표에 행동 하나를 남긴다(내용·제목은 남기지 않는다). */
export function track(k: string, v?: string): void {
  const t = now();
  set((s) => ({ ...s, metrics: addEvent(s.metrics, t, k, v) }));
}

/** 오늘 앱을 열었음을 남긴다(하루 한 번). */
export function markOpen(t = now()): void {
  if (state.metrics.opens.includes(dateKey(t))) return;
  set((s) => ({ ...s, metrics: addOpen(s.metrics, t) }));
}

export function answerSurvey(a: Omit<SurveyAnswer, 'at'>): void {
  const t = now();
  set((s) => ({ ...s, feedback: { ...s.feedback, surveys: [...s.feedback.surveys.filter((x) => x.key !== a.key), { ...a, at: t }] } }));
}

export function surveyLater(): void {
  const day = dateKey(now());
  set((s) => ({ ...s, feedback: { ...s.feedback, surveyLater: day } }));
}

export function addReport(r: Omit<FeedbackReport, 'at'>): void {
  const t = now();
  set((s) => ({ ...s, feedback: { ...s.feedback, reports: [...s.feedback.reports, { ...r, text: r.text.slice(0, 1000), at: t }].slice(-50) } }));
}

// ---------------------------------------------------------------------------
// 2일 관찰
// ---------------------------------------------------------------------------

/** 설정 없이 시작: 1일차는 기록만 한다. 오후 3시 이후에 시작하면 다음 날이 1일차다. */
export function startObservation(): void {
  const t = now();
  const day1 = t.getHours() >= 15 ? dateKey(addDays(t, 1)) : dateKey(t);
  replaceState({ ...initialState(), ...carryOver(state), onboarded: true, observation: { phase: 'recording', day1, startedAt: t } });
}

/** 1일차 기록을 보고 바꿀 것만 고친 뒤 2일차 일정을 만든다. */
export function completeObservation(p: {
  goals: HabitGoals;
  settings: Partial<PersonalSettings>;
  /** 1일차에 실제로 일어난 시각. 목표와 30분 넘게 차이 나면 단계적으로 옮긴다. */
  recordedWake: number | null;
}): void {
  const t = now();
  set((s) => {
    const obs = s.observation;
    if (!obs) return s;
    const day2 = dateKey(addDays(fromKey(obs.day1), 1));
    let next: AppState = bump({ ...s, goals: p.goals, settings: { ...s.settings, ...p.settings } });
    next.correction =
      p.recordedWake != null && Math.abs(p.recordedWake - p.goals.wake) > 30
        ? {
            plan: createCorrection({ baseline: p.recordedWake, target: p.goals.wake, stepSize: 30 }),
            lastUpdateWeek: dateKey(mondayOf(t)),
            holdNext: false,
            history: [],
          }
        : null;
    next = { ...next, observation: { ...obs, phase: 'trial', day2 }, eveningDone: [...new Set([...next.eveningDone, obs.day1])] };
    const todayKey = dateKey(t);
    // 1일차 밤에 정리하면 2일차 일정을, 다음 날 정리하면 오늘 남은 일정을 만든다.
    const key = todayKey >= day2 ? todayKey : day2;
    const plan = buildPlan(next, key, key === todayKey ? { notBefore: t } : {});
    return { ...next, plans: { ...next.plans, [key]: storedFrom(plan, next) } };
  });
}

/** 2일차 저녁: 정한 시각과 실제가 20분 넘게 어긋난 습관만 다시 묻고 관찰을 끝낸다. */
function endObservation(s: AppState, day: string, t: Date): AppState {
  const view = evaluate(s, day, t);
  const items: InboxItem[] = [];
  for (const b of view.plan.blocks) {
    if (b.kind !== 'habit' || !b.activity || b.activity === 'sleep') continue;
    const logs = s.logs.filter((l) => l.activity === b.activity && l.source !== 'evening' && Math.abs(diffMin(l.start, b.start)) <= 120);
    if (!logs.length) continue;
    const actual = logs.reduce((a, c) => (Math.abs(diffMin(c.start, b.start)) < Math.abs(diffMin(a.start, b.start)) ? c : a));
    const drift = diffMin(actual.start, b.start);
    if (Math.abs(drift) < 20) continue;
    const start = Math.round((actual.start.getHours() * 60 + actual.start.getMinutes()) / 5) * 5;
    const title = b.title;
    const message = `${title}${objectParticle(title)} ${formatHm(b.start)}으로 정했는데 오늘은 ${formatHm(actual.start)}에 시작했어요. ${formatClock(start)}으로 옮길까요?`;
    items.push({
      id: newId('obs'),
      day,
      createdAt: t,
      kind: 'coach',
      message,
      status: 'pending',
      suggestion: { ruleId: 'OBS', message, changes: [], patch: { move_habit: title, start } },
    });
  }
  items.push({
    id: newId('info'),
    day,
    createdAt: t,
    kind: 'info',
    status: 'pending',
    message: '이틀 관찰이 끝났어요. 이제 매일 밤 내일 일정과 알람을 자동으로 짜요.',
  });
  return { ...s, observation: s.observation ? { ...s.observation, phase: 'done' } : null, inbox: [...s.inbox, ...items] };
}

/** 한 번만 보여 주는 안내를 봤다고 기록한다. */
export function markAsked(patch: AppState['asked']): void {
  set((s) => ({ ...s, asked: { ...s.asked, ...patch } }));
}

// ---------------------------------------------------------------------------
// 친구와 겨루기
// ---------------------------------------------------------------------------

export function setProfileName(name: string): void {
  set((s) => ({ ...s, profile: { ...s.profile, name: name.trim().slice(0, 12) } }));
}

/** 친구 코드로 받은 기록을 넣는다. 같은 친구면 새 기록으로 바꾼다. 내 코드는 넣지 않는다. */
export function addFriend(f: Friend): 'added' | 'updated' | 'self' {
  if (f.id === state.profile.id) return 'self';
  const exists = state.friends.some((x) => x.id === f.id);
  set((s) => ({ ...s, friends: exists ? s.friends.map((x) => (x.id === f.id ? f : x)) : [...s.friends, f] }));
  return exists ? 'updated' : 'added';
}

export function removeFriend(id: string): void {
  set((s) => ({ ...s, friends: s.friends.filter((f) => f.id !== id) }));
}

// ---------------------------------------------------------------------------
// 근처 익명 보드
// ---------------------------------------------------------------------------

export function setNearbyOn(on: boolean, cell?: string): void {
  set((s) => ({ ...s, nearby: { ...s.nearby, on, ...(cell ? { cell, cellAt: now() } : {}), ...(on ? {} : { cell: undefined, cellAt: undefined }) } }));
}

/** 가까운 사람의 익명 코드를 받아 근처 보드에 올린다. */
export function addNearby(f: Friend): 'added' | 'updated' | 'self' {
  if (f.id === state.profile.id) return 'self';
  const exists = state.nearby.people.some((x) => x.id === f.id);
  set((s) => ({
    ...s,
    nearby: { ...s.nearby, people: exists ? s.nearby.people.map((x) => (x.id === f.id ? f : x)) : [...s.nearby.people, f] },
  }));
  return exists ? 'updated' : 'added';
}

export function removeNearby(id: string): void {
  set((s) => ({ ...s, nearby: { ...s.nearby, people: s.nearby.people.filter((p) => p.id !== id) } }));
}
