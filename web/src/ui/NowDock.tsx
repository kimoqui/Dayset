// 일정 체크 팝업: 화면 아래(탭 위)에 늘 떠 있다.
// 일정이 시작됐는데 기록이 없으면 크게 펼쳐 '시작했어요'를 묻고, 기록 중이면 작은 띠로 지금·다음 일정을 보여 준다.

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { checkKey, expectedActivity, type NowCheck } from '../app/nowCheck';
import { objectParticle } from '../engine/coaching';
import { type Activity, ACTIVITY_LABEL, formatDuration, formatHm } from '../engine/models';
import { Icon } from './kit';

const LABEL_SHORT: Record<Activity, string> = { sleep: '수면', meal: '식사', work: '업무', exercise: '운동', rest: '휴식' };

export function NowDock({
  check,
  onRecord,
  onSkip,
}: {
  check: NowCheck;
  /** at: 제때 누르지 못했을 때 실제로 시작한(끝난) 시각. 없으면 지금. */
  onRecord: (a: Activity, via: 'popup', at?: Date) => void;
  onSkip: (id: string) => void;
}) {
  const key = checkKey(check);
  const alert = (check.kind === 'due' || check.kind === 'over') && !check.skipped;
  const [min, setMin] = useState(!alert);
  // 늦게 눌렀을 때 고르는 시각: 'now' | 'plan' | 직접 고른 분(0~1439)
  const [when, setWhen] = useState<'now' | 'plan' | number>('plan');
  const ref = useRef<HTMLDivElement>(null);

  // 새로 기록할 일이 생기면 다시 펼친다.
  useEffect(() => {
    setMin(!alert);
    setWhen('plan');
  }, [key, alert]);

  // 팝업 높이를 알려 토스트·화면 아래 여백이 가리지 않게 한다.
  useLayoutEffect(() => {
    const el = ref.current;
    const set = () => document.documentElement.style.setProperty('--dock-h', `${el ? el.offsetHeight : 0}px`);
    set();
    if (!el || typeof ResizeObserver === 'undefined') return () => document.documentElement.style.setProperty('--dock-h', '0px');
    const ro = new ResizeObserver(set);
    ro.observe(el);
    return () => {
      ro.disconnect();
      document.documentElement.style.setProperty('--dock-h', '0px');
    };
  }, [min, alert, check.kind]);

  if (check.kind === 'none') return null;
  const b = check.block;
  const next = check.next;
  const cur = check.current ? `${ACTIVITY_LABEL[check.current]} ${formatDuration(check.currentMinutes)}째` : '기록 없음';

  // 작은 띠
  if (min || !alert) {
    let text: string;
    let tone = '';
    if (check.kind === 'ok' && b) text = `지금 ${b.title} · ${formatHm(b.end)}까지`;
    else if (check.kind === 'next' && next) text = `다음 ${formatHm(next.start)} ${next.title} · ${formatDuration(check.minutes)} 뒤`;
    else if (check.kind === 'next') text = '오늘 남은 일정이 없어요';
    else if (check.kind === 'due' && b) {
      text = `${b.title} · ${check.skipped ? '이번엔 건너뜀' : '기록 전'}`;
      tone = check.skipped ? '' : 'warn';
    } else if (check.kind === 'over' && b) {
      text = `${b.title} 끝날 시간이 지났어요`;
      tone = check.skipped ? '' : 'warn';
    } else text = '';
    return (
      <div ref={ref} className={`now-dock slim ${tone}`} role="status" aria-label="일정 체크">
        <span className={`dock-dot ${check.kind}`} />
        <span className="grow ellipsis">{text}</span>
        {(check.kind === 'due' || check.kind === 'over') && check.expected && (
          <button type="button" className="dock-mini" onClick={() => onRecord(check.kind === 'over' ? 'rest' : check.expected!, 'popup')}>
            {check.kind === 'over' ? '끝났어요' : '기록하기'}
          </button>
        )}
        {alert && (
          <button type="button" className="icon-btn" aria-label="펼치기" onClick={() => setMin(false)} style={{ width: 32, height: 32 }}>
            <Icon name="back" size={16} />
          </button>
        )}
      </div>
    );
  }

  // 펼친 팝업: 기록하라는 알림
  const exp = check.expected!;
  const isOver = check.kind === 'over';
  // 일정 시각에서 5분 넘게 지났으면 '언제 시작(끝)했는지'를 고르게 한다.
  const planAt = isOver ? b!.end : b!.start;
  const nowAt = new Date(planAt.getTime() + check.minutes * 60_000);
  const late = check.minutes >= 5;
  const pickAt = (): Date | undefined => {
    if (!late || when === 'now') return undefined;
    if (when === 'plan') return planAt;
    const d = new Date(nowAt.getFullYear(), nowAt.getMonth(), nowAt.getDate(), Math.floor(when / 60), when % 60);
    return d.getTime() > nowAt.getTime() ? new Date(d.getTime() - 86_400_000) : d;
  };
  const hm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  const whenRow = late && (
    <div className="dock-when" role="group" aria-label={isOver ? '끝난 시각' : '시작한 시각'}>
      <span className="t-label">{isOver ? '끝난 시각' : '시작한 시각'}</span>
      <button type="button" className="chip" aria-checked={when === 'plan'} role="radio" onClick={() => setWhen('plan')}>
        일정대로 {formatHm(planAt)}
      </button>
      <button type="button" className="chip" aria-checked={when === 'now'} role="radio" onClick={() => setWhen('now')}>
        지금 {formatHm(nowAt)}
      </button>
      <input
        type="time"
        aria-label="다른 시각"
        className={typeof when === 'number' ? 'on' : ''}
        value={typeof when === 'number' ? hm(when) : ''}
        onChange={(e) => {
          const [h, m] = e.target.value.split(':').map(Number);
          if (Number.isFinite(h) && Number.isFinite(m)) setWhen(h * 60 + m);
        }}
      />
    </div>
  );
  return (
    <div ref={ref} className="now-dock open" role="alertdialog" aria-label="일정 체크">
      <div className="row between">
        <span className="dock-tag">
          <span className="dock-dot due" /> {isOver ? '끝났는지 확인' : '지금 일정'}
        </span>
        <button type="button" className="icon-btn" aria-label="작게 보기" onClick={() => setMin(true)} style={{ width: 32, height: 32, marginRight: -6 }}>
          <Icon name="close" size={16} />
        </button>
      </div>
      <strong className="dock-title">{isOver ? `${b!.title} 끝났어요?` : `${formatHm(b!.start)} ${b!.title} 시간이에요`}</strong>
      <span className="t-label">
        {isOver
          ? `${formatHm(b!.end)}에 끝나는 일정이었어요 · 지금 기록: ${cur}`
          : `지금 기록: ${cur} · ${LABEL_SHORT[exp]}${objectParticle(LABEL_SHORT[exp])} 시작했으면 눌러 주세요`}
      </span>
      {whenRow}
      <div className="row" style={{ gap: 8 }}>
        {isOver ? (
          <>
            <button type="button" className="btn primary grow" onClick={() => onRecord('rest', 'popup', pickAt())}>
              끝났어요 · 휴식
            </button>
            {next && expectedActivity(next) && expectedActivity(next) !== exp && (
              <button type="button" className="btn grow" onClick={() => onRecord(expectedActivity(next)!, 'popup', pickAt())}>
                {next ? `${LABEL_SHORT[expectedActivity(next)!]} 시작` : ''}
              </button>
            )}
            <button type="button" className="btn" onClick={() => onSkip(`${b!.id}:over`)}>
              아직이에요
            </button>
          </>
        ) : (
          <>
            <button type="button" className="btn primary grow" onClick={() => onRecord(exp, 'popup', pickAt())}>
              {LABEL_SHORT[exp]} 시작했어요
            </button>
            <button type="button" className="btn" onClick={() => onSkip(b!.id)}>
              지금은 안 해요
            </button>
          </>
        )}
      </div>
    </div>
  );
}
