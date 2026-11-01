// 일정 바꾸기: 일정 탭에서 직접 고치거나, 채팅으로 말한 것을 같은 '바꾸기' 목록으로 만들어 적용한다.
// 모두 순수 함수다(상태를 받아 새 상태를 돌려준다). 저장소(store.ts)는 이걸 적용하고 남은 일정을 다시 짠다.
//
// 바꿀 수 있는 것
//  - 습관(식사·운동): 그날만(시작·길이·빼기) 또는 매일(목표 자체)
//  - 기상 시각: 그날만 또는 매일
//  - 캘린더 일정: 넣기·옮기기·지우기
//  - 할 일: 넣기
//  - 그날 바꾼 것 되돌리기
// 잠금·캘린더에서 가져온 일정·수면 블록은 직접 움직이지 않는다(기상·습관 목표를 바꾸면 엔진이 다시 짠다).

import {
  addDays,
  dateKey,
  type FixedEvent,
  focusByType,
  formatClock,
  formatDuration,
  formatHm,
  fromKey,
  type HabitSlot,
  koreanDate,
  type TaskItem,
  type TaskType,
} from '../engine/models';
import { type DayPlan } from '../engine/scheduleBuilder';
import { effectiveGoals, planFor, regeneratePlan } from './derive';
import type { AppState, HabitEdit } from './state';

export type EditScope = 'day' | 'every';

export type ScheduleEdit =
  | { kind: 'habit'; day: string; title: string; patch: HabitEdit; scope: EditScope }
  | { kind: 'wake'; day: string; minutes: number; scope: EditScope }
  | { kind: 'event-add'; title: string; start: Date; end: Date }
  | { kind: 'event-move'; id: string; start: Date; end: Date }
  | { kind: 'event-delete'; id: string }
  | { kind: 'task-add'; title: string; minutes: number; type: TaskType; dueAt?: Date }
  | { kind: 'reset'; day: string };

let seq = 0;
const id = (p: string) => `${p}-${Date.now().toString(36)}-${(seq++).toString(36)}`;

/** 오늘·내일·모레·M월 D일 요일 */
export function dayLabel(day: string, now: Date): string {
  const t = dateKey(now);
  if (day === t) return '오늘';
  if (day === dateKey(addDays(now, 1))) return '내일';
  if (day === dateKey(addDays(now, 2))) return '모레';
  return koreanDate(fromKey(day));
}

/** 이 날 이 습관의 지금 값(바꾼 값 반영). 없으면 null. */
export function habitOn(s: AppState, day: string, title: string): HabitSlot | null {
  const g = effectiveGoals(s, day);
  return [...g.meals, ...(g.exercise ? [g.exercise] : [])].find((h) => h.title === title) ?? null;
}

/** 목표에 있는 습관 이름(식사·운동). */
export function habitTitles(s: AppState): string[] {
  return [...s.goals.meals.map((m) => m.title), ...(s.goals.exercise ? [s.goals.exercise.title] : [])];
}

/** 사람이 읽는 설명. */
export function describeEdit(s: AppState, e: ScheduleEdit, now: Date): string {
  switch (e.kind) {
    case 'habit': {
      const when = e.scope === 'every' ? '매일' : dayLabel(e.day, now);
      if (e.patch.skip) return e.scope === 'every' ? `${e.title}: 앞으로 일정에서 빼기` : `${when} ${e.title}: 이날은 빼기`;
      const parts = [e.patch.start != null ? `${formatClock(e.patch.start)} 시작` : '', e.patch.minutes != null ? formatDuration(e.patch.minutes) : ''].filter(Boolean);
      return `${when} ${e.title}: ${parts.join(' · ')}`;
    }
    case 'wake':
      return `${e.scope === 'every' ? '매일' : dayLabel(e.day, now)} 기상 알람: ${formatClock(e.minutes)}`;
    case 'event-add':
      return `캘린더에 넣기: ${dayLabel(dateKey(e.start), now)} ${formatHm(e.start)}–${formatHm(e.end)} ${e.title}`;
    case 'event-move': {
      const ev = s.events.find((x) => x.id === e.id);
      return `${ev?.title ?? '일정'} 옮기기: ${dayLabel(dateKey(e.start), now)} ${formatHm(e.start)}–${formatHm(e.end)}`;
    }
    case 'event-delete':
      return `${s.events.find((x) => x.id === e.id)?.title ?? '일정'} 지우기`;
    case 'task-add':
      return `할 일 넣기: ${e.title} · ${formatDuration(e.minutes)}${e.dueAt ? ` · ${dayLabel(dateKey(e.dueAt), now)}까지` : ''}`;
    case 'reset':
      return `${dayLabel(e.day, now)} 바꾼 것 되돌리기`;
  }
}

