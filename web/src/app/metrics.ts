// 베타 지표. 서버가 없어서 기기 안에 쌓았다가, 사용자가 동의하면 파일로 내보낸다.
//
// 넣는 것: 익명 번호, 쓴 날 수, 활성화(2일 관찰 완료), 1·7·14일 유지, 주별 셋 데이 수, 기능 사용 횟수, 설문 응답, 불편 신고.
// 넣지 않는 것: 이름, 기록한 시각·내용, 할 일·일정 제목, 위치.
// 이 파일의 출시 판단 기준: 7일 유지 40% · '없어지면 매우 아쉽다' 40% · 주 3일 이상 셋 데이 30%.

import { addDays, dateKey, fromKey, mondayOf } from '../engine/models';
import { periodStats, weekKeys } from './derive';
import { calibrationFor } from './duration';
import type { AppState, MetricsLog } from './state';
import { computeStreak } from './streak';

export const METRICS_SCHEMA = 'dayset-metrics/1';
export const APP_VERSION = '0.9-preview';

function hash(text: string): string {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(36).padStart(7, '0');
}

/** 이름과 연결되지 않는 익명 번호. 같은 기기에서는 늘 같다. */
export const anonId = (s: AppState): string => `b-${hash(`dayset:${s.profile.id}`)}`;

export function addOpen(m: MetricsLog, t: Date): MetricsLog {
  const k = dateKey(t);
  return m.opens.includes(k) ? m : { ...m, opens: [...m.opens, k].slice(-400) };
}

export function addEvent(m: MetricsLog, t: Date, k: string, v?: string): MetricsLog {
  return { ...m, events: [...m.events, { at: t, k, ...(v ? { v } : {}) }].slice(-1000) };
}

/** 그 기기를 쓴 날(연 날 + 기록이 있는 날). */
export function activeDays(s: AppState): string[] {
  const days = new Set(s.metrics.opens);
  for (const l of s.logs) if (l.source !== 'estimate' && l.source !== 'evening') days.add(dateKey(l.start));
  return [...days].sort();
}

const dayIndex = (start: string, k: string) => Math.round((fromKey(k).getTime() - fromKey(start).getTime()) / 86400000);

export interface MetricsReport {
  schema: string;
  appVersion: string;
  anonId: string;
  generatedAt: string;
  installDate: string;
  daysSinceInstall: number;
  consent: { health: boolean; metrics: boolean } | null;
  goal: { focus: string[] } | null;
  activation: { observationStarted: boolean; reviewed: boolean; activated: boolean; activatedDay: number | null };
  retention: { activeDays: number; d1: boolean; d7: boolean; d14: boolean };
  habit: { weeks: { week: string; setDays: number }[]; weeksWith3SetDays: number; currentStreak: number; bestStreak: number };
  usage: Record<string, number>;
  calibration: { samples: number; ratios: Record<string, number> };
  notify: { enabled: boolean; sticky: boolean; remind: boolean; token: boolean };
  surveys: { key: string; answer: string; best?: string; worst?: string; day: number }[];
  feedback: { kind: string; text: string; page: string; day: number }[];
}

export function computeMetrics(s: AppState, now: Date): MetricsReport {
  const install = dateKey(s.metrics.installAt);
  const days = activeDays(s);
  const idx = days.map((k) => dayIndex(install, k));
  const ev = (k: string) => s.metrics.events.filter((e) => e.k === k).length;

  const obsDay = s.observation?.day2 ?? null;
  const reviewed = !!s.observation && s.observation.phase !== 'recording';
  const activated = reviewed || (!s.observation && Object.keys(s.plans).length > 0);
  const firstPlanDay = Object.keys(s.plans).sort()[0] ?? null;
  const activatedKey = obsDay ?? firstPlanDay;

  // 설치한 주부터 이번 주까지 주별 셋 데이
  const weeks: { week: string; setDays: number }[] = [];
  for (let m = mondayOf(s.metrics.installAt); m <= now; m = addDays(m, 7)) {
    const keys = weekKeys(m).filter((k) => k >= install && k <= dateKey(now));
    if (!keys.length) continue;
    weeks.push({ week: dateKey(m), setDays: periodStats(s, keys, now).setDays });
  }
  const streak = computeStreak(s, now);
  const ratios: Record<string, number> = {};
  for (const type of ['work', 'assignment', 'homework', 'personal'] as const) {
    const c = calibrationFor(s.durations, { type, title: '' });
    if (c) ratios[type] = c.ratio;
  }

  return {
    schema: METRICS_SCHEMA,
    appVersion: APP_VERSION,
    anonId: anonId(s),
    generatedAt: now.toISOString(),
    installDate: install,
    daysSinceInstall: dayIndex(install, dateKey(now)),
    consent: s.consent ? { health: s.consent.health, metrics: s.consent.metrics } : null,
    goal: s.intent ? { focus: s.intent.focus } : null,
    activation: {
      observationStarted: !!s.observation,
      reviewed,
      activated,
      activatedDay: activated && activatedKey ? Math.max(0, dayIndex(install, activatedKey)) : null,
    },
    retention: { activeDays: days.length, d1: idx.some((i) => i >= 1), d7: idx.some((i) => i >= 7), d14: idx.some((i) => i >= 14) },
    habit: { weeks, weeksWith3SetDays: weeks.filter((w) => w.setDays >= 3).length, currentStreak: streak.current, bestStreak: streak.best },
    usage: {
      nowButtonTaps: s.logs.filter((l) => l.source === 'button').length,
      checkPopupRecords: ev('check_record'),
      notificationRecords: ev('notify_record'),
      tasksAdded: ev('task_add'),
      tasksDone: s.tasks.filter((t) => t.done).length,
      reorders: s.learning.reorders.length,
      calendarsConnected: s.calendars.length,
      shares: ev('share'),
      friends: s.friends.length,
      nearbyPeople: s.nearby.people.filter((p) => !p.demo).length,
      eveningChecks: s.eveningDone.length,
    },
    calibration: { samples: s.durations.samples.filter((x) => !x.outlier).length, ratios },
    notify: { enabled: s.notify.enabled, sticky: s.notify.sticky, remind: s.notify.remind, token: !!s.notify.token },
    surveys: s.feedback.surveys.map((x) => ({ key: x.key, answer: x.answer, best: x.best, worst: x.worst, day: dayIndex(install, dateKey(x.at)) })),
    feedback: s.feedback.reports.map((r) => ({ kind: r.kind, text: r.text, page: r.page, day: dayIndex(install, dateKey(r.at)) })),
  };
}

/** 설문을 보여 줄 때(7일째, 28일째). 이미 답했거나 오늘 '나중에'를 눌렀으면 null. */
export function surveyDue(s: AppState, now: Date): 'd7' | 'd28' | null {
  if (!s.consent) return null;
  const since = dayIndex(dateKey(s.metrics.installAt), dateKey(now));
  if (s.feedback.surveyLater === dateKey(now)) return null;
  const done = new Set(s.feedback.surveys.map((x) => x.key));
  if (since >= 28 && !done.has('d28')) return 'd28';
  if (since >= 7 && !done.has('d7')) return 'd7';
  return null;
}
