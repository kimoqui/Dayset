// 근처 사람들과 익명으로 겨루기.
//
// 개인정보 원칙
//  - 실명·사진·정확한 위치는 쓰지 않는다. 기기마다 정해지는 익명 별명(예: '새벽 수달 #284')만 보인다.
//  - 위치는 사용자가 켰을 때만 읽고, 위도·경도를 약 2km 칸으로 뭉개서 칸 이름만 저장한다.
//  - 로컬 버전은 서버가 없어, 가까이 있는 사람과 QR·코드를 직접 주고받아 보드에 올린다.
//    앱 버전에서는 같은 칸 사람들이 서버를 통해 자동으로 보인다.

import { dateKey, mondayOf } from '../engine/models';
import type { Friend } from './social';
import type { StreakInfo } from './streak';

const ADJ = ['새벽', '부지런한', '차분한', '느긋한', '반짝이는', '꾸준한', '용감한', '산뜻한', '단단한', '포근한', '씩씩한', '고요한'];
const ANIMAL = ['수달', '고래', '여우', '부엉이', '다람쥐', '펭귄', '판다', '고양이', '사슴', '토끼', '거북이', '참새'];

function hash(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** 기기마다 고정되는 익명 별명. 실명과 연결되지 않는다. */
export function anonName(deviceId: string): string {
  const h = hash(deviceId);
  return `${ADJ[h % ADJ.length]} ${ANIMAL[(h >>> 8) % ANIMAL.length]} #${String((h >>> 16) % 1000).padStart(3, '0')}`;
}

/** 위도·경도를 약 2km 칸으로 뭉갠다(0.02도 ≈ 위도 2.2km). 정확한 위치는 남기지 않는다. */
export function cellOf(lat: number, lon: number): string {
  const r = (v: number) => (Math.floor(v / 0.02) * 0.02).toFixed(2);
  return `${r(lat)},${r(lon)}`;
}

/** 두 칸 사이 거리대. 같은 칸 = 2km 안, 바로 옆 칸 = 4km 안. */
export function distanceBand(a?: string, b?: string): string | null {
  if (!a || !b) return null;
  const [la, lo] = a.split(',').map(Number);
  const [lb, lob] = b.split(',').map(Number);
  const d = Math.max(Math.abs(la - lb), Math.abs(lo - lob)) / 0.02;
  if (d < 0.5) return '2km 안';
  if (d < 1.5) return '4km 안';
  if (d < 3.5) return '8km 안';
  return '멀리';
}

export interface NearbyState {
  /** 근처에 익명으로 보이기(동의). */
  on: boolean;
  cell?: string;
  cellAt?: Date;
  people: Friend[];
}

export const emptyNearby = (): NearbyState => ({ on: false, people: [] });

export interface NearbyRow {
  id: string;
  name: string;
  me: boolean;
  weekSetDays: number;
  streak: number;
  band: string | null;
  demo: boolean;
}

export interface NearbyBoard {
  rows: NearbyRow[];
  myRank: number;
  /** 상위 몇 %인지(1~100). */
  topPercent: number;
  avgWeek: number;
}

export function nearbyBoard(deviceId: string, info: StreakInfo, n: NearbyState, now: Date): NearbyBoard {
  const week = dateKey(mondayOf(now));
  const rows: NearbyRow[] = [
    { id: deviceId, name: anonName(deviceId), me: true, weekSetDays: info.weekSetDays, streak: info.current, band: null, demo: false },
    ...n.people.map((p) => ({
      id: p.id,
      name: p.name,
      me: false,
      weekSetDays: p.week === week ? p.weekSetDays : 0,
      streak: p.streak,
      band: distanceBand(n.cell, p.cell),
      demo: !!p.demo,
    })),
  ].sort((a, b) => b.weekSetDays - a.weekSetDays || b.streak - a.streak || (a.me ? -1 : b.me ? 1 : 0));
  const myRank = rows.findIndex((r) => r.me) + 1;
  const avgWeek = rows.reduce((s, r) => s + r.weekSetDays, 0) / rows.length;
  return { rows, myRank, topPercent: Math.max(1, Math.round((myRank / rows.length) * 100)), avgWeek };
}