/** 하나 적용(순수). */
export function applyEdit(s: AppState, e: ScheduleEdit, now: Date): AppState {
  const bump = (x: AppState): AppState => ({ ...x, inputsVersion: x.inputsVersion + 1 });
  switch (e.kind) {
    case 'habit': {
      if (e.scope === 'every') {
        const g = s.goals;
        const fix = (h: HabitSlot): HabitSlot => ({ ...h, start: e.patch.start ?? h.start, minutes: e.patch.minutes ?? h.minutes });
        const isEx = g.exercise?.title === e.title;
        const goals = isEx
          ? { ...g, exercise: e.patch.skip ? null : fix(g.exercise!) }
          : { ...g, meals: e.patch.skip ? g.meals.filter((m) => m.title !== e.title) : g.meals.map((m) => (m.title === e.title ? fix(m) : m)) };
        // 매일로 바꾸면 그날만 바꾼 값은 지운다(헷갈리지 않게).
        const overrides = Object.fromEntries(
          Object.entries(s.overrides).map(([k, o]) => {
            if (!o.habits?.[e.title]) return [k, o];
            const { [e.title]: _drop, ...rest } = o.habits;
            return [k, { ...o, habits: rest }];
          }),
        );
        return bump({ ...s, goals, overrides });
      }
      const o = s.overrides[e.day] ?? {};
      const prev = o.habits?.[e.title] ?? {};
      const next: HabitEdit = e.patch.skip ? { skip: true } : { ...prev, ...e.patch, skip: undefined };
      return bump({ ...s, overrides: { ...s.overrides, [e.day]: { ...o, habits: { ...(o.habits ?? {}), [e.title]: next } } } });
    }
    case 'wake': {
      if (e.scope === 'every') return bump({ ...s, goals: { ...s.goals, wake: e.minutes }, correction: null });
      const o = s.overrides[e.day] ?? {};
      return bump({ ...s, overrides: { ...s.overrides, [e.day]: { ...o, wake: e.minutes } } });
    }
    case 'event-add': {
      const ev: FixedEvent = { id: id('ev'), title: e.title, start: e.start, end: e.end };
      return bump({ ...s, events: [...s.events, ev] });
    }
    case 'event-move':
      return bump({ ...s, events: s.events.map((x) => (x.id === e.id ? { ...x, start: e.start, end: e.end } : x)) });
    case 'event-delete':
      return bump({ ...s, events: s.events.filter((x) => x.id !== e.id) });
    case 'task-add': {
      const t: TaskItem = {
        id: id('task'),
        title: e.title,
        estMinutes: e.minutes,
        dueAt: e.dueAt ?? addDays(new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 0), 7),
        type: e.type,
        priority: 'normal',
        focus: focusByType(e.type),
        doneMinutes: 0,
        createdAt: now,
      };
      return bump({ ...s, tasks: [...s.tasks, t] });
    }
    case 'reset': {
      const o = s.overrides[e.day];
      if (!o) return s;
      const { wake: _w, habits: _h, ...rest } = o;
      return bump({ ...s, overrides: { ...s.overrides, [e.day]: rest } });
    }
  }
}

