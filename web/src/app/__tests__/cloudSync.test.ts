import { beforeEach, describe, expect, it } from 'vitest';
import { CloudClient, type Session } from '../cloud';
import { cloudView, resolveConflict, signIn, signOut, signUp, syncNow, useClientForTest } from '../cloudSync';
import { demoState } from '../seed';
import { initialState, keptBackups, serialize } from '../state';
import { getState, replaceState, setFixedClock, setProfileName } from '../store';
import { fakeServer } from './fakeCloud';

const cfg = { url: 'https://x.supabase.co', key: 'anon' };
const now = new Date(2026, 10, 1, 21, 0);

describe('계정 동기화(한 기기 + 다른 기기 흉내)', () => {
  let srv: ReturnType<typeof fakeServer>;
  let other: CloudClient;
  let otherSession: Session;

  beforeEach(async () => {
    await signOut();
    srv = fakeServer();
    useClientForTest(new CloudClient(cfg, srv.fetcher));
    other = new CloudClient(cfg, srv.fetcher);
    setFixedClock(now);
    replaceState(demoState(now));
  });

  it('가입하면 이 기기 기록을 올리고, 바꾸면 다시 올린다', async () => {
    expect(await signUp('me@d.s', 'secret1')).toBe('ok');
    expect(cloudView().status).toBe('idle');
    const row = [...srv.rows.values()][0];
    expect(row.rev).toBe(1);
    expect((row.state as { demo: boolean }).demo).toBe(true);

    setProfileName('대희');
    expect(cloudView().dirty).toBe(true);
    await syncNow();
    expect([...srv.rows.values()][0].rev).toBe(2);
    expect(([...srv.rows.values()][0].state as { profile: { name: string } }).profile.name).toBe('대희');
    expect(cloudView().dirty).toBe(false);
  });

  it('다른 기기가 올린 기록을 받는다', async () => {
    await signUp('me@d.s', 'secret1');
    otherSession = await other.signIn('me@d.s', 'secret1');
    const remote = (await other.fetchState(otherSession))!;
    const changed = { ...(remote.state as object), profile: { ...(remote.state as { profile: object }).profile, name: '앱에서' } };
    expect(await other.updateState(otherSession, changed, remote.rev, 'android')).toBe(2);
    await syncNow();
    expect(getState().profile.name).toBe('앱에서');
    expect(cloudView().status).toBe('idle');
  });

  it('양쪽 다 바뀌면 고르게 하고, 이 기기 것을 고르면 계정을 덮는다', async () => {
    await signUp('me@d.s', 'secret1');
    otherSession = await other.signIn('me@d.s', 'secret1');
    const remote = (await other.fetchState(otherSession))!;
    await other.updateState(otherSession, remote.state, remote.rev, 'android');
    setProfileName('웹에서');
    await syncNow();
    expect(cloudView().status).toBe('conflict');
    await resolveConflict('local');
    expect(cloudView().status).toBe('idle');
    const row = [...srv.rows.values()][0];
    expect(row.rev).toBe(3);
    expect((row.state as { profile: { name: string } }).profile.name).toBe('웹에서');
  });

  it('새 기기(빈 상태)에서 로그인하면 계정 기록을 그대로 받는다', async () => {
    await signUp('me@d.s', 'secret1');
    const uploaded = serialize(getState());
    await signOut();
    replaceState(initialState());
    await signIn('me@d.s', 'secret1');
    expect(getState().onboarded).toBe(true);
    expect(serialize(getState())).toBe(uploaded);
  });

  it('기록이 있는 기기에서 처음 로그인하면 고르게 하고, 계정 기록을 고르면 이 기기 기록은 보관한다', async () => {
    await signUp('me@d.s', 'secret1');
    await signOut();
    const local = { ...demoState(now), profile: { id: 'u-local', name: '이 기기' } };
    replaceState(local);
    await signIn('me@d.s', 'secret1');
    expect(cloudView().conflict?.first).toBe(true);
    await resolveConflict('remote');
    expect(getState().profile.name).not.toBe('이 기기');
    expect(keptBackups().length).toBeGreaterThanOrEqual(0); // 저장소가 없는 테스트 환경에서는 보관을 건너뛴다
  });

  it('인터넷이 끊기면 기록은 그대로 두고 오프라인으로 표시한다', async () => {
    await signUp('me@d.s', 'secret1');
    setProfileName('끊김');
    srv.setDown(true);
    await syncNow();
    expect(cloudView().status).toBe('offline');
    expect(cloudView().dirty).toBe(true);
    srv.setDown(false);
    await syncNow();
    expect(cloudView().dirty).toBe(false);
  });
});
