import { useMemo, useState } from 'react';
import { rateOf } from '../../engine/achievement';
import { weekTarget } from '../../engine/correction';
import {
  ACTIVITY_LABEL,
  dateKey,
  formatClock,
  formatHm,
  fromKey,
  isBefore,
  isEstimate,
  SOURCE_LABEL,
  weekdayLabel,
} from '../../engine/models';
import { logsAround, monthKeys, periodStats, weekKeys } from '../../app/derive';
import { deleteLog, retimeLog } from '../../app/store';
import type { AppState } from '../../app/state';
import { activityColor, Icon, pct, Segmented, Sheet, TimeField } from '../kit';
import { computeStreak } from '../../app/streak';
import { StreakCard } from '../Social';

const WEEK_HEAD = ['월', '화', '수', '목', '금', '토', '일'];

export function Stats({ s, now, openEvening, toast }: { s: AppState; now: Date; openEvening: () => void; toast: (t: string) => void }) {
  const [view, setView] = useState<'week' | 'month'>('week');
  const info = useMemo(() => computeStreak(s, now), [s, now]);
  const [monthOffset, setMonthOffset] = useState(0);
  const todayKey = dateKey(now);

  return (
    <div className="screen">
      <div className="topbar">
        <h1 className="t-title">기록</h1>
        {!(s.observation && (s.observation.phase === 'recording' || todayKey <= s.observation.day1)) && (
          <button type="button" className="btn small" onClick={openEvening}>
            오늘 하루 확인
          </button>
        )}
      </div>
      <Segmented
        label="기간"
        value={view}
        onChange={setView}
        options={[
          { value: 'week', label: '주간' },
          { value: 'month', label: '월간' },
        ]}
      />
      {view === 'week' && (
        <>
          <StreakCard s={s} info={info} toast={toast} share={false} />
          <Week s={s} now={now} todayKey={todayKey} toast={toast} />
        </>
      )}
      {view === 'month' && <Month s={s} now={now} todayKey={todayKey} offset={monthOffset} setOffset={setMonthOffset} />}
    </div>
  );
}

function Week({ s, now, todayKey, toast }: { s: AppState; now: Date; todayKey: string; toast: (t: string) => void }) {
  const [editing, setEditing] = useState<string | null>(null);
  const keys = weekKeys(now);
  const stats = useMemo(() => periodStats(s, keys, now), [s, now]); // eslint-disable-line react-hooks/exhaustive-deps
  const byKey = new Map(stats.days.map((d) => [d.key, d]));
  const rows: { label: string; key: keyof typeof stats.rates }[] = [
    { label: '수면', key: 'sleep' },
    { label: '식사', key: 'meal' },
    { label: '운동', key: 'exercise' },
    { label: '할 일', key: 'task' },
  ];
  const todayLogs = logsAround(s, todayKey).filter((l) => l.end == null || !isBefore(l.end, fromKey(todayKey)));

  return (
    <>
      <section className="card" aria-label="이번 주 셋 데이">
        <div className="row between" style={{ alignItems: 'baseline' }}>
          <h2 className="t-h2">이번 주 셋 데이</h2>
          <span className="t-label">일정대로 지낸 날</span>
        </div>
        <div className="row" style={{ alignItems: 'baseline', gap: 6 }}>
          <span className="t-display accent">{stats.setDays}</span>
          <span className="muted">일 / 7일</span>
        </div>
        <div className="cal-head">
          {WEEK_HEAD.map((w) => (
            <span key={w}>{w}</span>
          ))}
        </div>
        <div className="cal-week">
          {keys.map((k) => (
            <DayCell key={k} k={k} todayKey={todayKey} isSet={!!byKey.get(k)?.isSetDay} isRest={s.restDays.includes(k)} big />
          ))}
        </div>
        <p className="t-label" style={{ margin: 0 }}>
          셋 데이 = 기상 알람 ±30분 안에 일어나고, 그날 습관을 70% 이상 지킨 날
        </p>
      </section>

      <section className="card" aria-label="습관별 달성률">
        <div className="row between">
          <h2 className="t-h2">습관별 달성률</h2>
          <span className="t-label">이번 주 · 추정 기록 제외</span>
        </div>
        {rows.map((r) => {
          const rate = stats.rates[r.key];
          const v = rate ? rateOf(rate) : null;
          const color = r.key === 'task' ? 'var(--task)' : activityColor(r.key);
          return (
            <div key={r.key} className="col" style={{ gap: 4 }}>
              <div className="row between t-body">
                <span>{r.label}</span>
                <span className="num">
                  <span className="strong">{pct(v)}</span>
                  <span className="t-label"> {rate ? `${rate.achieved}/${rate.counted}` : ''}</span>
                </span>
              </div>
              <div className="meter" role="img" aria-label={`${r.label} 달성률 ${pct(v)}`}>
                <i style={{ width: `${Math.round((v ?? 0) * 100)}%`, background: color }} />
              </div>
            </div>
          );
        })}
      </section>

      <section className="card" aria-label="날마다 습관 달성률">
        <h2 className="t-h2">날마다 습관 달성률</h2>
        <div className="bars">
          {keys.map((k) => {
            const d = byKey.get(k);
            const v = d?.rate ?? null;
            return (
              <div key={k} className="b" title={`${weekdayLabel(fromKey(k))} ${pct(v)}`}>
                <span className="t-small num">{v == null ? '' : Math.round(v * 100)}</span>
                <div className={`fill ${v == null ? 'empty' : ''}`} style={{ height: `${Math.max(4, Math.round((v ?? 0.04) * 100))}%`, opacity: d?.isSetDay ? 1 : 0.55 }} />
                <span className="t-small" style={k === todayKey ? { color: 'var(--accent)', fontWeight: 600 } : undefined}>
                  {weekdayLabel(fromKey(k))}
                </span>
              </div>
            );
          })}
        </div>
        <p className="t-label" style={{ margin: 0 }}>진한 막대가 셋 데이예요</p>
      </section>

      <section className="col" aria-label="오늘 기록">
        <div className="section-title">
          <h2 className="t-h2">오늘 기록</h2>
          <span className="t-label">눌러서 시각을 고치거나 지워요</span>
        </div>
        <div className="card list">
          {todayLogs.length === 0 && <div className="empty">아직 기록이 없어요. 홈의 '지금' 버튼을 눌러 보세요.</div>}
          {todayLogs
            .filter((l) => !isEstimate(l))
            .map((l) => (
              <button key={l.id} type="button" className="line-row list-btn" onClick={() => setEditing(l.id)} aria-label={`${ACTIVITY_LABEL[l.activity]} ${formatHm(l.start)}부터 기록 고치기`}>
                <span className="bar" style={{ background: activityColor(l.activity) }} />
                <span className="grow">{ACTIVITY_LABEL[l.activity]}</span>
                <span className="t-label num">
                  {formatHm(l.start)}–{l.end ? formatHm(l.end) : '지금'}
                </span>
                <span className="t-small" style={{ width: 30, textAlign: 'right' }}>
                  {SOURCE_LABEL[l.source]}
                </span>
                <span className="edit-hint">고치기</span>
              </button>
            ))}
        </div>
      </section>
      {editing && <LogEditSheet s={s} id={editing} now={now} toast={toast} onClose={() => setEditing(null)} />}
    </>
  );
}

