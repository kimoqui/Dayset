// 계정: 로그인·가입 창, 설정의 계정 카드, 기록이 엇갈렸을 때 고르는 창, 자동 동기화.

import { useEffect, useState, useSyncExternalStore } from 'react';
import { errorText } from '../app/cloud';
import { cloudView, resetPassword, resolveConflict, signIn, signOut, signUp, subscribeCloud, summarize, syncNow, deleteRemote } from '../app/cloudSync';
import { formatHm, koreanDate } from '../engine/models';
import { Icon, Sheet } from './kit';
import { haptic } from './motion';


export function useCloud() {
  return useSyncExternalStore(subscribeCloud, cloudView);
}

/** 앱을 열 때·다시 볼 때·인터넷이 돌아올 때·2분마다 맞춘다. */
export function useCloudAutoSync(): void {
  useEffect(() => {
    void syncNow();
    const onVis = () => document.visibilityState === 'visible' && void syncNow();
    const onOnline = () => void syncNow();
    document.addEventListener('visibilitychange', onVis);
    window.addEventListener('online', onOnline);
    const id = window.setInterval(() => document.visibilityState === 'visible' && void syncNow(), 120_000);
    return () => {
      document.removeEventListener('visibilitychange', onVis);
      window.removeEventListener('online', onOnline);
      window.clearInterval(id);
    };
  }, []);
}

const ago = (t: number | null): string => {
  if (!t) return '아직 맞추지 않음';
  const m = Math.round((Date.now() - t) / 60000);
  return m < 1 ? '방금 맞춤' : m < 60 ? `${m}분 전에 맞춤` : `${koreanDate(new Date(t))} ${formatHm(new Date(t))}에 맞춤`;
};

