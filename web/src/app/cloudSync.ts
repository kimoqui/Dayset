// 계정 동기화 실행: 로그인 상태를 기억하고, 기록이 바뀌면 잠시 뒤 올리고, 앱을 열면 받는다.
// 무엇을 할지는 cloud.ts의 planSync가 정한다. 버리는 쪽 기록은 지우지 않고 보관한다(설정 → 데이터).

import { CloudClient, CloudError, errorText, planSync, type RemoteState, type Session, type SyncMeta } from './cloud';
import { CLOUD_KEY, CLOUD_URL } from './cloudConfig';
import { deserialize, keepCopy, serialize, type AppState } from './state';
import { getState, replaceState, subscribe } from './store';

const AUTH_KEY = 'dayset:auth';
const META_KEY = 'dayset:cloud';
const PUSH_DELAY = 4000;

export type CloudStatus = 'off' | 'idle' | 'syncing' | 'offline' | 'error' | 'conflict';

export interface CloudView {
  ready: boolean;
  session: Session | null;
  status: CloudStatus;
  message: string | null;
  syncedAt: number | null;
  dirty: boolean;
  conflict: { remote: RemoteState; first: boolean } | null;
}

let client = new CloudClient({ url: CLOUD_URL, key: CLOUD_KEY });

function read<T>(key: string): T | null {
  try {
    const t = localStorage.getItem(key);
    return t ? (JSON.parse(t) as T) : null;
  } catch {
    return null;
  }
}
function write(key: string, v: unknown): void {
  try {
    if (v == null) localStorage.removeItem(key);
    else localStorage.setItem(key, JSON.stringify(v));
  } catch {
    // 저장소를 못 쓰면 이번 실행 동안만 기억한다.
  }
}

let session: Session | null = read<Session>(AUTH_KEY);
let meta: SyncMeta = (() => {
  const m = read<SyncMeta>(META_KEY);
  return m && session && m.userId === session.userId ? m : { userId: session?.userId ?? '', rev: 0, dirty: false, syncedAt: null };
})();
let view: CloudView = {
  ready: client.ready,
  session,
  status: session ? 'idle' : 'off',
  message: null,
  syncedAt: meta.syncedAt,
  dirty: meta.dirty,
  conflict: null,
};
const listeners = new Set<() => void>();

function emit(patch: Partial<CloudView>): void {
  view = { ...view, ...patch, session, syncedAt: meta.syncedAt, dirty: meta.dirty };
  for (const l of listeners) l();
}

