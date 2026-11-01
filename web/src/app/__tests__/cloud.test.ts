import { beforeEach, describe, expect, it } from 'vitest';
import { CloudClient, planSync, type RemoteState, type SyncMeta } from '../cloud';
import { fakeServer } from './fakeCloud';

const cfg = { url: 'https://x.supabase.co', key: 'anon' };

describe('계정 서버 연결', () => {
  let srv: ReturnType<typeof fakeServer>;
  let c: CloudClient;
  beforeEach(() => {
    srv = fakeServer();
    c = new CloudClient(cfg, srv.fetcher);
  });

  it('가입·로그인·잘못된 비밀번호·이미 가입한 이메일', async () => {
    const s = await c.signUp('a@b.c', 'secret1');
    expect(s).not.toBe('confirm');
    await expect(c.signUp('a@b.c', 'secret1')).rejects.toMatchObject({ code: 'exists' });
    await expect(c.signUp('x@b.c', '123')).rejects.toMatchObject({ code: 'weak' });
    await expect(c.signIn('a@b.c', 'wrong!!')).rejects.toMatchObject({ code: 'auth', message: '이메일이나 비밀번호가 맞지 않아요' });
    const t = await c.signIn('a@b.c', 'secret1');
    expect(t.email).toBe('a@b.c');
  });

  it('서버 설정이 없으면 준비 중으로 알린다', async () => {
    const none = new CloudClient({ url: '', key: '' }, srv.fetcher);
    expect(none.ready).toBe(false);
    await expect(none.signIn('a@b.c', 'secret1')).rejects.toMatchObject({ code: 'config' });
  });

  it('인터넷이 끊기면 network 오류', async () => {
    srv.setDown(true);
    await expect(c.signIn('a@b.c', 'secret1')).rejects.toMatchObject({ code: 'network', message: '인터넷 연결을 확인해 주세요' });
  });

  it('처음 올리기·조건부 올리기(다른 기기가 먼저 올리면 충돌)', async () => {
    const s = (await c.signUp('a@b.c', 'secret1')) as Exclude<Awaited<ReturnType<CloudClient['signUp']>>, 'confirm'>;
    expect(await c.fetchState(s)).toBeNull();
    expect(await c.createState(s, { v: 1 }, 'web')).toBe(1);
    expect(await c.createState(s, { v: 9 }, 'web')).toBeNull();
    expect(await c.updateState(s, { v: 2 }, 1, 'android')).toBe(2);
    expect(await c.updateState(s, { v: 3 }, 1, 'web')).toBeNull(); // 이미 2로 올라감
    const r = await c.fetchState(s);
    expect(r).toMatchObject({ state: { v: 2 }, rev: 2, device: 'android' });
    await c.deleteState(s);
    expect(await c.fetchState(s)).toBeNull();
  });

  it('로그인 연장(refresh)', async () => {
    const s = (await c.signUp('a@b.c', 'secret1')) as Exclude<Awaited<ReturnType<CloudClient['signUp']>>, 'confirm'>;
    const t = await c.refresh(s);
    expect(t.accessToken).not.toBe(s.accessToken);
    await expect(c.refresh(s)).rejects.toMatchObject({ code: 'auth' }); // 한 번 쓴 refresh 토큰
  });

  it('남의 기록은 읽지 못한다', async () => {
    const a = (await c.signUp('a@b.c', 'secret1')) as Exclude<Awaited<ReturnType<CloudClient['signUp']>>, 'confirm'>;
    const b = (await c.signUp('b@b.c', 'secret1')) as Exclude<Awaited<ReturnType<CloudClient['signUp']>>, 'confirm'>;
    await c.createState(a, { mine: 'a' }, 'web');
    expect(await c.fetchState({ ...b, userId: a.userId })).toBeNull();
  });
});

describe('동기화 판단', () => {
  const meta = (p: Partial<SyncMeta> = {}): SyncMeta => ({ userId: 'u1', rev: 0, dirty: false, syncedAt: null, ...p });
  const remote = (rev: number): RemoteState => ({ state: {}, rev, updatedAt: '', device: 'web' });

  it('서버에 없으면 올리고, 이 기기도 비어 있으면 아무것도 안 한다', () => {
    expect(planSync(meta(), null, true).kind).toBe('create');
    expect(planSync(meta(), null, false).kind).toBe('none');
  });
  it('처음 연결: 이 기기가 비어 있으면 받고, 둘 다 있으면 고르게 한다', () => {
    expect(planSync(meta(), remote(3), false)).toMatchObject({ kind: 'pull' });
    expect(planSync(meta(), remote(3), true)).toMatchObject({ kind: 'conflict', first: true });
  });
  it('같은 rev: 바뀐 게 있으면 올리고 없으면 그대로', () => {
    expect(planSync(meta({ rev: 3, dirty: true }), remote(3), true)).toEqual({ kind: 'push', baseRev: 3 });
    expect(planSync(meta({ rev: 3 }), remote(3), true).kind).toBe('none');
  });
  it('서버가 앞섬: 이 기기에 안 올린 변경이 없으면 받고, 있으면 충돌', () => {
    expect(planSync(meta({ rev: 3 }), remote(5), true)).toMatchObject({ kind: 'pull' });
    expect(planSync(meta({ rev: 3, dirty: true }), remote(5), true)).toMatchObject({ kind: 'conflict', first: false });
  });
});
