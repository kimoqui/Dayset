import { useMemo, useState } from 'react';
import type { Outcome } from '../../engine/achievement';
import {
  addDays,
  blockMinutes,
  dateKey,
  dayStart,
  type FixedEvent,
  formatDuration,
  formatHm,
  isAfter,
  isBefore,
  koreanDate,
} from '../../engine/models';
import { effectiveGoals, evaluate, planFor } from '../../app/derive';
import { deleteEvent, newId, regenerate, saveEvent } from '../../app/store';
import type { AppState } from '../../app/state';
import { blockColor, Icon, kindLabel, Segmented, Sheet } from '../kit';
import { AddEventSheet } from '../AddEvent';
import { CalendarSheet } from '../CalendarConnect';
import { ChatSheet, HabitEditSheet, WakeEditSheet } from '../Chat';
import { dayLabel as labelOf } from '../../app/edits';
import { notifyPlan, type ToastFn } from './Tasks';

interface Row {
  key: string;
  time: Date;
  end?: Date;
  title: string;
  tag: string;
  color: string;
  reason?: string;
  outcome?: Outcome;
  adjusted?: boolean;
  /** 눌러서 바꿀 수 있는 조각: 습관 이름 또는 기상. */
  edit?: { kind: 'habit'; title: string } | { kind: 'wake' };
}

const OUTCOME_TAG: Partial<Record<Outcome, string>> = { achieved: '달성', missed: '놓침', estimated: '기록 없음' };