function DayCell({ k, todayKey, isSet, isRest, big }: { k: string; todayKey: string; isSet: boolean; isRest: boolean; big?: boolean }) {
  const future = k > todayKey;
  const cls = ['cal-cell', big ? 'big' : '', isSet ? 'set' : '', future ? 'future' : '', k === todayKey ? 'today' : ''].join(' ');
  const d = fromKey(k);
  const label = `${d.getMonth() + 1}월 ${d.getDate()}일 ${isSet ? '셋 데이' : isRest ? '쉬는 날' : future ? '예정' : k === todayKey ? '오늘' : '일정대로 지내지 못함'}`;
  return (
    <span className={cls} role="img" aria-label={label} title={label}>
      {isRest && !isSet && <span className="dot" />}
    </span>
  );
}

function Month({ s, now, todayKey, offset, setOffset }: { s: AppState; now: Date; todayKey: string; offset: number; setOffset: (n: number) => void }) {
  const base = new Date(now.getFullYear(), now.getMonth() + offset, 1);
  const keys = monthKeys(base.getFullYear(), base.getMonth());
  const stats = useMemo(() => periodStats(s, keys, now), [s, now, offset]); // eslint-disable-line react-hooks/exhaustive-deps
  const setKeys = new Set(stats.days.filter((d) => d.isSetDay).map((d) => d.key));
  const lead = (fromKey(keys[0]).getDay() + 6) % 7;
  const cells: (string | null)[] = [...Array(lead).fill(null), ...keys];
  while (cells.length % 7) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  const c = s.correction;

  return (
    <>
      <section className="card" aria-label="셋 데이 캘린더" style={{ gap: 8 }}>
        <div className="row between" style={{ alignItems: 'center' }}>
          <div className="row" style={{ gap: 2 }}>
            <button type="button" className="icon-btn" aria-label="이전 달" onClick={() => setOffset(offset - 1)} style={{ marginLeft: -12 }}>
              <Icon name="back" size={18} />
            </button>
            <h2 className="t-h2">{base.getMonth() + 1}월 셋 데이</h2>
            <button type="button" className="icon-btn" aria-label="다음 달" disabled={offset >= 0} onClick={() => setOffset(offset + 1)} style={{ transform: 'scaleX(-1)', opacity: offset >= 0 ? 0.3 : 1 }}>
              <Icon name="back" size={18} />
            </button>
          </div>
          <span className="t-label">일정대로 지낸 날</span>
        </div>
        <div className="cal-head">
          {WEEK_HEAD.map((w) => (
            <span key={w}>{w}</span>
          ))}
        </div>
        {weeks.map((w, i) => (
          <div key={i} className="cal-week">
            {w.map((k, j) => (k ? <DayCell key={k} k={k} todayKey={todayKey} isSet={setKeys.has(k)} isRest={s.restDays.includes(k)} /> : <span key={`b${j}`} className="cal-cell blank" />))}
          </div>
        ))}
        <p className="t-body" style={{ margin: '2px 0 0' }}>
          {offset === 0 ? '이번 달' : `${base.getMonth() + 1}월`} 셋 데이 <strong className="accent">{setKeys.size}일</strong>
        </p>
        <p className="t-label" style={{ margin: 0 }}>채운 칸은 셋 데이, 점은 쉬는 날이에요</p>
      </section>

      {c && (
        <section className="card" aria-label="기상 교정">
          <div className="row between">
            <h2 className="t-h2">기상 단계적 교정</h2>
            <span className="pill">{c.plan.status === 'done' ? '완료' : `${c.plan.currentStep + 1}/${c.plan.totalWeeks + 1}단계`}</span>
          </div>
          <p className="t-body" style={{ margin: 0 }}>
            이번 주 기상 목표 <strong>{formatClock(weekTarget(c.plan))}</strong> → 최종 {formatClock(c.plan.target)} · 한 번에 {c.plan.stepSize}분씩
          </p>
          {c.history.slice(-4).map((h) => (
            <span key={h.week} className="t-label">
              {h.week.slice(5).replace('-', '/')} 주: 기상 달성 {pct(h.rate)} → {formatClock(h.target)}
            </span>
          ))}
          <span className="t-label">지난주 기상 달성률이 80% 이상이면 한 단계 당기고, 50% 미만이면 한 단계 늦춰요.</span>
        </section>
      )}

      <section className="card" aria-label="이번 달 습관 달성률">
        <h2 className="t-h2">이번 달 습관 달성률</h2>
        {(['sleep', 'meal', 'exercise', 'task'] as const).map((k) => {
          const r = stats.rates[k];
          const v = r ? rateOf(r) : null;
          return (
            <div key={k} className="row between t-body">
              <span>{k === 'task' ? '할 일' : ACTIVITY_LABEL[k]}</span>
              <span className="num">
                <span className="strong">{pct(v)}</span> <span className="t-label">{r ? `${r.achieved}/${r.counted}` : ''}</span>
              </span>
            </div>
          );
        })}
      </section>
    </>
  );
}

