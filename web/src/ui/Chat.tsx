// 말로 일정 바꾸기(채팅) + 일정 조각 바꾸기 창.
// 바로 바꾸지 않는다: 읽은 내용과 바뀌는 일정을 먼저 보여 주고, '바꾸기'를 눌러야 적용한다(15초 되돌리기).

import { useEffect, useMemo, useRef, useState } from 'react';
import { CHAT_EXAMPLES, interpretChat } from '../app/chatCommand';
import { describeEdit, type EditScope, habitOn, previewEdits, type ScheduleEdit } from '../app/edits';
import type { AppState } from '../app/state';
import { applyEdits, getState, now as clockNow } from '../app/store';
import { objectParticle, topicParticle } from '../engine/coaching';
import { formatClock, formatDuration } from '../engine/models';
import { Icon, NumberField, Segmented, Sheet, TimeField } from './kit';
import { haptic } from './motion';
import { notifyPlan, type ToastFn } from './screens/Tasks';

interface Msg {
  id: number;
  who: 'me' | 'bot';
  text: string;
  edits?: ScheduleEdit[];
  state?: 'ask' | 'done' | 'cancel';
}

let msgSeq = 0;

/** 변경 미리보기 묶음. */
function Preview({ s, edits }: { s: AppState; edits: ScheduleEdit[] }) {
  const t = clockNow();
  const pv = useMemo(() => previewEdits(s, edits, t), [s, edits]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <div className="col" style={{ gap: 6 }}>
      <ul className="chat-list">
        {edits.map((e, i) => (
          <li key={i}>{describeEdit(s, e, t)}</li>
        ))}
      </ul>
      {pv.map((p) => (
        <div key={p.day} className="col" style={{ gap: 2 }}>
          <span className="t-label strong">{p.label} 일정</span>
          {p.diffs.length ? (
            p.diffs.map((d) => (
              <span key={d} className="t-label">
                · {d}
              </span>
            ))
          ) : (
            <span className="t-label">· 겉으로 바뀌는 시각은 없어요</span>
          )}
        </div>
      ))}
    </div>
  );
}

export function ChatSheet({ s, onClose, toast }: { s: AppState; onClose: () => void; toast: ToastFn }) {
  const [msgs, setMsgs] = useState<Msg[]>([
    { id: msgSeq++, who: 'bot', text: '일정을 어떻게 바꿀까요? 말하듯이 적어 주세요. 바꾸기 전에 무엇이 바뀌는지 먼저 보여 드릴게요.' },
  ]);
  const [text, setText] = useState('');
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => end.current?.scrollIntoView({ block: 'end', behavior: 'smooth' }), [msgs]);

  const send = (raw: string) => {
    const q = raw.trim();
    if (!q) return;
    haptic(6);
    const r = interpretChat(q, getState(), clockNow());
    setMsgs((m) => [...m, { id: msgSeq++, who: 'me', text: q }, { id: msgSeq++, who: 'bot', text: r.reply, edits: r.edits.length ? r.edits : undefined, state: r.edits.length ? 'ask' : undefined }]);
    setText('');
  };

  const decide = (id: number, ok: boolean) => {
    const msg = msgs.find((m) => m.id === id);
    if (!msg?.edits) return;
    if (ok) {
      const r = applyEdits(msg.edits);
      haptic(12);
      notifyPlan(toast, { ...r, replanned: true }, '말한 대로 일정을 바꿨어요');
    }
    setMsgs((m) => [
      ...m.map((x) => (x.id === id ? { ...x, state: ok ? ('done' as const) : ('cancel' as const) } : x)),
      { id: msgSeq++, who: 'bot', text: ok ? '바꿨어요. 일정 탭에서 확인할 수 있어요.' : '그대로 둘게요.' },
    ]);
  };

  return (
    <Sheet title="말로 일정 바꾸기" onClose={onClose}>
      <div className="chat-log" aria-live="polite">
        {msgs.map((m) => (
          <div key={m.id} className={`chat-msg ${m.who}`}>
            <span className="chat-bubble">{m.text}</span>
            {m.edits && (
              <div className="chat-card">
                <Preview s={s} edits={m.edits} />
                {m.state === 'ask' ? (
                  <div className="row" style={{ gap: 8 }}>
                    <button type="button" className="btn primary small grow" onClick={() => decide(m.id, true)}>
                      바꾸기
                    </button>
                    <button type="button" className="btn small" onClick={() => decide(m.id, false)}>
                      그대로 두기
                    </button>
                  </div>
                ) : (
                  <span className="t-label">{m.state === 'done' ? '적용했어요' : '적용하지 않았어요'}</span>
                )}
              </div>
            )}
          </div>
        ))}
        <div ref={end} />
      </div>
      <div className="chips">
        {CHAT_EXAMPLES.slice(0, 4).map((e) => (
          <button key={e} type="button" className="chip" onClick={() => send(e)}>
            {e}
          </button>
        ))}
      </div>
      <div className="row" style={{ gap: 8 }}>
        <input
          className="input grow"
          value={text}
          maxLength={200}
          placeholder="예: 내일 운동 7시로 옮겨줘"
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && !e.nativeEvent.isComposing && send(text)}
          aria-label="바꿀 내용"
        />
        <button type="button" className="btn primary square" style={{ width: 44, padding: 0 }} aria-label="보내기" disabled={!text.trim()} onClick={() => send(text)}>
          <Icon name="forward" size={18} />
        </button>
      </div>
      <span className="t-label">지금은 앱 안에서 규칙으로 읽어요. 서버를 붙이면 같은 창에서 AI(Claude)가 읽어요.</span>
    </Sheet>
  );
}