export function Schedule({ s, now, toast, openDemo }: { s: AppState; now: Date; toast: ToastFn; openDemo: () => void }) {
  const [adding, setAdding] = useState(false);
  const [day, setDay] = useState<'today' | 'tomorrow'>('today');
  const [openReason, setOpenReason] = useState<string | null>(null);
  const [editing, setEditing] = useState<FixedEvent | null>(null);
  const [importing, setImporting] = useState(false);
  const [chat, setChat] = useState(false);
  const [editRow, setEditRow] = useState<Row['edit'] | null>(null);
  const todayKey = dateKey(now);
  const tomorrowKey = dateKey(addDays(now, 1));
  const key = day === 'today' ? todayKey : tomorrowKey;
  const plan = useMemo(() => planFor(s, key, now), [s, key, now]);
  const tomorrowPlan = useMemo(() => planFor(s, tomorrowKey, now), [s, tomorrowKey, now]);
  const view = useMemo(() => (day === 'today' ? evaluate(s, todayKey, now) : null), [s, day, todayKey, now]);
  const outcomeById = new Map(view?.outcomes.map((o) => [o.block.id, o.outcome]) ?? []);

  const rows: Row[] = [];
  if (day === 'tomorrow') {
    rows.push({ key: 'wake', time: plan.wake, title: '기상 알람', tag: '알람', color: 'var(--alarm)', reason: plan.alarms[0].reason, edit: { kind: 'wake' } });
  }
  for (const b of plan.blocks) {
    if (b.activity === 'sleep') continue;
    if (day === 'today' && isBefore(b.end, dayStart(now))) continue;
    const ended = !isAfter(b.end, now);
    const outcome = day === 'today' && ended ? outcomeById.get(b.id) : undefined;
    rows.push({
      key: b.id,
      time: b.start,
      end: b.end,
      title: b.kind === 'task' ? `${b.title} · ${formatDuration(blockMinutes(b))}` : b.title,
      tag: kindLabel(b),
      color: blockColor(b),
      outcome,
      adjusted: b.adjusted,
      edit: b.kind === 'habit' && isAfter(b.end, now) ? { kind: 'habit', title: b.title } : undefined,
    });
  }
  const bed = day === 'today' ? tomorrowPlan : null;
  rows.push(
    bed
      ? { key: 'bed', time: bed.bedTonight, title: '취침 알림', tag: '알람', color: 'var(--alarm)', reason: bed.alarms[1].reason }
      : { key: 'bed', time: plan.dayEnd, title: '취침 예정', tag: '알람', color: 'var(--alarm)', reason: '모레 기상 기준 예정 시각' },
  );
  rows.sort((a, b) => a.time.getTime() - b.time.getTime());

  const deferred = plan.deferred.map((d) => {
    const t = s.tasks.find((x) => x.id === d.taskId);
    return `${t?.title ?? '할 일'} ${formatDuration(d.minutes)}: ${d.reason === 'budget' ? '빈 시간의 75%를 채워 다음 날로 넘겼어요' : '마감 전에 넣을 빈 시간이 없어요'}`;
  });
  const upcomingEvents = s.events
    .filter((e) => !isBefore(e.end, dayStart(now)))
    .sort((a, b) => a.start.getTime() - b.start.getTime());

  const obs = s.observation;
  const noPlan = !!obs && (obs.phase === 'recording' ? true : day === 'today' && todayKey <= obs.day1);

  return (
    <div className="screen">
      <div className="topbar">
        <span className="row" style={{ gap: 8 }}>
          <h1 className="t-title">일정</h1>
          <button type="button" className="hint-chip" style={{ height: 30, padding: '0 12px' }} onClick={openDemo}>
            <Icon name="refresh" size={14} /> 시연
          </button>
        </span>
        <span className="row" style={{ gap: 6 }}>
          <button type="button" className="btn small" onClick={() => setAdding(true)}>
            <Icon name="plus" size={16} /> 일정
          </button>
          <button type="button" className="btn primary small" onClick={() => setChat(true)}>
            <Icon name="chat" size={16} /> 말로 바꾸기
          </button>
        </span>
      </div>
      <Segmented
        label="날짜"
        value={day}
        onChange={setDay}
        options={[
          { value: 'today', label: '오늘' },
          { value: 'tomorrow', label: '내일' },
        ]}
      />
      {noPlan ? (
        <div className="card">
          <span className="t-h2">{obs?.phase === 'recording' ? '아직 일정이 없어요' : '오늘은 기록한 날이에요'}</span>
          <span className="t-body muted">
            {obs?.phase === 'recording'
              ? '첫날은 하루를 그대로 기록해요. 기록한 하루를 보고 바꾸고 싶은 시각만 고치면, 다음 날부터 일정과 알람이 자동으로 짜여요.'
              : "내일 일정은 '내일'에서 볼 수 있어요."}
          </span>
        </div>
      ) : (<>
      <p className="t-label" style={{ margin: 0 }}>
        {day === 'today'
          ? "자동으로 짠 일정이에요. 코칭으로 바뀐 일정은 '조정됨'으로 표시해요."
          : `${plan.stored ? '확정한' : '지금 기준으로 짠'} 내일 일정이에요. 기상 ${formatHm(plan.wake)} · 할 일 ${formatDuration(plan.taskMinutes)}`}
      </p>

      {plan.outdated && (
        <div className="card tint row between" style={{ flexDirection: 'row', alignItems: 'center' }}>
          <span className="t-body grow">할 일·일정이 바뀌었어요. {day === 'today' ? '남은 시간을' : '내일 일정을'} 다시 짤까요?</span>
          <button type="button" className="btn primary small" onClick={() => regenerate(key)}>
            다시 짜기
          </button>
        </div>
      )}
      {[...plan.notes, ...deferred].map((n) => (
        <p key={n} className="t-label miss" style={{ margin: 0 }}>
          {n}
        </p>
      ))}

      <p className="t-label" style={{ margin: 0 }}>식사·운동·기상은 눌러서 바꿀 수 있어요. ‘말로 바꾸기’로 한 번에 바꿔도 돼요.</p>
      <section className="card list" aria-label={`${day === 'today' ? '오늘' : '내일'} 일정`}>
        {rows.map((r) => {
          const isNow = day === 'today' && r.end != null && !isBefore(now, r.time) && isBefore(now, r.end);
          const tag = isNow ? '지금' : r.outcome ? OUTCOME_TAG[r.outcome] ?? r.tag : r.tag;
          const tagClass = isNow || r.adjusted || r.outcome === 'achieved' ? 'on' : r.outcome === 'missed' ? 'miss' : '';
          return (
            <div key={r.key}>
              <div className={`line-row ${isNow ? 'now' : ''}`}>
                <span className="time" style={isNow ? { color: 'var(--accent)' } : undefined}>
                  {formatHm(r.time)}
                </span>
                <span className="bar" style={{ background: r.color }} />
                {r.edit && !r.reason ? (
                  <button type="button" className="linklike grow ellipsis" onClick={() => setEditRow(r.edit!)}>
                    {r.title}
                    <span className="edit-hint">바꾸기</span>
                  </button>
                ) : r.reason ? (
                  <button type="button" className="linklike grow" aria-expanded={openReason === r.key} onClick={() => setOpenReason(openReason === r.key ? null : r.key)}>
                    {r.title} <span className="t-small">· 근거</span>
                  </button>
                ) : (
                  <span className="grow ellipsis">{r.title}</span>
                )}
                <span className={`tag ${tagClass}`}>{tag}</span>
              </div>
              {openReason === r.key && r.reason && (
                <p className="t-label" style={{ margin: '0 0 10px 56px' }}>
                  {r.reason}
                  {r.edit && (
                    <button type="button" className="btn ghost small" style={{ marginLeft: 4, height: 28 }} onClick={() => setEditRow(r.edit!)}>
                      바꾸기
                    </button>
                  )}
                </p>
              )}
            </div>
          );
        })}
      </section>
      {day === 'today' && plan.stored && !plan.outdated && (
        <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => regenerate(key)}>
          <Icon name="refresh" size={16} /> 남은 일정 다시 짜기
        </button>
      )}
      </>)}

      <section className="col" aria-label="캘린더 일정">
        <div className="section-title">
          <h2 className="t-h2">캘린더 일정</h2>
          <button type="button" className="btn small" onClick={() => setImporting(true)}>
            {s.calendars.length ? `연결된 캘린더 ${s.calendars.length}` : '캘린더 가져오기'}
          </button>
        </div>
        <span className="t-label">기상 알람과 할 일 배치에 바로 반영해요</span>
        {s.calendars
          .filter((c) => c.error)
          .map((c) => (
            <button key={c.id} type="button" className="banner left warn" onClick={() => setImporting(true)}>
              {c.name}: {c.error}
            </button>
          ))}
        <div className="card list">
          {upcomingEvents.length === 0 && <div className="empty">아직 없어요. 회의·수업·약속을 넣어 주세요.</div>}
          {upcomingEvents.map((e) =>
            e.source ? (
              <div key={e.id} className="line-row">
                <span className="col grow" style={{ gap: 0 }}>
                  <span>{e.title}</span>
                  <span className="t-label num">
                    {koreanDate(e.start)} {formatHm(e.start)}–{formatHm(e.end)}
                  </span>
                </span>
                <span className="tag">{s.calendars.find((c) => c.id === e.source)?.kind === 'google' ? '구글' : '가져옴'}</span>
              </div>
            ) : (
            <div key={e.id} className="line-row">
              <button type="button" className="linklike grow" onClick={() => setEditing(e)}>
                <span className="col" style={{ gap: 0 }}>
                  <span>{e.title}</span>
                  <span className="t-label num">
                    {koreanDate(e.start)} {formatHm(e.start)}–{formatHm(e.end)}
                  </span>
                </span>
              </button>
              <button type="button" className="icon-btn" aria-label={`${e.title} 지우기`} onClick={() => notifyPlan(toast, deleteEvent(e.id), `${e.title} 일정을 지우고 남은 일정을 다시 짰어요`, `${e.title} 일정을 지웠어요`)}>
                <Icon name="trash" size={18} />
              </button>
            </div>
            ),
          )}
          {upcomingEvents.some((e) => e.source) && <span className="t-label" style={{ padding: '6px 0' }}>가져온 일정은 원래 캘린더에서 고치면 다음 동기화 때 바뀌어요</span>}
        </div>
      </section>

      {adding && <AddEventSheet s={s} now={now} day={day === 'today' ? now : addDays(now, 1)} onClose={() => setAdding(false)} toast={toast} />}
      {editing && (
        <EventSheet event={editing} askTravel={!s.asked.travel && !editing.id} travel={s.settings.travelMinutes} onClose={() => setEditing(null)} toast={toast} />
      )}
      {importing && <CalendarSheet s={s} onClose={() => setImporting(false)} toast={toast} />}
      {chat && <ChatSheet s={s} onClose={() => setChat(false)} toast={toast} />}
      {editRow?.kind === 'habit' && <HabitEditSheet s={s} day={key} title={editRow.title} dayLabel={labelOf(key, now)} onClose={() => setEditRow(null)} toast={toast} />}
      {editRow?.kind === 'wake' && (
        <WakeEditSheet s={s} day={key} current={effectiveGoals(s, key).wake} dayLabel={labelOf(key, now)} onClose={() => setEditRow(null)} toast={toast} />
      )}
    </div>
  );
}


