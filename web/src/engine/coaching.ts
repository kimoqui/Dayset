// 연결 코칭(엔진 명세 5번·7번).
//
// 규칙의 수치는 RuleConfig로 원격 설정에서 내려받아 앱 업데이트 없이 바꾼다.
// 조건 판단은 규칙마다 코드로 두고, 문턱값만 설정으로 뺀다(안전한 구조).

import {
  type Activity,
  ACTIVITY_LABEL,
  addMin,
  blockMinutes,
  diffMin,
  formatDuration,
  isAfter,
  type MissReason,
  sameDay,
  type ScheduleBlock,
} from './models';

// ---------------------------------------------------------------------------
// 규칙 설정
// ---------------------------------------------------------------------------

export interface RuleConfig {
  id: string;
  enabled: boolean;
  params: Record<string, number>;
}

export const p = (r: RuleConfig, key: string, fallback: number): number => r.params[key] ?? fallback;

/** 기본 규칙값. 원격 설정이 없을 때 쓴다. */
export const DEFAULT_RULES: RuleConfig[] = [
  { id: 'R1', enabled: true, params: { min_sleep_minutes: 360, max_focus_blocks: 2, exercise_minutes: 15 } },
  { id: 'R2', enabled: true, params: { min_gap_before_bed_minutes: 180, dinner_shift_minutes: 30 } },
  { id: 'R3', enabled: true, params: { late_minutes: 60, exercise_minutes: 15 } },
  { id: 'R4', enabled: true, params: { min_snooze: 3, days: 3, bedtime_shift_minutes: 15 } },
  { id: 'R5', enabled: true, params: { missed_meals: 2 } },
  { id: 'R6', enabled: true, params: { repeat: 2, remind_before_minutes: 5 } },
  { id: 'R7', enabled: true, params: { repeat: 2 } },
  { id: 'R8', enabled: true, params: { repeat: 2 } },
  { id: 'R9', enabled: true, params: { repeat: 2, shrink_to_minutes: 10 } },
];

export function parseRules(json: unknown): RuleConfig[] {
  if (!Array.isArray(json)) return DEFAULT_RULES;
  return json.map((j) => ({
    id: String(j.id),
    enabled: j.enabled ?? true,
    params: Object.fromEntries(Object.entries(j.params ?? {}).map(([k, v]) => [k, Number(v)])),
  }));
}

// ---------------------------------------------------------------------------
// 이벤트(트리거)
// ---------------------------------------------------------------------------

export type CoachEvent =
  /** 기상 기록(R1, R4). recentSnoozes는 최근 며칠의 스누즈 횟수, 마지막이 오늘. */
  | { type: 'wakeLogged'; sleepMinutes: number; recentSnoozes?: number[] }
  /** 저녁 식사 기록(R2). */
  | { type: 'dinnerLogged'; end: Date; bedtime: Date }
  /** 업무 종료 기록(R3). */
  | { type: 'workEnded'; planned: Date; actual: Date }
  /** 저녁 확인(R5). */
  | { type: 'eveningCheck'; missedMeals: number }
  /** 실패 이유 입력(R6~R9). weekCount는 같은 주, 같은 습관에서 그 이유를 고른 횟수. */
  | { type: 'missReason'; habit: Activity; reason: MissReason; weekCount: number; habitMinutes?: number };

// ---------------------------------------------------------------------------
// 제안
// ---------------------------------------------------------------------------

export interface BlockChange {
  blockId: string;
  newMinutes?: number;
  newTitle?: string;
  deferToTomorrow: boolean;
}

const shrink = (blockId: string, newMinutes: number, newTitle: string): BlockChange => ({
  blockId,
  newMinutes,
  newTitle,
  deferToTomorrow: false,
});
const defer = (blockId: string): BlockChange => ({ blockId, deferToTomorrow: true });

export type Patch = Record<string, string | number | boolean>;

export interface CoachingSuggestion {
  ruleId: string;
  /** 'UX 문구 가이드'를 따른다: 사실 + 다음 행동, 판단하지 않는다. */
  message: string;
  /** 오늘 일정 블록 변경. */
  changes: BlockChange[];
  /** 블록이 아닌 변경(내일 일정·알람·알림 설정). 키는 설정 저장소가 해석한다. */
  patch: Patch;
}

export type CoachDecision = 'accepted' | 'rejected' | 'expired';

export interface CoachRecord {
  ruleId: string;
  at: Date;
  decision: CoachDecision;
}

/** 하루 3건 이하, 같은 규칙을 2번 연속 거절하면 7일간 쉰다. */
export class CoachingPolicy {
  constructor(
    readonly maxPerDay = 3,
    readonly rejectStreak = 2,
    readonly cooldownDays = 7,
  ) {}

