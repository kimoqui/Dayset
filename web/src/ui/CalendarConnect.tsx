import { useEffect, useRef, useState } from 'react';
import { checkIcs, clientIdOf, GOOGLE_ID, googleDue, STALE_MS, syncGoogle, SYNC_EVERY_MS } from '../app/calendarSync';
import { forgetToken, originAllowed } from '../app/gcal';
import { formatHm, koreanDate } from '../engine/models';
import type { AppState, CalendarSource } from '../app/state';
import { getState, now as clockNow, removeCalendar, setGoogleClientId } from '../app/store';
import { Icon, Sheet } from './kit';
import { haptic } from './motion';

type ToastFn = (text: string, undo?: boolean | 'plan') => void;

const ago = (d: Date, t: Date): string => {
  const m = Math.round((t.getTime() - d.getTime()) / 60000);
  if (m < 1) return '방금';
  if (m < 60) return `${m}분 전`;
  if (m < 24 * 60) return `${Math.round(m / 60)}시간 전`;
  return `${koreanDate(d)} ${formatHm(d)}`;
};

/** 캘린더 가져오기: 구글 연결, .ics 파일, 연결된 캘린더 관리. */
export function CalendarSheet({ s, onClose, toast }: { s: AppState; onClose: () => void; toast: ToastFn }) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);
  const [confirm, setConfirm] = useState<{ text: string; run: () => void } | null>(null);
  const [cid, setCid] = useState(s.googleClientId);
  const t = clockNow();
  const google = s.calendars.find((c) => c.id === GOOGLE_ID);
  const clientId = clientIdOf();
  const canGoogle = originAllowed();

  const connectGoogle = async () => {
    setBusy(true);
    setMsg(null);
    const r = await syncGoogle(true);
    setBusy(false);
    if (r.ok) {
      haptic(12);
      toast(r.text, 'plan');
      onClose();
    } else setMsg({ text: r.text, bad: true });
  };

  const onFile = async (f: File) => {
    setMsg(null);
    let text = '';
    try {
      text = await f.text();
    } catch {
      setMsg({ text: '파일을 열지 못했어요', bad: true });
      return;
    }
    const c = checkIcs(text, f.name, f.size);
    if (c.kind === 'error') setMsg({ text: c.text, bad: true });
    else if (c.kind === 'empty-replace')
      setConfirm({
        text: `${c.text} 전에 가져온 '${c.name}' 일정 ${c.previous}개를 지울까요?`,
        run: () => {
          removeCalendar(c.id);
          toast(`'${c.name}' 일정을 지웠어요`, 'plan');
          onClose();
        },
      });
    else {
      const r = c.run();
      haptic(12);
      toast(r.text, 'plan');
      onClose();
    }
  };

  const disconnect = (c: CalendarSource) =>
    setConfirm({
      text: `'${c.name}'에서 가져온 일정 ${c.count}개를 지우고 연결을 끊을까요?`,
      run: () => {
        if (c.id === GOOGLE_ID) forgetToken();
        removeCalendar(c.id);
        toast('연결을 끊고 남은 일정을 다시 짰어요', 'plan');
        setConfirm(null);
      },
    });

  return (
    <Sheet title="캘린더 가져오기" onClose={onClose}>
      <p className="t-label" style={{ margin: 0 }}>
        회의·수업·약속이 자동으로 들어오고, 기상 알람과 할 일 배치가 바로 바뀌어요. 앞으로 2주 일정만 가져와요.
      </p>

      {s.calendars.length > 0 && (
        <div className="card list" aria-label="연결된 캘린더" style={{ padding: '4px 14px' }}>
          {s.calendars.map((c) => {
            const stale = t.getTime() - c.lastSync.getTime() > STALE_MS;
            return (
              <div key={c.id} className="cal-src">
                <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
                  <span className="strong ellipsis">{c.name}</span>
                  <span className="t-label">
                    {c.kind === 'google' ? '구글 연결' : '.ics 파일'} · {c.count}개 · {ago(c.lastSync, t)} 가져옴
                  </span>
                  {c.error && <span className="t-label miss">{c.error}</span>}
                  {!c.error && stale && c.kind === 'google' && <span className="t-label miss">하루 넘게 못 가져왔어요. 지금 동기화를 눌러 주세요</span>}
                  {!c.error && stale && c.kind === 'ics' && <span className="t-label">파일은 자동으로 바뀌지 않아요. 일정이 바뀌면 새로 내보내 고르세요</span>}
                </span>
                <span className="col" style={{ gap: 6, alignItems: 'flex-end' }}>
                  {c.kind === 'google' ? (
                    <button type="button" className="btn small primary" disabled={busy || !clientId || !canGoogle} onClick={connectGoogle}>
                      {c.needsAuth ? '다시 연결' : '지금 동기화'}
                    </button>
                  ) : (
                    <button type="button" className="btn small" onClick={() => fileRef.current?.click()}>
                      새 파일
                    </button>
                  )}
                  <button type="button" className="btn small ghost" onClick={() => disconnect(c)}>
                    연결 끊기
                  </button>
                </span>
              </div>
            );
          })}
        </div>
      )}

      {confirm && (
        <div className="card tint stack" role="alertdialog" aria-label="확인">
          <span className="t-body">{confirm.text}</span>
          <div className="row" style={{ gap: 8 }}>
            <button type="button" className="btn danger grow" onClick={confirm.run}>
              지우기
            </button>
            <button type="button" className="btn grow" onClick={() => setConfirm(null)}>
              그대로 두기
            </button>
          </div>
        </div>
      )}

      {!google && (
        <section className="stack" aria-label="구글 캘린더">
          <button type="button" className="btn primary block" disabled={busy || !clientId || !canGoogle} onClick={connectGoogle}>
            <Icon name="calendar" size={18} /> {busy ? '구글 창에서 허용해 주세요…' : '구글 캘린더 연결'}
          </button>
          {!canGoogle && (
            <span className="t-label">
              이 화면은 파일로 열려 있어 구글 로그인이 막혀요. 배포 주소(https)나 개발 서버(localhost)에서 연결할 수 있어요. 지금은 아래 .ics 파일로 가져오세요.
            </span>
          )}
          {canGoogle && !clientId && <span className="t-label">구글 연결에는 클라이언트 ID가 필요해요. 아래 '개발자 설정'에 넣어 주세요.</span>}
          {canGoogle && clientId && <span className="t-label">읽기 전용으로만 연결해요. 이 화면이 열려 있는 동안 30분마다 다시 가져와요.</span>}
        </section>
      )}

      <section className="stack" aria-label=".ics 파일">
        <button type="button" className="btn block" onClick={() => fileRef.current?.click()}>
          .ics 파일 고르기
        </button>
        <span className="t-label">
          구글 캘린더: 설정 → 가져오기/내보내기 → 내보내기(압축을 풀면 .ics). 애플 캘린더(맥): 파일 → 내보내기. 같은 캘린더를 다시 고르면 통째로 바꿔요.
        </span>
        <input
          ref={fileRef}
          type="file"
          accept=".ics,text/calendar"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) void onFile(f);
            e.target.value = '';
          }}
        />
      </section>

      {msg && (
        <p className={`t-label ${msg.bad ? 'miss' : ''}`} role="alert" style={{ margin: 0 }}>
          {msg.text}
        </p>
      )}

      <details className="dev">
        <summary className="t-label">개발자 설정 · 구글 클라이언트 ID</summary>
        <div className="row" style={{ gap: 8, marginTop: 8 }}>
          <input className="input grow" value={cid} onChange={(e) => setCid(e.target.value)} placeholder="xxxx.apps.googleusercontent.com" aria-label="구글 클라이언트 ID" />
          <button
            type="button"
            className="btn small"
            onClick={() => {
              const v = cid.trim();
              if (v && !/\.apps\.googleusercontent\.com$/.test(v)) {
                setMsg({ text: "클라이언트 ID는 '.apps.googleusercontent.com'으로 끝나요", bad: true });
                return;
              }
              setGoogleClientId(v);
              setMsg({ text: v ? '저장했어요' : '지웠어요' });
            }}
          >
            저장
          </button>
        </div>
      </details>
    </Sheet>
  );
}

/** 구글 캘린더 자동 동기화: 화면이 열릴 때, 다시 보일 때, 인터넷이 돌아올 때, 30분마다. */
export function useCalendarAutoSync(enabled: boolean, toast: ToastFn): void {
  const running = useRef(false);
  useEffect(() => {
    if (!enabled) return;
    const run = async (reason: 'open' | 'tick' | 'online') => {
      if (running.current || !getState().calendars.some((c) => c.id === GOOGLE_ID)) return;
      if (reason !== 'online' && !googleDue()) return;
      running.current = true;
      try {
        const r = await syncGoogle(false);
        // 조용히 동기화하고, 일정이 실제로 바뀌었을 때만 알린다.
        if (r.ok && r.outcome?.replanned) toast(r.text, 'plan');
      } finally {
        running.current = false;
      }
    };
    void run('open');
    const timer = window.setInterval(() => void run('tick'), SYNC_EVERY_MS);
    const onVis = () => document.visibilityState === 'visible' && void run('tick');
    const onOnline = () => void run('online');
    document.addEventListener('visibilitychange', onVis);
    window.addEventListener('online', onOnline);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVis);
      window.removeEventListener('online', onOnline);
    };
  }, [enabled, toast]);
}
