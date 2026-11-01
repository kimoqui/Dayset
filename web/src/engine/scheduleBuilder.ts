import {
  type ActivityLog,
  addMin,
  clockOn,
  dayStart,
  addDays,
  diffMin,
  type FixedEvent,
  formatClock,
  formatDuration,
  formatHm,
  type HabitGoals,
  isAfter,
  isBefore,
  overlaps,
  type PersonalSettings,
  type PlannedAlarm,
  PRIORITY_ORDER,
  remainingMinutes,
  sameDay,
  type ScheduleBlock,
  type TaskItem,
} from './models';

/** 다음 날 일정 생성 입력. 엔진·규칙 명세 1번. */
export interface DayPlanInput {
  /** 일정을 만들 날짜(시각은 무시한다). */
  date: Date;
  goals: HabitGoals;
  settings: PersonalSettings;
  fixedEvents?: FixedEvent[];
  lockedBlocks?: ScheduleBlock[];
  tasks?: TaskItem[];
  /** 하루 중간에 다시 짤 때: 할 일은 이 시각 이후에만 넣는다. */
  notBefore?: Date;
}

export type DeferReason = 'budget' | 'noSlot';

/** 오늘 넣지 못하고 다음 날로 넘긴 할 일. */
export interface DeferredTask {
  taskId: string;
  minutes: number;
  reason: DeferReason;
}

export interface DayPlan {
  date: Date;
  /** 그 날 기상 알람 시각. */
  wake: Date;
  /** 전날 밤 취침 알람 시각. */
  bedTonight: Date;
  /** 그 날 밤 취침 예정(하루 일정의 끝). */
  dayEnd: Date;
  /** 시작 시각 순으로 정렬된 블록. 첫 블록은 전날 밤 수면이다. */
  blocks: ScheduleBlock[];
  alarms: PlannedAlarm[];
  deferred: DeferredTask[];
  /** 사용자에게 보여줄 안내(예: 겹쳐서 뺀 습관). */
  notes: string[];
  /** 할 일을 넣기 전 빈 시간 합계(분). */
  freeMinutes: number;
  /** 실제로 배치한 할 일 시간(분). */
  taskMinutes: number;
}

interface Gap {
  start: Date;
  end: Date;
}

const gapMinutes = (g: Gap): number => diffMin(g.end, g.start);

/**
 * 하루 일정 엔진. 엔진·규칙 명세 2번과 3번을 구현한다.
 *
 * - 기상 = min(목표 기상, 첫 고정 일정 − 준비 − 이동)
 * - 전날 취침 = 기상 − 목표 수면 − 잠들기까지 걸리는 시간
 * - 할 일은 빈 시간의 75%까지만, 최대 50분 조각 + 10분 휴식으로 넣는다.
 */
