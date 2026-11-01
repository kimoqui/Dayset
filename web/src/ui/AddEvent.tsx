import { useMemo, useState } from 'react';
import { addDays, addMin, dateKey, dayStart, diffMin, formatDuration, formatHm, isAfter, koreanDate, overlaps } from '../engine/models';
import { eventImpact, planFor } from '../app/derive';
import { EXAMPLES, parseEventText } from '../app/nlp';
import type { AppState } from '../app/state';
import { newId, saveEvent } from '../app/store';
import { blockColor, Segmented, Sheet } from './kit';
import { haptic } from './motion';

type Mode = 'a' | 'b' | 'c';
interface Draft {
  title: string;
  start: Date;
  end: Date;
}

const MODE_KEY = 'dayset:addMode';
const TITLES = ['회의', '수업', '약속', '병원', '운동', '출장'];

function readMode(): Mode {
  try {
    const v = localStorage.getItem(MODE_KEY);
    if (v === 'a' || v === 'b' || v === 'c') return v;
  } catch {
    // 저장소 없음
  }
  return 'a';
}

/**
 * 캘린더 일정 추가 예시안 세 가지.
 * A 한 줄 입력 · B 타임라인에서 빈 시간 고르기 · C 버튼만으로 고르기.
 * 셋 다 '넣으면 일정이 어떻게 바뀌는지'를 바로 보여 준다.
 */
export function AddEventSheet({ s, now, day, onClose, toast }: { s: AppState; now: Date; day: Date; onClose: () => void; toast: (t: string, undo?: boolean | 'plan') => void }) {
  const [mode, setModeState] = useState<Mode>(readMode);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [travel, setTravel] = useState(s.settings.travelMinutes);
  const askTravel = !s.asked.travel;
  const setMode = (m: Mode) => {
    setModeState(m);
    try {
      localStorage.setItem(MODE_KEY, m);
    } catch {
      // 저장소 없음
    }
  };

  const valid = !!draft && draft.title.trim() !== '' && isAfter(draft.end, draft.start);
  const impact = useMemo(
    () => (valid && draft ? eventImpact(s, { id: '__draft', title: draft.title, start: draft.start, end: draft.end }, now) : []),
    [s, draft, valid, now],
  );

  const save = () => {
    if (!draft || !valid) return;
    haptic(10);
    const r = saveEvent({ id: newId('ev'), title: draft.title.trim(), start: draft.start, end: draft.end }, askTravel ? travel : undefined);
    toast(`${draft.title.trim()} 일정을 넣었어요${r.replanned ? '. 남은 일정을 바로 다시 짰어요' : ''}`, 'plan');
    onClose();
  };

  return (
    <Sheet title="캘린더 일정 추가" onClose={onClose}>
      <Segmented<Mode>
        label="입력 방식"
        value={mode}
        onChange={(m) => {
          setMode(m);
          setDraft(null);
        }}
        options={[
          { value: 'a', label: 'A 한 줄' },
          { value: 'b', label: 'B 타임라인' },
          { value: 'c', label: 'C 버튼' },
        ]}
      />
      {mode === 'a' && <ModeLine now={now} onDraft={setDraft} />}
      {mode === 'b' && <ModeTimeline s={s} now={now} initialDay={day} draft={draft} onDraft={setDraft} />}
      {mode === 'c' && <ModeButtons now={now} initialDay={day} onDraft={setDraft} />}

      {draft && (
        <section className="card add-preview" aria-label="미리보기">
          <div className="row between">
            <span className="t-h2 ellipsis">{draft.title || '제목 없음'}</span>
            <span className="t-label num">
              {koreanDate(draft.start)} {formatHm(draft.start)}–{formatHm(draft.end)}
            </span>
          </div>
          <span className="t-label">넣으면 이렇게 바뀌어요</span>
          {impact.length === 0 ? (
            <span className="t-body">다른 일정은 그대로예요</span>
          ) : (
            impact.map((c) => (
              <span key={c.text} className={`impact ${c.kind}`}>
                {c.text}
              </span>
            ))
          )}
        </section>
      )}

      {askTravel && draft && (
        <div className="field">
          <span>이런 일정까지 보통 이동은 몇 분 걸려요? (한 번만 물어요)</span>
          <div className="chips" role="radiogroup" aria-label="이동 시간">
            {[0, 20, 40, 60].map((m) => (
              <button key={m} type="button" className="chip" role="radio" aria-checked={travel === m} onClick={() => setTravel(m)}>
                {m === 0 ? '이동 없음' : `${m}분`}
              </button>
            ))}
          </div>
        </div>
      )}

      <button type="button" className="btn primary block" disabled={!valid} onClick={save}>
        추가하기
      </button>
    </Sheet>
  );
}

