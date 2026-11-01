// 예시 데이터: 직장인 한 명의 지난 3주. 통계·셋 데이 캘린더·코칭을 바로 볼 수 있다.

import { CoachingEngine } from '../engine/coaching';
import {
  type ActivityLog,
  addDays,
  addMin,
  dateKey,
  dayStart,
  isAfter,
  isBefore,
  MISS_REASONS,
  mondayOf,
  type MissReason,
  type TaskItem,
} from '../engine/models';
import { buildPlan, storedFrom } from './derive';
import type { Friend } from './social';
import { type AppState, DEFAULT_GOALS, initialState } from './state';

function rng(seed: number): () => number {
  let x = seed;
  return () => {
    x = (x * 1664525 + 1013904223) % 4294967296;
    return x / 4294967296;
  };
}

export function demoState(now: Date): AppState {
  const rand = rng(20261019);
  const jitter = (min: number, max: number): number => Math.round(min + rand() * (max - min));
  const today = dayStart(now);
  let n = 0;
  const id = (p: string): string => `${p}-demo-${n++}`;

  const d = (plus: number, h: number, m = 0): Date => new Date(today.getFullYear(), today.getMonth(), today.getDate() + plus, h, m);
  const tasks: TaskItem[] = [
    { id: 'task-report', title: '분기 보고서 작성', estMinutes: 180, dueAt: new Date(addDays(today, 3).setHours(18)), type: 'work', priority: 'high', focus: true, doneMinutes: 0, createdAt: d(-2, 10) },
    { id: 'task-english', title: '영어 숙제', estMinutes: 60, dueAt: new Date(addDays(today, 2).setHours(23)), type: 'homework', priority: 'normal', focus: false, doneMinutes: 0, createdAt: d(-1, 20) },
    { id: 'task-dentist', title: '치과 예약 전화', estMinutes: 10, dueAt: new Date(addDays(today, 0).setHours(18)), type: 'personal', priority: 'normal', focus: false, doneMinutes: 0, createdAt: d(-3, 9) },
  ];
  const events = [
    { id: 'ev-1', title: '고객 미팅', start: d(0, 16), end: d(0, 17) },
    { id: 'ev-2', title: '팀 회의', start: d(1, 9), end: d(1, 10) },
  ];

  let s: AppState = {
    ...initialState(),
    onboarded: true,
    demo: true,
    goals: structuredClone(DEFAULT_GOALS),
    events,
    tasks: [],
  };

  const logs: ActivityLog[] = [];
  const restDays: string[] = [];
  const DAYS = 20;

  // 지난 날: 일정 저장 + 기록 생성
  for (let i = DAYS; i >= 1; i--) {
    const day = addDays(today, -i);
    const key = dateKey(day);
    const plan = buildPlan(s, key);
    s.plans[key] = storedFrom(plan, s);
    const weekend = day.getDay() === 0 || day.getDay() === 6;
    if (weekend && rand() < 0.35) restDays.push(key);
    const good = rand() < 0.6; // 잘 지낸 날

    // 수면: 전날 밤 취침 ~ 기상
    const sleepBlock = plan.blocks[0];
    const bed = addMin(sleepBlock.start, good ? jitter(-10, 20) : jitter(10, 70));
    const wakeAt = addMin(plan.wake, good ? jitter(-5, 12) : jitter(15, 55));
    logs.push({ id: id('log'), activity: 'sleep', start: bed, end: wakeAt, source: 'alarm', confirmed: true, snoozeCount: 0 });
    s.wakes.push({ day: key, at: wakeAt, snoozes: good ? jitter(0, 1) : jitter(1, 4), source: 'alarm' });

    for (const b of plan.blocks.slice(1)) {
      if (b.kind !== 'habit' || !b.activity) continue;
      const p = b.activity === 'exercise' ? (good ? 0.75 : 0.25) : good ? 0.93 : 0.5;
      if (rand() < p) {
        const start = addMin(b.start, jitter(-8, 18));
        logs.push({ id: id('log'), activity: b.activity, start, end: addMin(start, Math.max(10, Math.round((b.end.getTime() - b.start.getTime()) / 60000) + jitter(-10, 10))), source: 'button', confirmed: true, snoozeCount: 0 });
      } else if (rand() < 0.85) {
        const reason: MissReason = b.activity === 'exercise' ? (['tired', 'unwilling', 'conflict'] as const)[jitter(0, 2)] : MISS_REASONS[jitter(0, 3)];
        s.misses.push({ day: key, blockId: b.id, activity: b.activity, reason, at: b.end });
      }
    }
    // 업무 기록(그래프용)
    if (!weekend) {
      const ws = d(-i, 9, jitter(0, 20));
      logs.push({ id: id('log'), activity: 'work', start: ws, end: d(-i, 11, 50), source: 'widget', confirmed: true, snoozeCount: 0 });
      logs.push({ id: id('log'), activity: 'work', start: d(-i, 13, jitter(0, 15)), end: d(-i, 18, jitter(0, 40)), source: 'widget', confirmed: true, snoozeCount: 0 });
    }
    s.eveningDone.push(key);
  }

  // 오늘: 어젯밤 짧게 잔 날(코칭 R1 예시). 지금 시각까지 일정대로 기록한다.
  s.tasks = tasks;
  const todayKey = dateKey(today);
  const todayPlan = buildPlan(s, todayKey, { reservedBlocks: [] });
  s.plans[todayKey] = storedFrom(todayPlan, s);
  const lastBed = d(0, 1, 20);
  const wakeAt = addMin(todayPlan.wake, 4);
  const sleepEnd = isAfter(now, wakeAt) ? wakeAt : null;
  logs.push({ id: id('log'), activity: 'sleep', start: lastBed, end: sleepEnd, source: 'button', confirmed: true, snoozeCount: 0 });
  if (sleepEnd) {
    s.wakes.push({ day: todayKey, at: wakeAt, snoozes: 1, source: 'alarm' });
    s.alarms[`${todayKey}|wake`] = { snoozes: 1, done: true };
    let last: ActivityLog | null = null;
    for (const b of todayPlan.blocks.slice(1)) {
      if (!b.activity || b.kind === 'fixed' || b.activity === 'exercise') continue;
      const start = addMin(b.start, jitter(0, 4));
      if (!isBefore(start, now)) break;
      if (last && last.activity === b.activity) {
        // 같은 활동이 이어지면 한 기록으로 둔다('지금' 버튼은 같은 상태를 다시 눌러도 바뀌지 않는다).
        last.end = isBefore(b.end, now) ? b.end : null;
        continue;
      }
      if (last && last.end == null) last.end = start;
      last = { id: id('log'), activity: b.activity, start, end: isBefore(b.end, now) ? b.end : null, source: 'button', confirmed: true, snoozeCount: 0 };
      logs.push(last);
    }
    // 마지막 기록은 지금도 이어지는 중으로 둔다.
    if (last && last.end && now.getTime() - last.end.getTime() < 90 * 60000) last.end = null;
    const engine = new CoachingEngine();
    const sg = engine.evaluate({ type: 'wakeLogged', sleepMinutes: Math.round((wakeAt.getTime() - lastBed.getTime()) / 60000) }, { today: todayPlan.blocks, now });
    s.inbox = sg.map((x) => ({ id: id('coach'), day: todayKey, createdAt: wakeAt, kind: 'coach', suggestion: x, message: x.message, status: 'pending' }));
  }

  logs.sort((a, b) => a.start.getTime() - b.start.getTime());
  const week = dateKey(mondayOf(now));
  const friends: Friend[] = [
    { id: 'demo-f1', name: '지민', streak: 12, best: 21, week, weekSetDays: 1, monthSetDays: 13, updatedAt: addMin(now, -95) },
    { id: 'demo-f2', name: '현우', streak: 4, best: 9, week, weekSetDays: 1, monthSetDays: 8, updatedAt: addMin(now, -300) },
    { id: 'demo-f3', name: '서연', streak: 0, best: 15, week: dateKey(addDays(mondayOf(now), -7)), weekSetDays: 5, monthSetDays: 6, updatedAt: addDays(now, -3) },
  ];
  // 우선순위 학습 예시: 4일 동안 '짧은 일·개인 일 먼저'로 순서를 바꿈 → AI 추천이 보인다.
  const L = (t: 'work' | 'assignment' | 'homework' | 'personal', est: number, age: number) => ({ type: t, est, age });
  const learning = {
    reorders: [
      { at: d(-4, 21), items: [L('personal', 20, 1), L('homework', 45, 2), L('work', 120, 3), L('assignment', 180, 1)] },
      { at: d(-3, 8), items: [L('personal', 10, 0), L('work', 30, 1), L('homework', 60, 2), L('work', 150, 2)] },
      { at: d(-2, 9), items: [L('work', 20, 0), L('personal', 30, 3), L('homework', 90, 1), L('assignment', 240, 4)] },
      { at: d(-1, 22), items: [L('personal', 15, 1), L('homework', 50, 0), L('work', 180, 2)] },
    ],
    completions: [
      { at: d(-3, 12), type: 'personal' as const, est: 10, age: 0.5, pos: 0 },
      { at: d(-2, 15), type: 'work' as const, est: 20, age: 0.2, pos: 0 },
      { at: d(-1, 11), type: 'personal' as const, est: 15, age: 1, pos: 0 },
    ],
  };
  const cell = '37.38,126.94';
  const near = (i: number, name: string, streak: number, wsd: number, c = cell): Friend => ({
    id: `demo-n${i}`, name, streak, best: streak + 3, week, weekSetDays: wsd, monthSetDays: wsd + 4, updatedAt: addMin(now, -30 * i), anon: true, cell: c, demo: true,
  });
  const nearby = {
    on: true,
    cell,
    cellAt: now,
    people: [
      near(1, '꾸준한 거북이 #071', 18, 1),
      near(2, '새벽 참새 #512', 9, 1),
      near(3, '느긋한 판다 #233', 2, 0, '37.36,126.94'),
      near(4, '반짝이는 여우 #908', 5, 1, '37.40,126.96'),
      near(5, '포근한 고양이 #144', 0, 0),
    ],
  };
  // 걸리는 시간 보정 예시: 숙제는 예상보다 오래, 개인 일은 빨리 끝내는 편.
  const durations = {
    on: true,
    samples: [
      ['영어 숙제', 'homework', 60, 80, -9],
      ['수학 숙제', 'homework', 40, 55, -7],
      ['독후감', 'homework', 45, 60, -5],
      ['택배 반품', 'personal', 20, 10, -8],
      ['은행 업무', 'personal', 30, 20, -6],
      ['병원 예약', 'personal', 15, 10, -4],
      ['주간 보고', 'work', 120, 125, -3],
      ['메일 정리', 'work', 30, 30, -2],
    ].map(([title, type, est, actual, day]) => ({ at: d(day as number, 21), type: type as TaskItem['type'], title: title as string, est: est as number, actual: actual as number })),
  };
  // 가져온 캘린더 예시(.ics 파일): 내일부터의 수업. 오늘 일정은 그대로 둔다.
  const school = [1, 3, 8].map((p) => ({ id: `ics:학교 시간표:class@${p}`, title: '경영학원론', start: d(p, 13), end: d(p, 14, 30), source: 'ics:학교 시간표' }));
  const calendars = [{ id: 'ics:학교 시간표', kind: 'ics' as const, name: '학교 시간표', lastSync: d(-1, 21), count: school.length }];
  // 예시 데이터: 동의·목표·지표가 채워진 상태로 둘러본다.
  const consent = { health: true, metrics: true, at: d(-DAYS, 9), version: 1 };
  const intent = { focus: ['wake', 'breakfast', 'tasks'] as ('wake' | 'breakfast' | 'tasks')[], wake: 7 * 60, sleepMinutes: 420, exerciseMinutes: 30, setAt: d(-DAYS, 9) };
  const metrics = { installAt: d(-DAYS, 9), opens: Array.from({ length: DAYS }, (_, i) => dateKey(addDays(today, i - DAYS))).filter((_, i) => i % 5 !== 3), events: [] };
  s = { ...s, logs, restDays, friends, learning, nearby, durations, calendars, consent, intent, metrics, events: [...s.events, ...school], profile: { ...s.profile, name: '나' } };
  return s;
}
