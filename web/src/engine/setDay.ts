// 핵심 지표 '셋 데이(Set Day)' 판정.
//
// 셋 데이 = 기상 알람 ±30분 안에 기상을 기록하고, 그날 습관 블록을 70% 이상 달성한 날.
// 저녁 확인에서 고른 '못 했어요'(놓침)와 '쉬는 날'(판정 제외)도 함께 반영한다.

import { AchievementCalculator, type BlockOutcome } from './achievement';
import { type ActivityLog, diffMin, type ScheduleBlock } from './models';

export interface DayMarks {
  /** 저녁 확인에서 '못 했어요'로 고른 블록 id. */
  missed: Set<string>;
  /** 저녁 확인에서 '쉬는 날'로 고른 블록 id(판정에서 뺀다). */
  skipped: Set<string>;
  /** 하루 전체를 쉬는 날로 표시했는지. */
  rest: boolean;
}

export const emptyMarks = (): DayMarks => ({ missed: new Set(), skipped: new Set(), rest: false });

export interface DayEvaluation {
  /** 판정 대상 블록(습관 + 할 일) 결과. */
  outcomes: BlockOutcome[];
  /** 습관 블록(수면·식사·운동) 결과. 셋 데이 판정에 쓴다. */
  habits: BlockOutcome[];
  wakeAt: Date | null;
  wakeOk: boolean;
  achieved: number;
  /** 분모: 습관 블록 중 추정을 뺀 수. */
  total: number;
  rate: number | null;
  rest: boolean;
  isSetDay: boolean;
}

export function evaluateDay(p: {
  blocks: ScheduleBlock[];
  logs: ActivityLog[];
  /** 그 날 기상 알람 시각. */
  wake: Date;
  /** 실제 기상 기록 시각. */
  wakeAt: Date | null;
  now: Date;
  goalSleepMinutes: number;
  marks?: DayMarks;
  setRatio?: number;
  wakeToleranceMinutes?: number;
}): DayEvaluation {
  const marks = p.marks ?? emptyMarks();
  const calc = new AchievementCalculator();
  const outcomes = calc
    .judgeAll(
      p.blocks.filter((b) => !marks.skipped.has(b.id)),
      p.logs,
      p.now,
      p.goalSleepMinutes,
    )
    .map((o) => (marks.missed.has(o.block.id) && o.outcome !== 'achieved' ? { ...o, outcome: 'missed' as const } : o));
  const habits = outcomes.filter((o) => o.block.kind === 'habit');
  const total = habits.filter((o) => o.outcome !== 'estimated').length;
  const achieved = habits.filter((o) => o.outcome === 'achieved').length;
  const rate = total === 0 ? null : achieved / total;
  const tol = p.wakeToleranceMinutes ?? 30;
  const wakeOk = p.wakeAt != null && Math.abs(diffMin(p.wakeAt, p.wake)) <= tol;
  const isSetDay = !marks.rest && wakeOk && rate != null && rate >= (p.setRatio ?? 0.7);
  return { outcomes, habits, wakeAt: p.wakeAt, wakeOk, achieved, total, rate, rest: marks.rest, isSetDay };
}