/** 일정 조각(식사·운동) 바꾸기 창. */
export function HabitEditSheet({ s, day, title, dayLabel, onClose, toast }: { s: AppState; day: string; title: string; dayLabel: string; onClose: () => void; toast: ToastFn }) {
  const cur = habitOn(s, day, title) ?? habitOn(s, day, title);
  const edited = !!s.overrides[day]?.habits?.[title];
  const [start, setStart] = useState(cur?.start ?? 12 * 60);
  const [minutes, setMinutes] = useState(cur?.minutes ?? 30);
  const [scope, setScope] = useState<EditScope>('day');
  const edit: ScheduleEdit = { kind: 'habit', day, title, patch: { start, minutes }, scope };
  const changed = !cur || cur.start !== start || cur.minutes !== minutes;
  const apply = (edits: ScheduleEdit[], text: string) => {
    notifyPlan(toast, { ...applyEdits(edits), replanned: true }, text);
    haptic(12);
    onClose();
  };
  return (
    <Sheet title={`${title} 바꾸기`} onClose={onClose}>
      <span className="t-label">
        지금 {dayLabel} {cur ? `${formatClock(cur.start)} · ${formatDuration(cur.minutes)}` : '일정에 없음'}
        {edited ? ' · 이날만 바꾼 값' : ''}
      </span>
      <div className="field-row">
        <TimeField label="시작" value={start} onChange={setStart} />
        <NumberField label="길이" value={minutes} min={5} max={240} onChange={setMinutes} />
      </div>
      <Segmented<EditScope>
        label="적용 범위"
        value={scope}
        onChange={setScope}
        options={[
          { value: 'day', label: `${dayLabel}만` },
          { value: 'every', label: '매일 이렇게' },
        ]}
      />
      {changed && <Preview s={s} edits={[edit]} />}
      <button type="button" className="btn primary block" disabled={!changed} onClick={() => apply([edit], `${title}${objectParticle(title)} 바꾸고 일정을 다시 짰어요`)}>
        바꾸기
      </button>
      <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
        <button type="button" className="btn small danger" onClick={() => apply([{ kind: 'habit', day, title, patch: { skip: true }, scope: 'day' }], `${dayLabel} ${title}${topicParticle(title)} 뺐어요`)}>
          {dayLabel}{topicParticle(dayLabel)} 빼기
        </button>
        {edited && (
          <button type="button" className="btn small" onClick={() => apply([{ kind: 'reset', day }], `${dayLabel} 바꾼 것을 되돌렸어요`)}>
            원래대로
          </button>
        )}
      </div>
    </Sheet>
  );
}

/** 기상 알람 바꾸기 창. */
export function WakeEditSheet({ s, day, current, dayLabel, onClose, toast }: { s: AppState; day: string; current: number; dayLabel: string; onClose: () => void; toast: ToastFn }) {
  const [wake, setWake] = useState(current);
  const [scope, setScope] = useState<EditScope>('day');
  const edit: ScheduleEdit = { kind: 'wake', day, minutes: wake, scope };
  return (
    <Sheet title="기상 알람 바꾸기" onClose={onClose}>
      <span className="t-label">
        지금 {dayLabel} {formatClock(current)}. 첫 일정이 이르면 준비·이동 시간만큼 더 일찍 울려요.
      </span>
      <TimeField label="기상 목표" value={wake} onChange={setWake} />
      <Segmented<EditScope>
        label="적용 범위"
        value={scope}
        onChange={setScope}
        options={[
          { value: 'day', label: `${dayLabel}만` },
          { value: 'every', label: '매일 이렇게' },
        ]}
      />
      {wake !== current && <Preview s={s} edits={[edit]} />}
      <button
        type="button"
        className="btn primary block"
        disabled={wake === current}
        onClick={() => {
          notifyPlan(toast, { ...applyEdits([edit]), replanned: true }, `기상 알람을 ${formatClock(wake)}으로 바꿨어요`);
          haptic(12);
          onClose();
        }}
      >
        바꾸기
      </button>
      {scope === 'every' && s.correction && <span className="t-label">매일로 바꾸면 단계적 교정은 멈추고 이 시각으로 맞춰요.</span>}
    </Sheet>
  );
}