  allows(ruleId: string, now: Date, history: CoachRecord[], shownToday = 0): boolean {
    const today = history.filter((r) => sameDay(r.at, now)).length + shownToday;
    if (today >= this.maxPerDay) return false;
    const mine = history.filter((r) => r.ruleId === ruleId).sort((a, b) => a.at.getTime() - b.at.getTime());
    if (mine.length < this.rejectStreak) return true;
    const last = mine.slice(mine.length - this.rejectStreak);
    const streak = last.every((r) => r.decision === 'rejected');
    if (!streak) return true;
    const days = Math.trunc((now.getTime() - last[last.length - 1].at.getTime()) / 86400000);
    return days >= this.cooldownDays;
  }
}

// ---------------------------------------------------------------------------
// 엔진
// ---------------------------------------------------------------------------

export class CoachingEngine {
  readonly rules: Map<string, RuleConfig>;

  constructor(
    rules: RuleConfig[] = DEFAULT_RULES,
    readonly policy = new CoachingPolicy(),
  ) {
    this.rules = new Map(rules.map((r) => [r.id, r]));
  }

  evaluate(
    event: CoachEvent,
    ctx: { today: ScheduleBlock[]; now: Date; history?: CoachRecord[]; shownToday?: number },
  ): CoachingSuggestion[] {
    const history = ctx.history ?? [];
    const raw: (CoachingSuggestion | null)[] = [];
    switch (event.type) {
      case 'wakeLogged':
        raw.push(this.r1(event, ctx.today, ctx.now), this.r4(event));
        break;
      case 'dinnerLogged':
        raw.push(this.r2(event));
        break;
      case 'workEnded':
        raw.push(this.r3(event, ctx.today, ctx.now));
        break;
      case 'eveningCheck':
        raw.push(this.r5(event));
        break;
      case 'missReason':
        raw.push(this.missReason(event));
        break;
    }
    const out: CoachingSuggestion[] = [];
    for (const s of raw) {
      if (!s) continue;
      if (this.policy.allows(s.ruleId, ctx.now, history, (ctx.shownToday ?? 0) + out.length)) out.push(s);
    }
    return out;
  }

  private on(id: string): RuleConfig | null {
    const r = this.rules.get(id);
    return r && r.enabled ? r : null;
  }

  private r1(e: Extract<CoachEvent, { type: 'wakeLogged' }>, today: ScheduleBlock[], now: Date): CoachingSuggestion | null {
    const r = this.on('R1');
    if (!r || e.sleepMinutes >= p(r, 'min_sleep_minutes', 360)) return null;
    const exMin = Math.trunc(p(r, 'exercise_minutes', 15));
    const maxFocus = Math.trunc(p(r, 'max_focus_blocks', 2));
    const changes: BlockChange[] = [];
    const upcoming = today.filter((b) => isAfter(b.end, now));
    for (const b of upcoming) {
      if (b.activity === 'exercise' && blockMinutes(b) > exMin) {
        changes.push(shrink(b.id, exMin, `운동 · ${exMin}분 가벼운 루틴`));
      }
    }
    const focus = upcoming.filter((b) => b.kind === 'task' && b.focus);
    for (const b of focus.slice(maxFocus)) changes.push(defer(b.id));
    if (changes.length === 0) return null;
    const hasExercise = changes.some((c) => !c.deferToTomorrow);
    const action = hasExercise ? `오늘 운동을 ${exMin}분 가벼운 루틴으로 바꿀까요?` : `오늘 집중 작업을 ${maxFocus}개로 줄일까요?`;
    return {
      ruleId: 'R1',
      message: `어젯밤 ${formatDuration(e.sleepMinutes)} 잤어요. ${action}`,
      changes,
      patch: {},
    };
  }

  private r2(e: Extract<CoachEvent, { type: 'dinnerLogged' }>): CoachingSuggestion | null {
    const r = this.on('R2');
    if (!r) return null;
    const gap = diffMin(e.bedtime, e.end);
    if (gap >= p(r, 'min_gap_before_bed_minutes', 180)) return null;
    const shift = Math.trunc(p(r, 'dinner_shift_minutes', 30));
    return {
      ruleId: 'R2',
      message:
        `저녁을 취침 ${formatDuration(gap < 0 ? 0 : gap)} 전에 마쳤어요. ` +
        `내일 저녁 식사를 ${shift}분 앞당기고, 아침은 가벼운 메뉴로 추천할까요?`,
      changes: [],
      patch: { tomorrow_dinner_shift_minutes: -shift, breakfast_light: true },
    };
  }

  private r3(e: Extract<CoachEvent, { type: 'workEnded' }>, today: ScheduleBlock[], now: Date): CoachingSuggestion | null {
    const r = this.on('R3');
    if (!r) return null;
    const late = diffMin(e.actual, e.planned);
    if (late < p(r, 'late_minutes', 60)) return null;
    const exMin = Math.trunc(p(r, 'exercise_minutes', 15));
    const changes = today
      .filter((b) => b.activity === 'exercise' && isAfter(b.end, now) && blockMinutes(b) > exMin)
      .map((b) => shrink(b.id, exMin, `운동 · ${exMin}분 가벼운 루틴`));
    if (changes.length === 0) return null;
    return {
      ruleId: 'R3',
      message: `업무가 예정보다 ${formatDuration(late)} 늦게 끝났어요. 오늘 운동을 ${exMin}분으로 줄일까요?`,
      changes,
      patch: {},
    };
  }

