// 걸리는 시간 자동 보정(기기 안에서 동작).
//
// 할 일을 끝낼 때 '처음 예상한 시간'과 '실제로 쓴 시간'을 남기고,
// 같은 이름의 일(2건 이상) 또는 같은 종류의 일(3건 이상)에서 실제/예상 비율의 중앙값을 구한다.
// 일정에는 예상 × 비율만큼 잡는다. 사용자가 적은 예상 시간은 그대로 두고, 일정에만 반영한다.
//
// 실제로 쓴 시간은 '사실'만 쓴다.
//  - 저녁 확인에서 '했어요'로 반영한 조각(doneMinutes)
//  - 오늘 일정에서 이미 지난(또는 지금 진행 중인) 그 할 일 조각
//  - '30분 더'처럼 사용자가 늘린 시간은 실제로 끝낼 때 쓴 시간에 포함된다
// 실제 시간을 알 수 없으면(일정 밖에서 끝냄) 기록하지 않는다.

import { hasBatchim } from '../engine/coaching';
import type { TaskItem, TaskType } from '../engine/models';

export interface DurationSample {
  at: Date;
  taskId?: string;
  type: TaskType;
  title: string;
  est: number;
  actual: number;
  /** 실제/예상이 1/3배보다 작거나 3배보다 크면 보정에 쓰지 않는다(체크를 잊고 며칠 묵힌 경우 등). */
  outlier?: boolean;
}

export interface DurationLearning {
  /** 걸리는 시간 자동 보정 켜기. */
  on: boolean;
  samples: DurationSample[];
}

export const emptyDurations = (): DurationLearning => ({ on: true, samples: [] });

export const MIN_TITLE_SAMPLES = 2;
export const MIN_TYPE_SAMPLES = 3;
const MAX_SAMPLES = 200;

export interface Calibration {
  ratio: number;
  n: number;
  basis: 'title' | 'type';
}

/** 이름 비교용: 공백·숫자·기호를 빼고 소문자로(예: '영어 숙제 3' = '영어숙제'). */
export function normTitle(title: string): string {
  return title.toLowerCase().replace(/[\s\d.,·_\-()[\]#]+/g, '');
}

function median(xs: number[]): number {
  const a = [...xs].sort((p, q) => p - q);
  const m = a.length >> 1;
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** 이 할 일에 쓸 보정 비율. 자료가 적거나 차이가 10% 안쪽이면 null(보정 안 함). */
export function calibrationFor(d: DurationLearning, task: Pick<TaskItem, 'type' | 'title'>): Calibration | null {
  if (!d.on) return null;
  const recent = d.samples.filter((x) => !x.outlier).slice(-60);
  const name = normTitle(task.title);
  const byTitle = name ? recent.filter((x) => normTitle(x.title) === name) : [];
  const pick = byTitle.length >= MIN_TITLE_SAMPLES ? { xs: byTitle, basis: 'title' as const } : null;
  const byType = recent.filter((x) => x.type === task.type);
  const use = pick ?? (byType.length >= MIN_TYPE_SAMPLES ? { xs: byType, basis: 'type' as const } : null);
  if (!use) return null;
  const ratio = Math.round(clamp(median(use.xs.slice(-10).map((x) => x.actual / x.est)), 0.5, 2) * 10) / 10;
  if (Math.abs(ratio - 1) < 0.1) return null;
  return { ratio, n: use.xs.length, basis: use.basis };
}

const round5 = (m: number) => Math.max(5, Math.round(m / 5) * 5);

/** 일정에 잡을 시간 = 예상 × 보정 비율 + 사용자가 늘린 시간. */
export function plannedMinutes(t: TaskItem, d: DurationLearning): number {
  const c = calibrationFor(d, t);
  return (c ? round5(t.estMinutes * c.ratio) : t.estMinutes) + (t.extraMinutes ?? 0);
}

/** 5분 안 된 기록은 실수로 체크한 것으로 보고 남기지 않는다. */
export const MIN_ACTUAL = 5;

export function addSample(d: DurationLearning, s: DurationSample): DurationLearning {
  if (s.est <= 0 || s.actual < MIN_ACTUAL) return d;
  const r = s.actual / s.est;
  return { ...d, samples: [...d.samples, { ...s, outlier: r < 1 / 3 || r > 3 || undefined }].slice(-MAX_SAMPLES) };
}

/** 사람이 읽는 설명(예: '숙제는 보통 예상보다 1.3배 걸렸어요'). */
export function calibrationText(t: Pick<TaskItem, 'type' | 'title'>, c: Calibration, typeLabel: string): string {
  const word = c.basis === 'title' ? t.title : typeLabel;
  const who = `${c.basis === 'title' ? `'${word}'` : word}${hasBatchim(word) ? '은' : '는'}`;
  const x = String(Math.round(c.ratio * 100) / 100);
  return c.ratio > 1 ? `${who} 보통 예상보다 ${x}배 걸렸어요` : `${who} 보통 예상보다 빨리 끝냈어요(${x}배)`;
}