export function buildDay(input: DayPlanInput): DayPlan {
  const day = dayStart(input.date);
  const nextDay = addDays(day, 1);
  const s = input.settings;
  const g = input.goals;
  let seq = 0;
  const nid = (prefix: string): string => `${prefix}-${++seq}`;

  const fixed = (input.fixedEvents ?? [])
    .filter((e) => sameDay(e.start, day))
    .sort((a, b) => a.start.getTime() - b.start.getTime());

  // 1) 기상과 취침
  let wake = clockOn(g.wake, day);
  let wakeReason = `목표 기상 ${formatClock(g.wake)}`;
  if (fixed.length > 0) {
    const latest = addMin(fixed[0].start, -(s.prepMinutes + s.travelMinutes));
    if (isBefore(latest, wake)) {
      wake = latest;
      wakeReason = `첫 일정 ${formatHm(fixed[0].start)} − 준비 ${s.prepMinutes}분 − 이동 ${s.travelMinutes}분`;
    }
  }
  const sleepTotal = g.sleepMinutes + s.sleepLatencyMinutes + (s.bedEarlierMinutes ?? 0);
  const bedTonight = addMin(wake, -sleepTotal);
  const dayEnd = addMin(clockOn(g.wake, nextDay), -sleepTotal);

  // 2) 움직일 수 없는 블록
  const blocks: ScheduleBlock[] = [
    { id: nid('sleep'), kind: 'habit', activity: 'sleep', title: '수면', start: bedTonight, end: wake },
  ];
  if (fixed.length > 0 && s.travelMinutes > 0) {
    const first = fixed[0].start;
    blocks.push({ id: nid('travel'), kind: 'fixed', title: '이동', start: addMin(first, -s.travelMinutes), end: first });
  }
  for (const e of fixed) {
    blocks.push({ id: nid('event'), kind: 'fixed', title: e.title, start: e.start, end: e.end, locked: true });
  }
  blocks.push(...(input.lockedBlocks ?? []).filter((b) => sameDay(b.start, day)));

  // 3) 습관 뼈대(식사·운동). 겹치면 2시간 안에서 뒤로 민다.
  const notes: string[] = [];
  const habits = [...g.meals, ...(g.exercise ? [g.exercise] : [])];
  for (const h of habits) {
    const placed = placeHabit(clockOn(h.start, day), h.minutes, blocks, dayEnd);
    if (placed == null) {
      notes.push(`${h.title}: 겹치는 일정이 있어 넣지 못했어요`);
      continue;
    }
    blocks.push({
      id: nid('habit'),
      kind: 'habit',
      activity: h.activity,
      title: h.title,
      start: placed,
      end: addMin(placed, h.minutes),
    });
  }

  // 4) 빈 시간 계산. 할 일은 기상 후 준비 시간이 지난 뒤부터, 취침 준비 전까지.
  let windowStart = addMin(wake, s.prepMinutes);
  if (input.notBefore && isAfter(input.notBefore, windowStart)) windowStart = input.notBefore;
  const windowEnd = addMin(dayEnd, -s.windDownMinutes);
  const gaps = findGaps(blocks, windowStart, windowEnd);
  const freeMinutes = gaps.reduce((sum, x) => sum + gapMinutes(x), 0);
  const budget = Math.floor(freeMinutes * s.fillRatio);

  // 5) 할 일 배치: 사용자가 정한 순서(rank) → 마감 → 우선순위 순.
  const tasks = [...(input.tasks ?? [])].sort((a, b) => {
    if (a.rank != null && b.rank != null && a.rank !== b.rank) return a.rank - b.rank;
    const d = a.dueAt.getTime() - b.dueAt.getTime();
    return d !== 0 ? d : PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority];
  });
  const deferred: DeferredTask[] = [];
  let used = 0;
  for (const t of tasks) {
    let remaining = remainingMinutes(t);
    while (remaining > 0) {
      const chunk = remaining < s.chunkMinutes ? remaining : s.chunkMinutes;
      if (used + chunk > budget) {
        deferred.push({ taskId: t.id, minutes: remaining, reason: 'budget' });
        break;
      }
      const start = bestSlot(gaps, chunk, t.dueAt, t.focus ? s : null, day);
      if (start == null) {
        deferred.push({ taskId: t.id, minutes: remaining, reason: 'noSlot' });
        break;
      }
      const end = addMin(start, chunk);
      blocks.push({
        id: nid('task'),
        kind: 'task',
        activity: 'work',
        title: t.title,
        start,
        end,
        focus: t.focus,
        taskId: t.id,
      });
      consume(gaps, start, addMin(end, s.restMinutes));
      used += chunk;
      remaining -= chunk;
    }
  }

  blocks.sort((a, b) => a.start.getTime() - b.start.getTime());

  const earlier = s.bedEarlierMinutes ? ` − 일찍 자기 ${s.bedEarlierMinutes}분` : '';
  const alarms: PlannedAlarm[] = [
    { kind: 'wake', at: wake, reason: wakeReason },
    {
      kind: 'bed',
      at: bedTonight,
      reason: `기상 ${formatHm(wake)} − 수면 ${formatDuration(g.sleepMinutes)} − 잠들기까지 ${s.sleepLatencyMinutes}분${earlier}`,
    },
    {
      kind: 'windDown',
      at: addMin(bedTonight, -s.windDownMinutes),
      reason: `취침 ${s.windDownMinutes}분 전 마무리`,
    },
  ];

  return { date: day, wake, bedTonight, dayEnd, blocks, alarms, deferred, notes, freeMinutes, taskMinutes: used };
}