export function cloudView(): CloudView {
  return view;
}
export function subscribeCloud(l: () => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

function saveMeta(m: Partial<SyncMeta>): void {
  meta = { ...meta, ...m };
  write(META_KEY, meta);
}

function setSession(s: Session | null): void {
  session = s;
  write(AUTH_KEY, s);
  if (s && meta.userId !== s.userId) saveMeta({ userId: s.userId, rev: 0, dirty: false, syncedAt: null });
  if (!s) write(META_KEY, null);
}

/** 테스트용: 서버 클라이언트를 바꾼다. */
export function useClientForTest(c: CloudClient): void {
  client = c;
  view = { ...view, ready: c.ready };
}

const device = (): string => {
  try {
    return /Android/i.test(navigator.userAgent) ? 'web-android' : /iPhone|iPad/i.test(navigator.userAgent) ? 'web-ios' : 'web';
  } catch {
    return 'web';
  }
};

const toJson = (s: AppState): unknown => JSON.parse(serialize(s));

let applying = false;
function applyRemote(remote: RemoteState, keepLocal: boolean): void {
  const next = deserialize(JSON.stringify(remote.state));
  if (keepLocal) keepCopy(serialize(getState()), 'before-import');
  applying = true;
  try {
    replaceState(next);
  } finally {
    applying = false;
  }
  saveMeta({ rev: remote.rev, dirty: false, syncedAt: Date.now() });
}

// 기록이 바뀌면 '안 올린 변경'으로 표시하고 잠시 뒤 올린다.
let timer: ReturnType<typeof setTimeout> | undefined;
subscribe(() => {
  if (applying || !session) return;
  if (!meta.dirty) saveMeta({ dirty: true });
  emit({});
  clearTimeout(timer);
  timer = setTimeout(() => void syncNow(), PUSH_DELAY);
});

async function fresh(): Promise<Session> {
  if (!session) throw new CloudError('auth', '로그인이 필요해요');
  if (session.expiresAt - Date.now() > 60_000) return session;
  try {
    const s = await client.refresh(session);
    setSession(s);
    return s;
  } catch (e) {
    if (e instanceof CloudError && e.code === 'auth') {
      // 로그인이 만료됐다: 이 기기 기록은 그대로 두고 다시 로그인하게 한다.
      setSession(null);
      emit({ status: 'off', message: '로그인이 만료됐어요. 다시 로그인해 주세요' });
    }
    throw e;
  }
}

let running: Promise<void> | null = null;

/** 지금 맞춘다(이미 맞추는 중이면 그 결과를 기다린다). */
export function syncNow(): Promise<void> {
  if (!session || !client.ready) return Promise.resolve();
  if (running) return running;
  running = (async () => {
    emit({ status: 'syncing', message: null });
    try {
      for (let round = 0; round < 2; round++) {
        const s = await fresh();
        const remote = await client.fetchState(s);
        const plan = planSync(meta, remote, getState().onboarded);
        if (plan.kind === 'none') {
          saveMeta({ syncedAt: Date.now() });
        } else if (plan.kind === 'create') {
          const rev = await client.createState(s, toJson(getState()), device());
          if (rev == null) continue; // 그사이 다른 기기가 먼저 만들었다: 다시 본다.
          saveMeta({ rev, dirty: false, syncedAt: Date.now() });
        } else if (plan.kind === 'push') {
          const rev = await client.updateState(s, toJson(getState()), plan.baseRev, device());
          if (rev == null) continue; // 다른 기기가 먼저 올렸다: 다시 본다.
          saveMeta({ rev, dirty: false, syncedAt: Date.now() });
        } else if (plan.kind === 'pull') {
          applyRemote(plan.remote, false);
        } else {
          emit({ status: 'conflict', conflict: { remote: plan.remote, first: plan.first } });
          return;
        }
        emit({ status: 'idle', conflict: null });
        return;
      }
      emit({ status: 'idle' });
    } catch (e) {
      const offline = e instanceof CloudError && e.code === 'network';
      if (session) emit({ status: offline ? 'offline' : 'error', message: errorText(e) });
    } finally {
      running = null;
    }
  })();
  return running;
}

/** 충돌 해결: 'remote' = 계정 기록 쓰기(이 기기 기록은 보관), 'local' = 이 기기 기록으로 계정을 덮기. */
export async function resolveConflict(choice: 'remote' | 'local'): Promise<void> {
  const c = view.conflict;
  if (!c || !session) return;
  try {
    if (choice === 'remote') {
      applyRemote(c.remote, true);
    } else {
      const s = await fresh();
      const rev = await client.updateState(s, toJson(getState()), c.remote.rev, device());
      if (rev == null) {
        emit({ conflict: null });
        await syncNow();
        return;
      }
      saveMeta({ rev, dirty: false, syncedAt: Date.now() });
    }
    emit({ status: 'idle', conflict: null, message: null });
  } catch (e) {
    emit({ status: 'error', message: errorText(e) });
  }
}

export async function signIn(email: string, password: string): Promise<void> {
  const s = await client.signIn(email, password);
  setSession(s);
  emit({ status: 'idle', message: null });
  await syncNow();
}

/** 가입. 메일 확인이 필요한 서버면 'confirm'. */
export async function signUp(email: string, password: string): Promise<'ok' | 'confirm'> {
  const r = await client.signUp(email, password);
  if (r === 'confirm') return 'confirm';
  setSession(r);
  emit({ status: 'idle', message: null });
  await syncNow();
  return 'ok';
}

/** 로그아웃. 이 기기 기록은 그대로 둔다. */
export async function signOut(): Promise<void> {
  const s = session;
  setSession(null);
  saveMeta({ userId: '', rev: 0, dirty: false, syncedAt: null });
  write(META_KEY, null);
  emit({ status: 'off', message: null, conflict: null });
  if (s) await client.signOut(s);
}

export async function resetPassword(email: string): Promise<void> {
  await client.resetPassword(email);
}

/** 서버에 저장된 기록을 지운다(이 기기 기록은 그대로). 다음 동기화 때 이 기기 기록을 새로 올린다. */
export async function deleteRemote(): Promise<void> {
  const s = await fresh();
  await client.deleteState(s);
  saveMeta({ rev: 0, dirty: true, syncedAt: null });
  emit({ status: 'idle' });
}

/** 충돌 창에 보여 줄 요약(기록 수, 마지막 기록 날). */
export function summarize(raw: unknown): { logs: number; tasks: number; lastLog: Date | null; onboarded: boolean } | null {
  try {
    const s = deserialize(JSON.stringify(raw));
    const last = s.logs.length ? s.logs[s.logs.length - 1].start : null;
    return { logs: s.logs.length, tasks: s.tasks.length, lastLog: last, onboarded: s.onboarded };
  } catch {
    return null;
  }
}