/** 기록 시각 고치기 창: 제때 누르지 못했으면 시작·끝 시각을 바꾼다. */
function LogEditSheet({ s, id, now, toast, onClose }: { s: AppState; id: string; now: Date; toast: (t: string) => void; onClose: () => void }) {
  const log = s.logs.find((l) => l.id === id);
  const mins = (d: Date) => d.getHours() * 60 + d.getMinutes();
  const [start, setStart] = useState(log ? mins(log.start) : 0);
  const [end, setEnd] = useState(log?.end ? mins(log.end) : 0);
  const [error, setError] = useState<string | null>(null);
  if (!log) return null;
  const label = ACTIVITY_LABEL[log.activity];
  /** 원래 날짜는 두고 시각만 바꾼다(밤을 넘긴 수면은 시작 날짜·끝 날짜를 따로 쓴다). */
  const on = (base: Date, m: number) => new Date(base.getFullYear(), base.getMonth(), base.getDate(), Math.floor(m / 60), m % 60);
  const save = () => {
    const err = retimeLog(log.id, on(log.start, start), log.end ? on(log.end, end) : null);
    if (err) {
      setError(err);
      return;
    }
    toast(`${label} 기록을 ${formatClock(start)}${log.end ? `–${formatClock(end)}` : '부터'}로 고쳤어요`);
    onClose();
  };
  const changed = start !== mins(log.start) || (!!log.end && end !== mins(log.end));
  return (
    <Sheet title={`${label} 기록 고치기`} onClose={onClose}>
      <span className="t-label">
        지금 {formatHm(log.start)}–{log.end ? formatHm(log.end) : `지금(${formatHm(now)})`}. 제때 누르지 못했으면 실제 시각으로 바꿔요. 겹치는 앞뒤 기록은 맞닿게 줄여요.
      </span>
      <div className="field-row">
        <TimeField label="시작" value={start} onChange={(v) => { setStart(v); setError(null); }} />
        {log.end ? <TimeField label="끝" value={end} onChange={(v) => { setEnd(v); setError(null); }} /> : <div className="col" style={{ justifyContent: 'flex-end' }}><span className="t-label">끝: 진행 중</span></div>}
      </div>
      {error && <span className="t-label" role="alert" style={{ color: 'var(--miss)' }}>{error}</span>}
      <button type="button" className="btn primary block" disabled={!changed} onClick={save}>
        바꾸기
      </button>
      <button
        type="button"
        className="btn small danger"
        style={{ alignSelf: 'flex-start' }}
        onClick={() => {
          deleteLog(log.id);
          toast(`${label} 기록을 지웠어요`);
          onClose();
        }}
      >
        기록 지우기
      </button>
    </Sheet>
  );
}
