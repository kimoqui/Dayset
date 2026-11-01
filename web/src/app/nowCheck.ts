// 일정 체크: 지금 일정과 지금 기록을 맞춰 보고, 기록할 때를 알려 준다.
//
// - due  : 일정이 시작됐는데 그 활동이 기록되지 않음 → "점심 식사 시간이에요, 시작했으면 눌러 주세요"
// - ok   : 일정대로 기록 중
// - over : 일정은 끝났는데 그 활동 기록이 이어지는 중(끝날 때 누르기를 잊은 경우) → "끝났으면 눌러 주세요"
// - next : 지금 일정이 없음 → 다음 일정 미리 보기
// - none : 오늘 일정이 아직 없음(첫날 기록 중 등)
// 수면은 기상·취침 알람이 맡고, 이동(buffer)은 기록 대상이 아니라서 보지 않는다.

import { type Activity, dateKey, diffMin, isAfter, isBefore, type ScheduleBlock } from '../engine/models';
import { currentLog } from './derive';
import type { AppState } from './state';

export type CheckKind = 'due' | 'ok' | 'over' | 'next' | 'none';

export interface NowCheck {
  kind: CheckKind;
  block?: ScheduleBlock;
  /** 그 일정에서 기대하는 활동. */
  expected?: Activity;
  /** 지금 기록 중인 활동. */
  current: Activity | null;
  /** 지금 기록이 시작된 지 몇 분. */
  currentMinutes: number;
  /** 일정이 시작된 지 몇 분(due), 끝난 지 몇 분(over), 시작까지 몇 분(next). */
  minutes: number;
  next?: ScheduleBlock;
  /** 사용자가 '지금은 안 해요'로 넘긴 조각이면 true(팝업은 작게, 알림은 보내지 않음). */
  skipped: boolean;
}

/** 일정 조각에서 기대하는 활동. 할 일·회의·수업은 업무로 본다. */
export function expectedActivity(b: ScheduleBlock): Activity | null {
  if (b.kind === 'buffer') return null;
  if (b.kind === 'task' || b.kind === 'fixed') return 'work';
  const a = b.activity ?? null;
  return a === 'sleep' ? null : a;
}

/** 일정이 끝난 뒤 이 시간 안이면 '끝났으면 눌러 주세요'를 묻는다. */
const OVER_WINDOW = 45;

export function nowCheck(s: AppState, now: Date): NowCheck {
  const log = currentLog(s);
  const current = log?.activity ?? null;
  const currentMinutes = log ? Math.max(0, Math.round(diffMin(now, log.start))) : 0;
  const base = { current, currentMinutes, skipped: false };
  const plan = s.plans[dateKey(now)];
  if (!s.onboarded || s.observation?.phase === 'recording' || !plan) return { ...base, kind: 'none', minutes: 0 };

  const blocks = plan.blocks.filter((b) => expectedActivity(b) != null);
  const next = blocks.find((b) => isAfter(b.start, now));
  const block = blocks.find((b) => !isAfter(b.start, now) && isBefore(now, b.end));

  if (block) {
    const expected = expectedActivity(block)!;
    if (current === expected) return { ...base, kind: 'ok', block, expected, minutes: Math.round(diffMin(now, block.start)), next };
    return { ...base, kind: 'due', block, expected, minutes: Math.round(diffMin(now, block.start)), next, skipped: s.checkSkips.includes(block.id) };
  }

  // 방금 끝난 일정의 활동이 아직 이어지면 끝났는지 묻는다(휴식은 묻지 않는다).
  const prev = [...blocks].reverse().find((b) => !isAfter(b.end, now));
  if (prev && current && current !== 'rest' && current === expectedActivity(prev)) {
    const after = Math.round(diffMin(now, prev.end));
    if (after <= OVER_WINDOW) return { ...base, kind: 'over', block: prev, expected: current, minutes: after, next, skipped: s.checkSkips.includes(`${prev.id}:over`) };
  }
  return { ...base, kind: 'next', next, minutes: next ? Math.round(diffMin(next.start, now)) : 0 };
}

/** 알림·팝업을 다시 띄울지 판단하는 열쇠(같은 열쇠면 한 번만). */
export const checkKey = (c: NowCheck): string => `${c.kind}:${c.block?.id ?? c.next?.id ?? '-'}`;
