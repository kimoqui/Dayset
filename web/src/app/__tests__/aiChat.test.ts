import { describe, expect, it } from 'vitest';
import { aiContext, readAiReply } from '../aiChat';
import { CloudClient } from '../cloud';
import { demoState } from '../seed';
import { addDays, dateKey } from '../../engine/models';

const now = new Date(2026, 10, 2, 9, 0); // 월요일 오전 9시
const s = demoState(now);
const today = dateKey(now);
const tomorrow = dateKey(addDays(now, 1));

describe('서버 AI 답 읽기', () => {
  it('요약에 습관·사흘 일정·일정 id가 들어간다', () => {
    const c = aiContext(s, now);
    expect(c.now).toBe(`${today}T09:00`);
    expect(c.habits).toContain('운동');
    expect(c.days).toHaveLength(3);
    expect(c.days[0].habits.length).toBeGreaterThan(0);
    for (const e of c.events) expect(s.events.some((x) => x.id === e.id)).toBe(true);
  });

  it('맞는 항목은 바꾸기 목록으로 바꾼다', () => {
    const r = readAiReply(
      {
        reply: '내일 운동을 저녁 9시로 옮길게요.',
        edits: [
          { kind: 'habit', day: tomorrow, title: '운동', start: '21:00', scope: 'day' },
          { kind: 'wake', day: tomorrow, start: '06:30', scope: 'every' },
          { kind: 'event-add', title: '치과', start: `${tomorrow}T15:00`, end: `${tomorrow}T16:00` },
          { kind: 'task-add', title: '보고서', minutes: 120, taskType: 'work', due: tomorrow },
        ],
      },
      s,
      now,
    );
    expect(r?.edits).toEqual([
      { kind: 'habit', day: tomorrow, title: '운동', patch: { start: 21 * 60 }, scope: 'day' },
      { kind: 'wake', day: tomorrow, minutes: 6 * 60 + 30, scope: 'every' },
      { kind: 'event-add', title: '치과', start: new Date(2026, 10, 3, 15), end: new Date(2026, 10, 3, 16) },
      { kind: 'task-add', title: '보고서', minutes: 120, type: 'work', dueAt: new Date(2026, 10, 3, 23) },
    ]);
    expect(r?.reply).toBe('내일 운동을 저녁 9시로 옮길게요.');
  });

  it('없는 습관·없는 일정·지난 날·이상한 시각은 버리고 알려 준다', () => {
    const r = readAiReply(
      {
        reply: '바꿀게요.',
        edits: [
          { kind: 'habit', day: today, title: '명상', start: '07:00' },
          { kind: 'event-delete', id: 'nope' },
          { kind: 'habit', day: dateKey(addDays(now, -1)), title: '운동', skip: true },
          { kind: 'wake', day: today, start: '25:00' },
          { kind: 'drop-table' },
        ],
      },
      s,
      now,
    );
    expect(r?.edits).toEqual([]);
    expect(r?.unknown).toEqual(['명상', '일정', '지난 날', '기상 시각']);
    expect(r?.reply).toContain('바꿀 수 없는 것은 뺐어요');
  });

  it('가져온 캘린더 일정은 옮기거나 지우지 않는다', () => {
    const ev = { id: 'g1', title: '수업', start: new Date(2026, 10, 3, 10), end: new Date(2026, 10, 3, 11), source: 'google' };
    const st = { ...s, events: [...s.events, ev] };
    const r = readAiReply({ reply: '', edits: [{ kind: 'event-delete', id: 'g1' }, { kind: 'event-move', id: 'g1', start: `${tomorrow}T12:00`, end: `${tomorrow}T13:00` }] }, st, now);
    expect(r?.edits).toEqual([]);
  });

  it('형식이 틀리면 null(기기 안 규칙으로 읽는다)', () => {
    expect(readAiReply(null, s, now)).toBeNull();
    expect(readAiReply('hello', s, now)).toBeNull();
    expect(readAiReply({ edits: 'x' }, s, now)).toBeNull();
  });

  it('클라이언트는 로그인 토큰으로 서버 함수를 부른다', async () => {
    let seen: { url: string; auth: string; body: unknown } | null = null;
    const c = new CloudClient({ url: 'https://x.supabase.co', key: 'pk' }, async (url, init) => {
      seen = { url, auth: String((init?.headers as Record<string, string>).Authorization), body: JSON.parse(String(init?.body)) };
      return new Response(JSON.stringify({ reply: 'ok', edits: [] }), { status: 200 });
    });
    const out = await c.askChat({ accessToken: 'tok', refreshToken: 'r', expiresAt: Date.now() + 3e6, userId: 'u', email: 'a@b.c' }, '내일 운동 빼줘', { now: 'x' });
    expect(out).toEqual({ reply: 'ok', edits: [] });
    expect(seen).toEqual({ url: 'https://x.supabase.co/functions/v1/dayset-chat', auth: 'Bearer tok', body: { text: '내일 운동 빼줘', context: { now: 'x' } } });
  });

  it('새 공개 키(sb_publishable)는 apikey 머리에만 둔다', async () => {
    const seen: Record<string, string>[] = [];
    const c = new CloudClient({ url: 'https://x.supabase.co', key: 'sb_publishable_abc' }, async (_url, init) => {
      seen.push(init?.headers as Record<string, string>);
      return new Response(JSON.stringify({ access_token: 'a', refresh_token: 'r', expires_in: 3600, user: { id: 'u', email: 'a@b.c' } }), { status: 200 });
    });
    await c.signIn('a@b.c', 'pw123456');
    expect(seen[0].apikey).toBe('sb_publishable_abc');
    expect(seen[0].Authorization).toBeUndefined();
  });
});
