import { describe, expect, it } from 'vitest';
import { anonName, cellOf, distanceBand, emptyNearby, nearbyBoard } from '../nearby';
import { makeFriendCode, readFriendCode } from '../social';
import type { StreakInfo } from '../streak';

const now = new Date(2026, 9, 21, 12, 0);
const info = { current: 5, best: 9, weekSetDays: 3 } as StreakInfo;

describe('근처 익명 겨루기', () => {
  it('익명 별명은 기기마다 고정되고 실명과 무관하다', () => {
    expect(anonName('u-abc')).toBe(anonName('u-abc'));
    expect(anonName('u-abc')).toMatch(/^\S+ \S+ #\d{3}$/);
  });

  it('위치는 약 2km 칸으로만 남는다', () => {
    expect(cellOf(37.3851, 126.9512)).toBe('37.38,126.94');
    expect(cellOf(37.3899, 126.9599)).toBe('37.38,126.94');
    expect(distanceBand('37.38,126.94', '37.38,126.94')).toBe('2km 안');
    expect(distanceBand('37.38,126.94', '37.38,126.96')).toBe('4km 안');
    expect(distanceBand('37.38,126.94', '37.50,126.94')).toBe('멀리');
    expect(distanceBand(undefined, '37.38,126.94')).toBeNull();
  });

  it('익명 코드는 이름 대신 별명과 칸만 담는다', () => {
    const code = makeFriendCode({ id: 'u-me', name: anonName('u-me') }, info, now, { anon: true, cell: '37.38,126.94' });
    const f = readFriendCode(code)!;
    expect(f.anon).toBe(true);
    expect(f.cell).toBe('37.38,126.94');
    expect(f.name).toBe(anonName('u-me'));
  });

  it('이번 주 셋 데이 → 연속 일수 순으로 줄 세우고, 지난주 기록은 0으로 본다', () => {
    const n = { ...emptyNearby(), on: true, cell: '37.38,126.94' };
    n.people = [
      { id: 'a', name: 'A', weekSetDays: 5, streak: 2, best: 2, week: '2026-10-19', at: now } as never,
      { id: 'b', name: 'B', weekSetDays: 6, streak: 9, best: 9, week: '2026-10-12', at: now } as never,
      { id: 'c', name: 'C', weekSetDays: 3, streak: 1, best: 1, week: '2026-10-19', at: now } as never,
    ];
    const b = nearbyBoard('u-me', info, n, now);
    expect(b.rows.map((r) => r.id)).toEqual(['a', 'u-me', 'c', 'b']);
    expect(b.myRank).toBe(2);
    expect(b.topPercent).toBe(50);
  });
});
