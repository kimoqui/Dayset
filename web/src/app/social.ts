// 친구와 겨루기(로컬 버전). 서버 없이 '친구 코드'를 주고받아 이번 주 셋 데이 순위를 본다.
// 앱 버전에서는 같은 구조를 서버(Supabase)에 올려 실시간 순위로 바꾼다.

import { dateKey, mondayOf } from '../engine/models';
import type { StreakInfo } from './streak';

export interface Friend {
  id: string;
  name: string;
  streak: number;
  best: number;
  /** 코드를 만든 주(월요일 날짜)와 그 주의 셋 데이 수. */
  week: string;
  weekSetDays: number;
  monthSetDays: number;
  updatedAt: Date;
  /** 근처 익명 보드에서 온 사람(실명 대신 익명 별명). */
  anon?: boolean;
  /** 약 2km로 뭉갠 위치 칸. */
  cell?: string;
  /** 예시 데이터 표시. */
  demo?: boolean;
}

const PREFIX = 'DS1-';

function toBase64Url(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(code: string): string {
  const b64 = code.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((code.length + 3) % 4);
  const bin = atob(b64);
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
}

/** 내 기록을 친구 코드로 만든다. */
export function makeFriendCode(p: { id: string; name: string }, info: StreakInfo, now: Date, extra: { anon?: boolean; cell?: string } = {}): string {
  const payload = {
    ...(extra.anon ? { a: 1 } : {}),
    ...(extra.cell ? { c: extra.cell } : {}),
    i: p.id,
    n: p.name,
    s: info.current,
    b: info.best,
    w: dateKey(mondayOf(now)),
    d: info.weekSetDays,
    m: info.monthSetDays,
    t: now.getTime(),
  };
  return PREFIX + toBase64Url(JSON.stringify(payload));
}

/** 붙여 넣은 글에서 친구 코드를 찾아 읽는다. 공유 문구 전체를 붙여 넣어도 된다. */
export function readFriendCode(text: string): Friend | null {
  const m = text.match(/DS1-[A-Za-z0-9_-]{10,}/);
  if (!m) return null;
  try {
    const j = JSON.parse(fromBase64Url(m[0].slice(PREFIX.length)));
    if (typeof j.i !== 'string' || typeof j.n !== 'string') return null;
    const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? Math.max(0, Math.round(v)) : 0);
    return {
      id: j.i.slice(0, 40),
      name: j.n.slice(0, 20) || '친구',
      streak: num(j.s),
      best: num(j.b),
      week: typeof j.w === 'string' ? j.w.slice(0, 10) : '',
      weekSetDays: Math.min(7, num(j.d)),
      monthSetDays: Math.min(31, num(j.m)),
      updatedAt: new Date(num(j.t) || Date.now()),
      anon: j.a === 1,
      cell: typeof j.c === 'string' && /^-?\d+\.\d{2},-?\d+\.\d{2}$/.test(j.c) ? j.c : undefined,
    };
  } catch {
    return null;
  }
}

export interface RankRow {
  id: string;
  name: string;
  me: boolean;
  weekSetDays: number;
  streak: number;
  /** 이번 주 기록이 아니면 지난 기록이라고 표시한다. */
  stale: boolean;
  updatedAt: Date | null;
}

/** 이번 주 순위: 셋 데이 수 → 연속 기록 순. 다른 주에 만든 코드는 이번 주 0일로 본다. */
export function leaderboard(me: { id: string; name: string }, info: StreakInfo, friends: Friend[], now: Date): RankRow[] {
  const week = dateKey(mondayOf(now));
  const rows: RankRow[] = [
    { id: me.id, name: me.name || '나', me: true, weekSetDays: info.weekSetDays, streak: info.current, stale: false, updatedAt: null },
    ...friends.map((f) => ({
      id: f.id,
      name: f.name,
      me: false,
      weekSetDays: f.week === week ? f.weekSetDays : 0,
      streak: f.streak,
      stale: f.week !== week,
      updatedAt: f.updatedAt,
    })),
  ];
  return rows.sort((a, b) => b.weekSetDays - a.weekSetDays || b.streak - a.streak || (a.me ? -1 : b.me ? 1 : 0));
}