/** A: "내일 오전 9시 팀 회의 1시간"처럼 한 줄로 쓰면 바로 알아듣는다. */
function ModeLine({ now, onDraft }: { now: Date; onDraft: (d: Draft | null) => void }) {
  const [text, setText] = useState('');
  const parsed = text.trim() ? parseEventText(text, now) : null;
  const update = (t: string) => {
    setText(t);
    const p = t.trim() ? parseEventText(t, now) : null;
    onDraft(p ? { title: p.title, start: p.start, end: p.end } : null);
  };
  return (
    <div className="stack" style={{ gap: 10 }}>
      <input className="input big-input" value={text} onChange={(e) => update(e.target.value)} placeholder="예: 내일 오전 9시 팀 회의" autoFocus />
      {text.trim() === '' ? (
        <div className="chips">
          {EXAMPLES.map((e) => (
            <button key={e} type="button" className="chip" onClick={() => update(e)}>
              {e}
            </button>
          ))}
        </div>
      ) : parsed ? (
        <div className="chips" aria-label="알아들은 내용">
          <span className="chip parsed">{parsed.found.date ?? '오늘'}</span>
          <span className="chip parsed">{parsed.found.time}</span>
          <span className="chip parsed">{parsed.found.length ?? '1시간(기본)'}</span>
          <span className="chip parsed strong">{parsed.title}</span>
        </div>
      ) : (
        <span className="t-label miss">시각을 함께 써 주세요. 예: "3시", "오전 10:30"</span>
      )}
    </div>
  );
}

const SLOT = 30;
const FROM = 6 * 60;
const TO = 24 * 60;

/** B: 그 날 자동 일정 위에서 빈 시간을 눌러 고른다. 한 번 누르면 1시간, 아래를 한 번 더 누르면 거기까지. */
function ModeTimeline({ s, now, initialDay, draft, onDraft }: { s: AppState; now: Date; initialDay: Date; draft: Draft | null; onDraft: (d: Draft | null) => void }) {
  const [day, setDay] = useState(() => dayStart(initialDay));
  const [title, setTitle] = useState('');
  const plan = useMemo(() => planFor(s, dateKey(day), now), [s, day, now]);
  const slots = Array.from({ length: (TO - FROM) / SLOT }, (_, i) => FROM + i * SLOT);
  const sel = draft && dateKey(draft.start) === dateKey(day) ? { s: diffMin(draft.start, day), e: diffMin(draft.end, day) } : null;

  const tap = (m: number) => {
    haptic(5);
    let st = m;
    let en = m + 60;
    if (sel && m >= sel.s && m < sel.s + SLOT) {
      onDraft(null); // 같은 칸을 다시 누르면 지우기
      return;
    }
    if (sel && m > sel.s) {
      st = sel.s;
      en = m + SLOT;
    }
    onDraft({ title, start: addMin(day, st), end: addMin(day, Math.min(TO, en)) });
  };
  const setT = (t: string) => {
    setTitle(t);
    if (draft) onDraft({ ...draft, title: t });
  };

  return (
    <div className="stack" style={{ gap: 10 }}>
      <div className="chips">
        {[0, 1, 2].map((i) => {
          const d = addDays(dayStart(now), i);
          return (
            <button key={i} type="button" className="chip" role="radio" aria-checked={dateKey(d) === dateKey(day)} onClick={() => { setDay(d); onDraft(null); }}>
              {['오늘', '내일', '모레'][i]}
            </button>
          );
        })}
      </div>
      <span className="t-label">빈 칸을 누르면 1시간, 아래 칸을 한 번 더 누르면 거기까지 늘어나요</span>
      <div className="tl" role="list" aria-label={`${koreanDate(day)} 시간표`}>
        {slots.map((m) => {
          const st = addMin(day, m);
          const blk = plan.blocks.find((b) => b.activity !== 'sleep' && overlaps(b, st, addMin(st, SLOT)));
          const on = sel && m >= sel.s && m < sel.e;
          const first = sel && m === sel.s;
          return (
            <button key={m} type="button" role="listitem" className={`tl-row ${on ? 'on' : ''} ${m % 60 === 0 ? 'hour' : ''}`} onClick={() => tap(m)}>
              <span className="tl-time num">{m % 60 === 0 ? formatHm(st) : ''}</span>
              <span className="tl-slot">
                {on ? (
                  first && <span className="tl-sel">{(draft?.title || '새 일정') + ` · ${formatDuration(sel!.e - sel!.s)}`}</span>
                ) : blk ? (
                  <span className="tl-blk" style={{ borderColor: blockColor(blk) }}>
                    {blk.start.getTime() >= st.getTime() || m === FROM ? blk.title : ''}
                  </span>
                ) : null}
              </span>
            </button>
          );
        })}
      </div>
      <TitlePicker value={title} onChange={setT} />
    </div>
  );
}

