// 단계적 교정 계획(엔진 명세 8번). MVP는 수면(기상)에만 쓴다.

export type CorrectionStatus = 'active' | 'done';

/** 주간 판정 결과(회고 카드와 '내 목표' 화면 문구에 쓴다). */
export type WeeklyDecision = 'stepUp' | 'stepBack' | 'hold' | 'keep' | 'done';

export const DECISION_LABEL: Record<WeeklyDecision, string> = {
  stepUp: '한 단계 올림',
  stepBack: '한 단계 내림',
  hold: '한 주 유지(피곤함)',
  keep: '그대로 유지',
  done: '목표 도달',
};

export interface CorrectionPlan {
  baseline: number;
  target: number;
  stepSize: number;
  totalWeeks: number;
  currentStep: number;
  status: CorrectionStatus;
}

/**
 * 최근 평균으로 계획을 만든다.
 *
 * 시각은 자정 기준 분이다. 새벽 1시 취침처럼 자정을 넘는 값은 25:00 = 1500으로
 * 넣는다. 예: baseline 1500(01:00), target 1380(23:00), step 30 → 4주.
 */
export function createCorrection(p: { baseline: number; target: number; stepSize: number }): CorrectionPlan {
  if (p.stepSize <= 0) throw new Error('stepSize must be positive');
  const gap = Math.abs(p.target - p.baseline);
  const weeks = Math.ceil(gap / p.stepSize);
  return {
    baseline: p.baseline,
    target: p.target,
    stepSize: p.stepSize,
    totalWeeks: weeks,
    currentStep: 0,
    status: weeks === 0 ? 'done' : 'active',
  };
}

const direction = (c: CorrectionPlan): number => (c.target < c.baseline ? -1 : 1);

function clampToTarget(c: CorrectionPlan, v: number): number {
  return direction(c) < 0 ? (v < c.target ? c.target : v) : v > c.target ? c.target : v;
}

/** 이번 주 목표값. 일정 엔진은 교정 중인 습관에 이 값을 쓴다. */
export function weekTarget(c: CorrectionPlan): number {
  return clampToTarget(c, c.baseline + direction(c) * c.stepSize * c.currentStep);
}

/** 다음 주 목표값(단계를 올렸을 때). */
export function nextTarget(c: CorrectionPlan): number {
  return clampToTarget(c, c.baseline + direction(c) * c.stepSize * (c.currentStep + 1));
}

/**
 * 매주 월요일 판정.
 *
 * - 피곤함이 같은 주 2번 이상이면 한 주 유지(R8)
 * - 달성률 80% 이상이면 한 단계 올림
 * - 50% 미만이면 한 단계 내림
 */
export function weeklyUpdate(
  c: CorrectionPlan,
  p: { achievementRate: number; tiredCount?: number },
): { plan: CorrectionPlan; decision: WeeklyDecision } {
  if (c.status === 'done') return { plan: c, decision: 'done' };
  let step = c.currentStep;
  let decision: WeeklyDecision;
  if ((p.tiredCount ?? 0) >= 2) {
    decision = 'hold';
  } else if (p.achievementRate >= 0.8) {
    step += 1;
    decision = 'stepUp';
  } else if (p.achievementRate < 0.5) {
    step = step > 0 ? step - 1 : 0;
    decision = 'stepBack';
  } else {
    decision = 'keep';
  }
  const done = step >= c.totalWeeks;
  return {
    plan: { ...c, currentStep: done ? c.totalWeeks : step, status: done ? 'done' : 'active' },
    decision: done ? 'done' : decision,
  };
}
