import { useEffect } from 'react';
import { addDays, dateKey, formatDuration, formatHm, diffMin } from '../engine/models';
import { planFor } from '../app/derive';
import { dismissBed, dismissWake, getState, now, type Ring, snooze } from '../app/store';

/** 알람 소리: 짧은 삐 소리를 반복한다. 브라우저는 화면을 한 번 누른 뒤에만 소리를 허용한다. */
function startSound(): () => void {
  let ctx: AudioContext | null = null;
  let timer: number | undefined;
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    ctx = new AC();
    const beep = () => {
      if (!ctx) return;
      const t = ctx.currentTime;
      for (let i = 0; i < 3; i++) {
        const o = ctx.createOscillator();
        const g = ctx.createGain();
        o.frequency.value = 880;
        g.gain.setValueAtTime(0.0001, t + i * 0.25);
        g.gain.exponentialRampToValueAtTime(0.25, t + i * 0.25 + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.25 + 0.18);
        o.connect(g).connect(ctx.destination);
        o.start(t + i * 0.25);
        o.stop(t + i * 0.25 + 0.2);
      }
      try {
        navigator.vibrate?.([200, 100, 200]);
      } catch {
        // 진동을 지원하지 않는 기기
      }
    };
    void ctx.resume().catch(() => undefined);
    beep();
    timer = window.setInterval(beep, 1500);
  } catch {
    // 소리를 낼 수 없는 환경
  }
  return () => {
    if (timer) window.clearInterval(timer);
    void ctx?.close().catch(() => undefined);
  };
}

export function AlarmOverlay({ ring, onDone, test }: { ring: Ring; onDone: () => void; test?: boolean }) {
  useEffect(() => startSound(), []);
  const t = now();
  const s = getState();
  const snoozes = s.alarms[ring.key]?.snoozes ?? 0;

  if (ring.kind === 'wake') {
    const plan = planFor(s, dateKey(t), t);
    return (
      <div className="ring" role="alertdialog" aria-label="기상 알람">
        <div className="col" style={{ alignItems: 'center', gap: 10 }}>
          <span style={{ opacity: 0.8, fontWeight: 600 }}>{test ? '알람 미리 듣기' : '기상 알람'}</span>
          <span className="big">{formatHm(t)}</span>
          <span style={{ opacity: 0.85 }}>{plan.alarms[0].reason}</span>
          {snoozes > 0 && <span style={{ opacity: 0.7, fontSize: 13 }}>{snoozes}번 미뤘어요</span>}
        </div>
        <div className="col" style={{ width: '100%', gap: 12 }}>
          <button
            type="button"
            className="btn primary block"
            onClick={() => {
              if (!test) dismissWake(ring);
              onDone();
            }}
          >
            알람 끄기 · 기상 기록
          </button>
          <button
            type="button"
            className="btn line block"
            onClick={() => {
              if (!test) snooze(ring, 5);
              onDone();
            }}
          >
            5분 뒤 다시
          </button>
        </div>
      </div>
    );
  }

  const tomorrow = planFor(s, dateKey(addDays(t, 1)), t);
  return (
    <div className="ring" role="alertdialog" aria-label="취침 알림" style={{ background: '#111829' }}>
      <div className="col" style={{ alignItems: 'center', gap: 10 }}>
        <span style={{ opacity: 0.8, fontWeight: 600 }}>취침 시간이에요</span>
        <span className="big">{formatHm(t)}</span>
        <span style={{ opacity: 0.85 }}>
          내일 {formatHm(tomorrow.wake)} 기상까지 {formatDuration(Math.max(0, diffMin(tomorrow.wake, t)))}
        </span>
      </div>
      <div className="col" style={{ width: '100%', gap: 12 }}>
        <button
          type="button"
          className="btn primary block"
          onClick={() => {
            dismissBed(ring, true);
            onDone();
          }}
        >
          잘게요 · 수면 기록
        </button>
        <button
          type="button"
          className="btn line block"
          onClick={() => {
            snooze(ring, 30);
            onDone();
          }}
        >
          30분 뒤 다시
        </button>
        <button
          type="button"
          className="btn line block"
          style={{ borderColor: 'transparent' }}
          onClick={() => {
            dismissBed(ring, false);
            onDone();
          }}
        >
          오늘은 끄기
        </button>
      </div>
    </div>
  );
}