/** 바꾸기 목록이 닿는 날(일정을 다시 짤 날·미리 볼 날). */
export function editDays(s: AppState, edits: ScheduleEdit[], now: Date): string[] {
  const today = dateKey(now);
  const tomorrow = dateKey(addDays(now, 1));
  const days = new Set<string>();
  for (const e of edits) {
    if (e.kind === 'habit' || e.kind === 'wake') {
      if (e.scope === 'every') {
        days.add(today);
        days.add(tomorrow);
      } else days.add(e.day);
    } else if (e.kind === 'reset') days.add(e.day);
    else if (e.kind === 'event-add') days.add(dateKey(e.start));
    else if (e.kind === 'event-move') {
      days.add(dateKey(e.start));
      const old = s.events.find((x) => x.id === e.id);
      if (old) days.add(dateKey(old.start));
    } else if (e.kind === 'event-delete') {
      const old = s.events.find((x) => x.id === e.id);
      days.add(old ? dateKey(old.start) : today);
    } else {
      days.add(today);
      days.add(tomorrow);
    }
  }
  return [...days].filter((d) => d >= today).sort();
}

/** 저장해 둔 그날 일정을 다시 짠다(지난 조각은 그대로). 저장하지 않은 날은 볼 때 새로 짜인다. */
export function replanDays(s: AppState, days: string[], now: Date): AppState {
  let next = s;
  for (const k of days) if (next.plans[k]) next = { ...next, plans: { ...next.plans, [k]: regeneratePlan(next, k, now) } };
  return next;
}

/** 두 일정의 차이(바꾸기 미리보기용 문장). */
export function diffPlans(before: DayPlan, after: DayPlan): string[] {
  const out: string[] = [];
  if (before.wake.getTime() !== after.wake.getTime()) out.push(`기상 알람 ${formatHm(before.wake)} → ${formatHm(after.wake)}`);
  const habits = (p: DayPlan) => p.blocks.filter((b) => b.kind === 'habit' && b.activity !== 'sleep');
  for (const b of habits(before)) {
    const a = habits(after).find((x) => x.title === b.title);
    if (!a) out.push(`${b.title} 빠짐`);
    else if (a.start.getTime() !== b.start.getTime() || a.end.getTime() !== b.end.getTime())
      out.push(`${b.title} ${formatHm(b.start)}–${formatHm(b.end)} → ${formatHm(a.start)}–${formatHm(a.end)}`);
  }
  for (const a of habits(after)) if (!habits(before).some((b) => b.title === a.title)) out.push(`${a.title} ${formatHm(a.start)} 추가`);
  const fixed = (p: DayPlan) => p.blocks.filter((b) => b.kind === 'fixed' && !b.locked);
  for (const a of fixed(after)) {
    const b = fixed(before).find((x) => x.title === a.title);
    if (!b) out.push(`${a.title} ${formatHm(a.start)}–${formatHm(a.end)} 들어감`);
    else if (b.start.getTime() !== a.start.getTime()) out.push(`${a.title} ${formatHm(b.start)} → ${formatHm(a.start)}`);
  }
  for (const b of fixed(before)) if (!fixed(after).some((x) => x.title === b.title)) out.push(`${b.title} 빠짐`);
  if (before.taskMinutes !== after.taskMinutes) out.push(`할 일 ${formatDuration(before.taskMinutes)} → ${formatDuration(after.taskMinutes)}`);
  return out;
}

/** 적용하면 그날 일정이 어떻게 바뀌는지(미리보기). */
export function previewEdits(s: AppState, edits: ScheduleEdit[], now: Date): { day: string; label: string; diffs: string[] }[] {
  let after = s;
  for (const e of edits) after = applyEdit(after, e, now);
  const days = editDays(s, edits, now);
  after = replanDays(after, days, now);
  return days.map((day) => ({ day, label: dayLabel(day, now), diffs: diffPlans(planFor(s, day, now), planFor(after, day, now)) }));
}