const toDateValue = (d: Date): string => dateKey(d);
const toTimeValue = (d: Date): string => formatHm(d);
const combine = (date: string, time: string): Date => {
  const [y, m, dd] = date.split('-').map(Number);
  const [h, mi] = time.split(':').map(Number);
  return new Date(y, m - 1, dd, h, mi);
};

function EventSheet({ event, askTravel, travel: travelDefault, onClose, toast }: { event: FixedEvent; askTravel: boolean; travel: number; onClose: () => void; toast: ToastFn }) {
  const [travel, setTravel] = useState(travelDefault);
  const [title, setTitle] = useState(event.title);
  const [date, setDate] = useState(toDateValue(event.start));
  const [start, setStart] = useState(toTimeValue(event.start));
  const [end, setEnd] = useState(toTimeValue(event.end));
  const s = combine(date, start);
  const e = combine(date, end);
  const valid = title.trim() !== '' && isAfter(e, s);
  return (
    <Sheet title={event.id ? '캘린더 일정 고치기' : '캘린더 일정 추가'} onClose={onClose}>
      <p className="t-label" style={{ margin: 0 }}>
        구글 캘린더를 연결하거나 .ics 파일을 가져오면 자동으로 들어와요. 여기서는 한 건씩 직접 넣어요.
      </p>
      <label className="field">
        <span>제목</span>
        <input className="input" value={title} onChange={(x) => setTitle(x.target.value)} placeholder="예: 팀 회의" autoFocus />
      </label>
      <label className="field">
        <span>날짜</span>
        <input className="input num" type="date" value={date} onChange={(x) => x.target.value && setDate(x.target.value)} />
      </label>
      <div className="field-row">
        <label className="field">
          <span>시작</span>
          <input className="input num" type="time" value={start} onChange={(x) => x.target.value && setStart(x.target.value)} />
        </label>
        <label className="field">
          <span>끝</span>
          <input className="input num" type="time" value={end} onChange={(x) => x.target.value && setEnd(x.target.value)} />
        </label>
      </div>
      {!isAfter(e, s) && <p className="t-label miss" style={{ margin: 0 }}>끝 시각이 시작보다 늦어야 해요</p>}
      {askTravel && (
        <div className="field">
          <span>이런 일정까지 보통 이동은 몇 분 걸려요? (한 번만 물어요)</span>
          <div className="chips" role="radiogroup" aria-label="이동 시간">
            {[0, 20, 40, 60].map((m) => (
              <button key={m} type="button" className="chip" role="radio" aria-checked={travel === m} onClick={() => setTravel(m)}>
                {m === 0 ? '재택·이동 없음' : `${m}분`}
              </button>
            ))}
          </div>
          <span className="t-label">첫 일정이 이르면 기상 알람을 이동 시간만큼 당겨요.</span>
        </div>
      )}
      <button
        type="button"
        className="btn primary block"
        disabled={!valid}
        onClick={() => {
          notifyPlan(toast, saveEvent({ id: event.id || newId('ev'), title: title.trim(), start: s, end: e }, askTravel ? travel : undefined), `${title.trim()} 일정을 넣고 남은 일정을 다시 짰어요`, `${title.trim()} 일정을 저장했어요`);
          onClose();
        }}
      >
        저장
      </button>
    </Sheet>
  );
}