/** 로그인·가입 창. */
export function AccountSheet({ onClose, toast, initial = 'in' }: { onClose: () => void; toast: (t: string) => void; initial?: 'in' | 'up' }) {
  const v = useCloud();
  const [mode, setMode] = useState<'in' | 'up'>(initial);
  const [email, setEmail] = useState('');
  const [pw, setPw] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const valid = /^\S+@\S+\.\S+$/.test(email.trim()) && pw.length >= 6;

  const submit = async () => {
    if (!valid || busy) return;
    setBusy(true);
    setMsg(null);
    try {
      if (mode === 'in') {
        await signIn(email, pw);
        toast('로그인했어요. 기록을 계정과 맞췄어요');
        onClose();
      } else {
        const r = await signUp(email, pw);
        if (r === 'confirm') setMsg('메일함에서 가입 확인 링크를 누른 뒤 로그인해 주세요');
        else {
          toast('계정을 만들었어요. 이 기기 기록을 계정에 올렸어요');
          onClose();
        }
      }
      haptic(12);
    } catch (e) {
      setMsg(errorText(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title={mode === 'in' ? '로그인' : '계정 만들기'} onClose={onClose}>
      {!v.ready && <div className="banner">계정 서버를 준비하고 있어요. 준비되면 여기서 로그인할 수 있어요.</div>}
      <span className="t-label">계정에 기록을 두면 웹과 안드로이드 앱, 다른 휴대폰에서 같은 기록을 이어서 써요.</span>
      <label className="field">
        <span>이메일</span>
        <input className="input" type="email" autoComplete="email" inputMode="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com" />
      </label>
      <label className="field">
        <span>비밀번호 (6자 이상)</span>
        <input
          className="input"
          type="password"
          autoComplete={mode === 'in' ? 'current-password' : 'new-password'}
          value={pw}
          onChange={(e) => setPw(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && void submit()}
        />
      </label>
      {msg && (
        <span className="t-label miss" role="alert">
          {msg}
        </span>
      )}
      <button type="button" className="btn primary block" disabled={!valid || busy || !v.ready} onClick={() => void submit()}>
        {busy ? '잠시만요…' : mode === 'in' ? '로그인' : '계정 만들기'}
      </button>
      <div className="row between">
        <button type="button" className="btn ghost small" onClick={() => (setMode(mode === 'in' ? 'up' : 'in'), setMsg(null))}>
          {mode === 'in' ? '처음이에요 · 계정 만들기' : '이미 계정이 있어요 · 로그인'}
        </button>
        {mode === 'in' && (
          <button
            type="button"
            className="btn ghost small"
            disabled={!/^\S+@\S+\.\S+$/.test(email.trim()) || !v.ready}
            onClick={async () => {
              try {
                await resetPassword(email);
                setMsg('비밀번호를 바꾸는 메일을 보냈어요. 메일함을 확인해 주세요');
              } catch (e) {
                setMsg(errorText(e));
              }
            }}
          >
            비밀번호 찾기
          </button>
        )}
      </div>
    </Sheet>
  );
}

/** 설정의 계정 카드. */
export function AccountCard({ toast }: { toast: (t: string) => void }) {
  const v = useCloud();
  const [open, setOpen] = useState<'in' | 'up' | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const statusText =
    v.status === 'syncing'
      ? '맞추는 중…'
      : v.status === 'offline'
        ? '인터넷이 끊겨 기다리는 중 · 기록은 이 기기에 저장돼요'
        : v.status === 'error'
          ? (v.message ?? '맞추지 못했어요')
          : v.status === 'conflict'
            ? '기록이 엇갈렸어요 · 고르기를 기다려요'
            : `${ago(v.syncedAt)}${v.dirty ? ' · 올릴 변경 있음' : ''}`;
  return (
    <section className="card" aria-label="계정">
      <div className="row between">
        <div className="col" style={{ gap: 2, minWidth: 0 }}>
          <span className="t-h2">계정</span>
          <span className="t-label ellipsis">{v.session ? v.session.email : '웹·앱·다른 휴대폰에서 같은 기록을 이어 써요'}</span>
        </div>
        {!v.session ? (
          <button type="button" className="btn primary small" onClick={() => setOpen('in')}>
            로그인
          </button>
        ) : (
          <button type="button" className="btn small" disabled={v.status === 'syncing'} onClick={() => void syncNow().then(() => toast('계정과 맞췄어요'))}>
            <Icon name="refresh" size={16} /> 지금 맞추기
          </button>
        )}
      </div>
      {v.session ? (
        <>
          <span className={`t-label ${v.status === 'error' ? 'miss' : ''}`} aria-live="polite">
            {statusText}
          </span>
          <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
            <button
              type="button"
              className="btn small"
              onClick={async () => {
                await signOut();
                toast('로그아웃했어요. 이 기기 기록은 그대로 있어요');
              }}
            >
              로그아웃
            </button>
            {!confirmDelete ? (
              <button type="button" className="btn small danger" onClick={() => setConfirmDelete(true)}>
                계정에 저장된 기록 지우기
              </button>
            ) : (
              <button
                type="button"
                className="btn small danger"
                onClick={async () => {
                  try {
                    await deleteRemote();
                    toast('계정에 저장된 기록을 지웠어요. 이 기기 기록은 그대로 있어요');
                  } catch (e) {
                    toast(errorText(e));
                  }
                  setConfirmDelete(false);
                }}
              >
                정말 지우기
              </button>
            )}
          </div>
        </>
      ) : (
        v.message && <span className="t-label miss">{v.message}</span>
      )}
      {open && <AccountSheet initial={open} onClose={() => setOpen(null)} toast={toast} />}
    </section>
  );
}

/** 기록이 엇갈렸을 때(처음 로그인했는데 양쪽에 기록이 있음, 또는 두 기기에서 동시에 바뀜) 고르는 창. */
export function ConflictSheet({ toast }: { toast: (t: string) => void }) {
  const v = useCloud();
  const [busy, setBusy] = useState(false);
  if (!v.conflict) return null;
  const remote = summarize(v.conflict.remote.state);
  const when = v.conflict.remote.updatedAt ? new Date(v.conflict.remote.updatedAt) : null;
  const pick = async (c: 'remote' | 'local') => {
    setBusy(true);
    await resolveConflict(c);
    setBusy(false);
    toast(c === 'remote' ? '계정 기록으로 바꿨어요. 이 기기 기록은 설정 → 데이터에 보관했어요' : '이 기기 기록을 계정에 올렸어요');
  };
  return (
    <Sheet title={v.conflict.first ? '어느 기록으로 이어 쓸까요?' : '기록이 엇갈렸어요'} onClose={() => undefined}>
      <span className="t-body">
        {v.conflict.first
          ? '이 기기와 계정에 모두 기록이 있어요. 하나를 골라 주세요.'
          : '다른 기기에서 바뀐 기록과 이 기기에서 바뀐 기록이 둘 다 있어요. 하나를 골라 주세요.'}
      </span>
      <div className="card">
        <span className="t-h2">계정에 저장된 기록</span>
        <span className="t-label">
          {remote ? `기록 ${remote.logs}개 · 할 일 ${remote.tasks}개${remote.lastLog ? ` · 마지막 기록 ${koreanDate(remote.lastLog)}` : ''}` : '읽지 못한 기록'}
          {when ? ` · ${koreanDate(when)} ${formatHm(when)} 저장` : ''}
          {v.conflict.remote.device ? ` (${v.conflict.remote.device === 'android' ? '안드로이드 앱' : '웹'})` : ''}
        </span>
        <button type="button" className="btn primary block" disabled={busy || !remote} onClick={() => void pick('remote')}>
          계정 기록 쓰기
        </button>
      </div>
      <div className="card">
        <span className="t-h2">이 기기 기록</span>
        <button type="button" className="btn block" disabled={busy} onClick={() => void pick('local')}>
          이 기기 기록으로 계정 덮기
        </button>
      </div>
      <span className="t-label">고르지 않은 쪽은 지우지 않아요. 계정 기록을 고르면 이 기기 기록은 설정 → 데이터에 보관해요.</span>
    </Sheet>
  );
}