/** 습관을 원래 시각에 두고, 겹치면 겹친 블록 끝으로 옮긴다(최대 120분 뒤까지). */
function placeHabit(start: Date, minutes: number, blocks: ScheduleBlock[], dayEnd: Date): Date | null {
  const limit = addMin(start, 120);
  let candidate = start;
  for (let i = 0; i < blocks.length + 1; i++) {
    const end = addMin(candidate, minutes);
    if (isAfter(end, dayEnd) || isAfter(candidate, limit)) return null;
    const clash = blocks.filter((b) => overlaps(b, candidate, end));
    if (clash.length === 0) return candidate;
    candidate = clash.map((b) => b.end).reduce((a, b) => (isAfter(a, b) ? a : b));
  }
  return null;
}

function findGaps(blocks: ScheduleBlock[], from: Date, to: Date): Gap[] {
  const busy = blocks
    .filter((b) => isAfter(b.end, from) && isBefore(b.start, to))
    .sort((a, b) => a.start.getTime() - b.start.getTime());
  const gaps: Gap[] = [];
  let cursor = from;
  for (const b of busy) {
    if (isAfter(b.start, cursor)) gaps.push({ start: cursor, end: b.start });
    if (isAfter(b.end, cursor)) cursor = b.end;
  }
  if (isAfter(to, cursor)) gaps.push({ start: cursor, end: to });
  return gaps.filter((x) => gapMinutes(x) > 0);
}

/** 조각이 들어갈 시작 시각. 집중 작업이면 집중 시간대를 먼저 찾는다. */
function bestSlot(gaps: Gap[], minutes: number, due: Date, focus: PersonalSettings | null, day: Date): Date | null {
  const fits = (s: Date, g: Gap): boolean => {
    const e = addMin(s, minutes);
    return !isBefore(s, g.start) && !isAfter(e, g.end) && !isAfter(e, due);
  };
  if (focus) {
    const fs = clockOn(focus.focusStart, day);
    const fe = clockOn(focus.focusEnd, day);
    for (const g of gaps) {
      const s = isAfter(g.start, fs) ? g.start : fs;
      if (isBefore(s, fe) && fits(s, g)) return s;
    }
  }
  for (const g of gaps) {
    if (fits(g.start, g)) return g.start;
  }
  return null;
}

function consume(gaps: Gap[], start: Date, end: Date): void {
  for (let i = 0; i < gaps.length; i++) {
    const g = gaps[i];
    if (!isBefore(g.start, end) || !isBefore(start, g.end)) continue;
    const pieces: Gap[] = [];
    if (isAfter(start, g.start)) pieces.push({ start: g.start, end: start });
    if (isBefore(end, g.end)) pieces.push({ start: end, end: g.end });
    gaps.splice(i, 1, ...pieces);
    return;
  }
}

export type AlarmDecision = 'apply' | 'needsConfirmation';

/** 알람 변경 제한(엔진 명세 3번): 취침 기록 뒤에는 기상 알람을 앞당기기만 한다. */
export function decideWakeChange(p: { current: Date; proposed: Date; sleepLogged: boolean }): AlarmDecision {
  if (!isAfter(p.proposed, p.current)) return 'apply';
  return p.sleepLogged ? 'needsConfirmation' : 'apply';
}

/** 블록 시작 후 10분 동안 기록이 없으면 예정 시각으로 추정 기록을 만든다(명세 4번). */
export function estimateMissing(p: {
  blocks: ScheduleBlock[];
  logs: ActivityLog[];
  now: Date;
  graceMinutes?: number;
}): ActivityLog[] {
  const grace = p.graceMinutes ?? 10;
  const out: ActivityLog[] = [];
  for (const b of p.blocks) {
    const a = b.activity;
    if (!a || b.kind === 'fixed') continue;
    if (diffMin(p.now, b.start) < grace) continue;
    const hasLog = p.logs.some((l) => l.activity === a && Math.abs(diffMin(l.start, b.start)) <= 30);
    if (hasLog) continue;
    out.push({
      id: `est-${b.id}`,
      activity: a,
      start: b.start,
      end: isBefore(b.end, p.now) ? b.end : null,
      source: 'estimate',
      confirmed: false,
      snoozeCount: 0,
    });
  }
  return out;
}
