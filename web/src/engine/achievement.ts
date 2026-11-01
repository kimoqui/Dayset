import { type Activity, type ActivityLog, addMin, blockMinutes, diffMin, isAfter, isEstimate, isOpen, minutesUntil, type ScheduleBlock } from './models';

export type Outcome = 'achieved' | 'missed' | 'estimated' | 'pending';

export interface BlockOutcome {
  block: ScheduleBlock;
  outcome: Outcome;
  log?: ActivityLog;
}

export interface HabitRate {
  activity: Activity;
  achieved: number;
  /** 달성률 분모(예정 블록 중 추정·예정을 뺀 것). */
  counted: number;
  estimated: number;
}

export const rateOf = (r: { achieved: number; counted: number }): number | null =>
  r.counted === 0 ? null : r.achieved / r.counted;

export interface PeriodSummary {
  byActivity: Partial<Record<Activity, HabitRate>>;
  achieved: number;
  counted: number;
  rate: number | null;
  /** 달성률이 가장 높은 습관(회고 카드 '잘한 것'). */
  best: HabitRate | null;
  /** 달성률이 가장 낮은 습관(회고 카드 '놓친 것'). */
  worst: HabitRate | null;
}

/**
 * 달성 판정(엔진 명세 9번).
 *
 * - 확정 기록이 있고 시작이 예정 ±30분 안이면 달성
 * - 수면은 취침 ±30분 그리고 목표 수면시간의 90% 이상
 * - 추정 기록은 분모·분자에서 모두 뺀다
 */
export class AchievementCalculator {
  constructor(
    readonly toleranceMinutes = 30,
    readonly sleepRatio = 0.9,
  ) {}

  /** 판정 대상이 아니면 null(캘린더 고정 일정, 이동, 버퍼). */
  judge(block: ScheduleBlock, logs: ActivityLog[], now: Date, goalSleepMinutes?: number): BlockOutcome | null {
    const activity = block.activity;
    if (!activity || block.kind === 'fixed' || block.kind === 'buffer') return null;
    // 할 일 블록은 업무를 이어서 하는 중에 시작되는 경우가 많다. 블록 시작 시각에
    // 이미 진행 중인 업무 기록도 그 블록의 기록으로 본다.
    const covers = (l: ActivityLog): boolean =>
      block.kind === 'task' && !isAfter(l.start, block.start) && isAfter(l.end ?? now, block.start);
    const near = logs.filter(
      (l) => l.activity === activity && (Math.abs(diffMin(l.start, block.start)) <= this.toleranceMinutes || covers(l)),
    );
    const confirmed = near.filter((l) => !isEstimate(l));

    if (confirmed.length > 0) {
      const log = confirmed[0];
      if (activity === 'sleep') {
        const goal = goalSleepMinutes ?? blockMinutes(block);
        if (isOpen(log)) return { block, outcome: 'pending', log };
        const ok = minutesUntil(log, now) >= goal * this.sleepRatio;
        return { block, outcome: ok ? 'achieved' : 'missed', log };
      }
      return { block, outcome: 'achieved', log };
    }
    if (near.length > 0) return { block, outcome: 'estimated', log: near[0] };

    const deadline = addMin(block.start, this.toleranceMinutes);
    return { block, outcome: isAfter(now, deadline) ? 'missed' : 'pending' };
  }

  judgeAll(blocks: ScheduleBlock[], logs: ActivityLog[], now: Date, goalSleepMinutes?: number): BlockOutcome[] {
    const out: BlockOutcome[] = [];
    for (const b of blocks) {
      const o = this.judge(b, logs, now, goalSleepMinutes);
      if (o) out.push(o);
    }
    return out;
  }

  summarize(outcomes: BlockOutcome[]): PeriodSummary {
    const map: Partial<Record<Activity, HabitRate>> = {};
    for (const o of outcomes) {
      const a = o.block.activity!;
      const r = map[a] ?? { activity: a, achieved: 0, counted: 0, estimated: 0 };
      map[a] = {
        activity: a,
        achieved: r.achieved + (o.outcome === 'achieved' ? 1 : 0),
        counted: r.counted + (o.outcome === 'achieved' || o.outcome === 'missed' ? 1 : 0),
        estimated: r.estimated + (o.outcome === 'estimated' ? 1 : 0),
      };
    }
    const rates = Object.values(map) as HabitRate[];
    const achieved = rates.reduce((s, r) => s + r.achieved, 0);
    const counted = rates.reduce((s, r) => s + r.counted, 0);
    const pick = (better: (a: number, b: number) => boolean): HabitRate | null => {
      let out: HabitRate | null = null;
      for (const r of rates) {
        const v = rateOf(r);
        if (v == null) continue;
        if (out == null || better(v, rateOf(out)!)) out = r;
      }
      return out;
    };
    return {
      byActivity: map,
      achieved,
      counted,
      rate: counted === 0 ? null : achieved / counted,
      best: pick((a, b) => a > b),
      worst: pick((a, b) => a < b),
    };
  }
}