/** C: 키보드 없이 버튼만으로. */
function ModeButtons({ now, initialDay, onDraft }: { now: Date; initialDay: Date; onDraft: (d: Draft | null) => void }) {
  const today = dayStart(now);
  const days = [
    { label: '오늘', d: today },
    { label: '내일', d: addDays(today, 1) },
    { label: '모레', d: addDays(today, 2) },
    { label: '토요일', d: addDays(today, (6 - today.getDay() + 7) % 7 || 7) },
  ];
  const [d, setD] = useState(() => dayStart(initialDay));
  const [start, setStart] = useState<number | null>(null);
  const [len, setLen] = useState(60);
  const [title, setTitle] = useState('');
  const emit = (p: { d?: Date; start?: number | null; len?: number; title?: string }) => {
    const dd = p.d ?? d;
    const st = p.start !== undefined ? p.start : start;
    const ln = p.len ?? len;
    const tt = p.title ?? title;
    onDraft(st == null ? null : { title: tt, start: addMin(dd, st), end: addMin(dd, st + ln) });
  };
  const times = [8 * 60, 9 * 60, 10 * 60, 11 * 60, 13 * 60, 14 * 60, 15 * 60, 16 * 60, 18 * 60, 19 * 60];
  return (
    <div className="stack" style={{ gap: 12 }}>
      <Group label="언제">
        {days.map((x) => (
          <button key={x.label} type="button" className="chip" role="radio" aria-checked={dateKey(x.d) === dateKey(d)} onClick={() => { setD(x.d); emit({ d: x.d }); }}>
            {x.label}
          </button>
        ))}
      </Group>
      <Group label="몇 시">
        {times.map((t) => (
          <button key={t} type="button" className="chip num" role="radio" aria-checked={start === t} onClick={() => { setStart(t); emit({ start: t }); }}>
            {formatHm(addMin(today, t))}
          </button>
        ))}
        <input
          className="input num"
          type="time"
          aria-label="직접 고르기"
          style={{ width: 120, height: 36 }}
          onChange={(e) => {
            if (!e.target.value) return;
            const [h, m] = e.target.value.split(':').map(Number);
            setStart(h * 60 + m);
            emit({ start: h * 60 + m });
          }}
        />
      </Group>
      <Group label="얼마나">
        {[30, 60, 90, 120, 180].map((l) => (
          <button key={l} type="button" className="chip" role="radio" aria-checked={len === l} onClick={() => { setLen(l); emit({ len: l }); }}>
            {formatDuration(l)}
          </button>
        ))}
      </Group>
      <TitlePicker value={title} onChange={(t) => { setTitle(t); emit({ title: t }); }} />
    </div>
  );
}

function Group({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="field">
      <span>{label}</span>
      <div className="chips" role="radiogroup" aria-label={label}>
        {children}
      </div>
    </div>
  );
}

function TitlePicker({ value, onChange }: { value: string; onChange: (t: string) => void }) {
  return (
    <div className="field">
      <span>무슨 일정</span>
      <div className="chips">
        {TITLES.map((t) => (
          <button key={t} type="button" className="chip" role="radio" aria-checked={value === t} onClick={() => onChange(t)}>
            {t}
          </button>
        ))}
      </div>
      <input className="input" value={value} onChange={(e) => onChange(e.target.value)} placeholder="직접 쓰기 · 예: 팀 회의" />
    </div>
  );
}