  private r4(e: Extract<CoachEvent, { type: 'wakeLogged' }>): CoachingSuggestion | null {
    const r = this.on('R4');
    if (!r) return null;
    const days = Math.trunc(p(r, 'days', 3));
    const minSnooze = p(r, 'min_snooze', 3);
    const snoozes = e.recentSnoozes ?? [];
    if (snoozes.length < days) return null;
    const lastDays = snoozes.slice(snoozes.length - days);
    if (!lastDays.every((n) => n >= minSnooze)) return null;
    const shift = Math.trunc(p(r, 'bedtime_shift_minutes', 15));
    return {
      ruleId: 'R4',
      message: `${days}일 연속 알람을 ${Math.trunc(minSnooze)}번 이상 미뤘어요. 취침 알람을 ${shift}분 앞당길까요?`,
      changes: [],
      patch: { bedtime_shift_minutes: -shift },
    };
  }

  private r5(e: Extract<CoachEvent, { type: 'eveningCheck' }>): CoachingSuggestion | null {
    const r = this.on('R5');
    if (!r || e.missedMeals < p(r, 'missed_meals', 2)) return null;
    return {
      ruleId: 'R5',
      message: `오늘 식사를 ${e.missedMeals}번 놓쳤어요. 내일 첫 끼는 단백질 위주 메뉴로 추천할까요?`,
      changes: [],
      patch: { next_meal_focus: 'protein' },
    };
  }

  private missReason(e: Extract<CoachEvent, { type: 'missReason' }>): CoachingSuggestion | null {
    const id = ({ forgot: 'R6', conflict: 'R7', tired: 'R8', unwilling: 'R9', other: null } as const)[e.reason];
    if (!id) return null;
    const r = this.on(id);
    if (!r || e.weekCount < p(r, 'repeat', 2)) return null;
    const h = ACTIVITY_LABEL[e.habit];
    const n = e.weekCount;
    switch (id) {
      case 'R6': {
        const before = Math.trunc(p(r, 'remind_before_minutes', 5));
        return {
          ruleId: id,
          message: `이번 주 ${h}${objectParticle(h)} 깜빡해서 ${n}번 놓쳤어요. ${before}분 전에 소리 알람으로 알려드릴까요?`,
          changes: [],
          patch: { habit: e.habit, remind_before_minutes: before, sound: true },
        };
      }
      case 'R7':
        return {
          ruleId: id,
          message: `이번 주 ${h}${subjectParticle(h)} 일·약속과 ${n}번 겹쳤어요. 다른 시간으로 옮길까요?`,
          changes: [],
          patch: { habit: e.habit, suggest_move: true },
        };
      case 'R8':
        return {
          ruleId: id,
          message: `이번 주 피곤해서 ${h}${objectParticle(h)} ${n}번 놓쳤어요. 교정 단계를 한 주 유지하고 수면부터 지킬까요?`,
          changes: [],
          patch: { hold_correction_week: true },
        };
      default: {
        const to = Math.trunc(p(r, 'shrink_to_minutes', 10));
        const size = e.habitMinutes != null ? `${e.habitMinutes}분 대신 ${to}분으로` : `${to}분으로`;
        return {
          ruleId: id,
          message: `${h}${objectParticle(h)} 더 작게 시작해볼까요? ${size} 줄여요.`,
          changes: [],
          patch: { habit: e.habit, shrink_to_minutes: to },
        };
      }
    }
  }
}

/** 제안을 승인했을 때 오늘 블록에 반영한다. 미룬 블록은 목록에서 빠지고 deferred에 담긴다. */
export function applyChanges(
  blocks: ScheduleBlock[],
  changes: BlockChange[],
): { blocks: ScheduleBlock[]; deferred: ScheduleBlock[] } {
  const byId = new Map(changes.map((c) => [c.blockId, c]));
  const kept: ScheduleBlock[] = [];
  const deferred: ScheduleBlock[] = [];
  for (const b of blocks) {
    const c = byId.get(b.id);
    if (!c) kept.push(b);
    else if (c.deferToTomorrow) deferred.push(b);
    else kept.push({ ...b, end: addMin(b.start, c.newMinutes!), title: c.newTitle ?? b.title, adjusted: true });
  }
  return { blocks: kept, deferred };
}

/** 받침이 있으면 '을', 없으면 '를'. */
export const objectParticle = (word: string): string => (hasBatchim(word) ? '을' : '를');

/** 받침이 있으면 '이', 없으면 '가'. */
export const subjectParticle = (word: string): string => (hasBatchim(word) ? '이' : '가');

export function hasBatchim(word: string): boolean {
  if (!word) return false;
  const code = word.codePointAt(word.length - 1)!;
  if (code < 0xac00 || code > 0xd7a3) return false;
  return (code - 0xac00) % 28 !== 0;
}
