// 프리뷰(베타)용 화면 조각: 처음 목표 정하기, 동의, 알림 켜기, 설문, 불편 신고, 베타 지표.

import { useMemo, useState } from 'react';
import { computeMetrics, surveyDue } from '../app/metrics';
import type { AppState, GoalFocus } from '../app/state';
import { addReport, answerSurvey, now as clockNow, setConsent, setIntent, setNotify, surveyLater, track } from '../app/store';
import { formatClock } from '../engine/models';
import { GOAL_EXAMPLES, readGoalText } from '../app/goalText';
import { Icon, type IconName, NumberField, Sheet, TimeField } from './kit';
import { haptic } from './motion';
import { enableNotifications, notifySupport } from './notify';

// ---------------------------------------------------------------------------
// 처음 접속: 목표 정하기
// ---------------------------------------------------------------------------

const FOCUS: { id: GoalFocus; icon: IconName; title: string; desc: string }[] = [
  { id: 'wake', icon: 'sun', title: '일찍 일어나기', desc: '기상 시각을 정하고 매주 조금씩 당겨요' },
  { id: 'sleep', icon: 'moon', title: '충분히 자기', desc: '목표 수면 시간에 맞춰 취침 알림을 맞춰요' },
  { id: 'breakfast', icon: 'meal', title: '아침 챙겨 먹기', desc: '기상과 출발 사이에 아침 시간을 넣어요' },
  { id: 'exercise', icon: 'exercise', title: '운동 습관', desc: '매일 빈 시간에 운동을 넣어요' },
  { id: 'tasks', icon: 'tasks', title: '할 일 미루지 않기', desc: '할 일을 빈 시간에 자동으로 배치해요' },
];

export function GoalStep({ s, onBack, onNext }: { s: AppState; onBack: () => void; onNext: () => void }) {
  const init = s.intent;
  const [manual, setManual] = useState<GoalFocus[]>(init?.focus ?? []);
  /** 글에서 읽었지만 사용자가 끈 목표. */
  const [removed, setRemoved] = useState<GoalFocus[]>([]);
  const [otherOn, setOtherOn] = useState(!!init?.note);
  const [text, setText] = useState(init?.note ?? '');
  const reading = useMemo(() => readGoalText(otherOn ? text : ''), [otherOn, text]);
  // 사용자가 직접 바꾼 값은 글에서 읽은 값보다 앞선다.
  const [wakeIn, setWakeIn] = useState<number | null>(init ? init.wake : null);
  const [sleepIn, setSleepIn] = useState<number | null>(init ? init.sleepMinutes / 60 : null);
  const [exIn, setExIn] = useState<number | null>(init ? init.exerciseMinutes : null);
  const wake = wakeIn ?? reading.wake ?? 7 * 60;
  const sleepH = sleepIn ?? (reading.sleepMinutes != null ? reading.sleepMinutes / 60 : 7);
  const exMin = exIn ?? reading.exerciseMinutes ?? 30;
  const focus = FOCUS.map((f) => f.id).filter((id) => manual.includes(id) || (reading.focus.includes(id) && !removed.includes(id)));
  const on = (f: GoalFocus) => focus.includes(f);
  const auto = (f: GoalFocus) => !manual.includes(f) && reading.focus.includes(f) && !removed.includes(f);
  const toggle = (f: GoalFocus) => {
    haptic(6);
    if (on(f)) {
      setManual((xs) => xs.filter((x) => x !== f));
      if (reading.focus.includes(f)) setRemoved((xs) => [...xs, f]);
    } else {
      setManual((xs) => [...xs, f]);
      setRemoved((xs) => xs.filter((x) => x !== f));
    }
  };
  const exChoices = [...new Set([15, 30, 45, 60, exMin])].sort((a, b) => a - b);
  return (
    <div className="screen plain" style={{ paddingTop: 24 }}>
      <span className="t-label">목표 정하기</span>
      <h1 className="t-title">무엇을 바꾸고 싶어요?</h1>
      <p className="t-label" style={{ margin: 0 }}>
        여러 개 골라도 돼요. 마땅한 게 없으면 '기타'에 적어 주세요. 첫날 기록을 본 뒤 이 목표에 맞춰 일정을 짜요.
      </p>
      <div className="goal-grid" role="group" aria-label="바꾸고 싶은 것">
        {FOCUS.map((f) => (
          <button key={f.id} type="button" className={`goal-card ${on(f.id) ? 'on' : ''}`} aria-pressed={on(f.id)} onClick={() => toggle(f.id)}>
            <span className="goal-ic">
              <Icon name={on(f.id) ? 'check' : f.icon} size={18} />
            </span>
            <span className="col grow" style={{ gap: 2, minWidth: 0 }}>
              <span className="strong">{f.title}</span>
              <span className="t-label">{f.desc}</span>
            </span>
            {auto(f.id) && <span className="auto-tag">적은 글에서</span>}
          </button>
        ))}
        <button
          type="button"
          className={`goal-card ${otherOn ? 'on' : ''}`}
          aria-pressed={otherOn}
          aria-expanded={otherOn}
          onClick={() => {
            haptic(6);
            setOtherOn((v) => !v);
          }}
        >
          <span className="goal-ic">
            <Icon name={otherOn ? 'check' : 'chat'} size={18} />
          </span>
          <span className="col" style={{ gap: 2, minWidth: 0 }}>
            <span className="strong">기타 · 직접 적기</span>
            <span className="t-label">하고 싶은 걸 적으면 알아서 읽고 목표를 맞춰요</span>
          </span>
        </button>
      </div>
      {otherOn && (
        <section className="card stack" aria-label="직접 적기">
          <label className="field">
            <span>바꾸고 싶은 것을 편하게 적어 주세요</span>
            <textarea
              className="input"
              style={{ height: 88, padding: 12, resize: 'none', lineHeight: '21px' }}
              value={text}
              maxLength={300}
              autoFocus
              placeholder="예: 6시 반에 일어나고 저녁 8시에 30분 달리기"
              onChange={(e) => setText(e.target.value)}
            />
          </label>
          {!text.trim() && (
            <div className="chips">
              {GOAL_EXAMPLES.map((e) => (
                <button key={e} type="button" className="chip" onClick={() => setText(e)}>
                  {e}
                </button>
              ))}
            </div>
          )}
          {text.trim() && (
            <div className="col" style={{ gap: 8 }} aria-live="polite">
              <span className="t-label">{reading.found.length ? '이렇게 읽고 위 목표에 반영했어요' : '아직 읽은 목표가 없어요'}</span>
              {reading.found.length > 0 && (
                <div className="chips">
                  {reading.found.map((f) => (
                    <span key={f.focus} className={`pill ${removed.includes(f.focus) ? 'gray' : ''}`}>
                      {f.text}
                    </span>
                  ))}
                </div>
              )}
              {reading.unknown.length > 0 && (
                <span className="t-label">
                  ‘{reading.unknown.join('’, ‘')}’{hasFinal(reading.unknown[reading.unknown.length - 1]) ? '은' : '는'} 아직 일정에 자동으로 넣지 못해요. 시작한 뒤 할 일로 넣을 수 있어요.
                </span>
              )}
            </div>
          )}
        </section>
      )}
      {(on('wake') || on('sleep') || on('exercise')) && (
        <section className="card stack" aria-label="목표 값">
          {on('wake') && <TimeField label="목표 기상 시각" value={wake} onChange={setWakeIn} />}
          {on('sleep') && <NumberField label="목표 수면 시간" unit="시간" value={sleepH} step={0.5} min={5} max={10} onChange={setSleepIn} />}
          {on('exercise') && (
            <div className="field">
              <span>운동 시간{reading.exerciseTitle && reading.exerciseTitle !== '운동' ? ` · ${reading.exerciseTitle}` : ''}</span>
              <div className="chips" role="radiogroup" aria-label="운동 시간">
                {exChoices.map((m) => (
                  <button key={m} type="button" className="chip" role="radio" aria-checked={exMin === m} onClick={() => setExIn(m)}>
                    {m}분
                  </button>
                ))}
              </div>
            </div>
          )}
          {on('wake') && <span className="t-label">지금 기상이 {formatClock(wake)}보다 30분 넘게 늦으면, 한 번에 바꾸지 않고 매주 30분씩 당겨요.</span>}
        </section>
      )}
      <div className="row" style={{ gap: 8, marginTop: 'auto' }}>
        <button type="button" className="btn" onClick={onBack}>
          이전
        </button>
        <button
          type="button"
          className="btn primary grow"
          disabled={focus.length === 0}
          onClick={() => {
            const ex = on('exercise');
            setIntent({
              focus,
              wake,
              sleepMinutes: Math.round(sleepH * 60),
              exerciseMinutes: exMin,
              ...(ex && reading.exerciseTitle ? { exerciseTitle: reading.exerciseTitle } : {}),
              ...(ex && reading.exerciseStart != null ? { exerciseStart: reading.exerciseStart } : {}),
              ...(otherOn && text.trim() ? { note: text.trim() } : {}),
            });
            onNext();
          }}
        >
          {focus.length ? `${focus.length}개 목표로 다음` : '하나 이상 골라 주세요'}
        </button>
      </div>
    </div>
  );
}

/** 마지막 글자에 받침이 있는지(조사 고르기). */
function hasFinal(word: string): boolean {
  const c = word.trim().charCodeAt(word.trim().length - 1);
  return c >= 0xac00 && c <= 0xd7a3 ? (c - 0xac00) % 28 !== 0 : false;
}

// ---------------------------------------------------------------------------
// 동의: 생활 기록(필수) · 베타 지표 내보내기(선택)
// ---------------------------------------------------------------------------

export function ConsentPanel({ s, onBack, onDone, title = '기록 전에 확인해 주세요' }: { s: AppState; onBack?: () => void; onDone: () => void; title?: string }) {
  const [health, setHealth] = useState(s.consent?.health ?? false);
  const [metrics, setMetrics] = useState(s.consent?.metrics ?? false);
  return (
    <div className="screen plain" style={{ paddingTop: 24 }}>
      <span className="t-label">동의</span>
      <h1 className="t-title">{title}</h1>
      <section className="card stack" aria-label="무엇을 기록하나요">
        <div className="consent-row">
          <Icon name="check" size={18} />
          <span className="t-body">
            <strong>기록하는 것</strong> · 수면·식사·업무·운동·휴식을 시작하고 끝낸 시각, 기상 알람에 응답한 시각
          </span>
        </div>
        <div className="consent-row">
          <Icon name="home" size={18} />
          <span className="t-body">
            <strong>저장하는 곳</strong> · 이 기기(브라우저)에만 저장하고 서버로 보내지 않아요
          </span>
        </div>
        <div className="consent-row">
          <Icon name="trash" size={18} />
          <span className="t-body">
            <strong>지우기</strong> · 설정 → 데이터 → 모든 기록 지우기로 언제든 지워요
          </span>
        </div>
      </section>
      <label className={`consent-check ${health ? 'on' : ''}`}>
        <input type="checkbox" checked={health} onChange={(e) => setHealth(e.target.checked)} />
        <span className="t-body">
          <strong>[필수]</strong> 생활 기록(수면·식사·운동 시각) 수집·이용에 동의해요
        </span>
      </label>
      <label className={`consent-check ${metrics ? 'on' : ''}`}>
        <input type="checkbox" checked={metrics} onChange={(e) => setMetrics(e.target.checked)} />
        <span className="t-body">
          <strong>[선택]</strong> 베타 지표 파일 내보내기에 동의해요
          <span className="t-label" style={{ display: 'block' }}>
            이름·기록 시각·할 일 제목 없이, 쓴 날 수와 주별 셋 데이 수 같은 숫자만 담겨요. 내보낼 때마다 내용을 먼저 보여 드려요.
          </span>
        </span>
      </label>
      <details className="dev">
        <summary className="t-label">개인정보 처리 안내 전문</summary>
        <div className="t-label stack" style={{ gap: 6, marginTop: 8 }}>
          <span>1. 처리 항목: 활동 종류와 시작·끝 시각, 알람 응답 시각, 스누즈 횟수, 목표 값, 할 일 이름·걸리는 시간, 가져온 캘린더 일정.</span>
          <span>2. 목적: 하루 일정과 알람을 자동으로 짜고, 목표를 단계적으로 맞추기 위해서.</span>
          <span>3. 보관: 이 기기의 브라우저 저장소. 사용자가 지울 때까지. 서버 전송·제3자 제공 없음.</span>
          <span>4. 베타 지표(선택): 사용자가 직접 내보낸 파일만 운영자가 받으며, 익명 번호로만 구분해요.</span>
          <span>5. DaySet은 의료 서비스가 아니에요. 진단·치료·처방을 하지 않아요.</span>
          <span>6. 동의 철회: 설정 → 데이터에서 동의를 거두면 기록을 지우고 처음 화면으로 돌아가요.</span>
        </div>
      </details>
      <div className="row" style={{ gap: 8, marginTop: 'auto' }}>
        {onBack && (
          <button type="button" className="btn" onClick={onBack}>
            이전
          </button>
        )}
        <button
          type="button"
          className="btn primary grow"
          disabled={!health}
          onClick={() => {
            setConsent({ health, metrics });
            onDone();
          }}
        >
          {health ? '동의하고 계속' : '필수 항목에 동의해 주세요'}
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 알림 켜기(권한 + 푸시 토큰)
// ---------------------------------------------------------------------------

export function NotifyStep({ onBack, onDone }: { onBack: () => void; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const support = notifySupport();
  const turnOn = async () => {
    setBusy(true);
    const r = await enableNotifications();
    setBusy(false);
    setNotify({ enabled: r.permission === 'granted', ...(r.token ? { token: r.token, tokenAt: clockNow() } : {}) });
    track('notify_enable', r.permission === 'granted' ? 'granted' : String(r.permission));
    setMsg(r.text);
    if (r.permission === 'granted') window.setTimeout(onDone, 900);
  };
  return (
    <div className="screen plain" style={{ paddingTop: 24 }}>
      <span className="t-label">알림</span>
      <h1 className="t-title">기록할 때를 알려 드릴게요</h1>
      <p className="t-body" style={{ margin: 0 }}>
        지금 일정을 알림에 계속 띄워 두고, 일정이 시작됐는데 기록이 없으면 알려요. 알림의 '기록하기'를 누르면 바로 기록돼요.
      </p>
      <div className="notif-mock" aria-hidden="true">
        <span className="notif-app">DaySet · 지금</span>
        <strong>12:00 점심 식사 시간이에요</strong>
        <span className="t-label">시작했으면 '기록하기'를 눌러 주세요</span>
        <span className="notif-actions">
          <span>기록하기</span>
          <span>지금은 안 해요</span>
        </span>
      </div>
      <span className="t-label">
        {support === 'sw'
          ? '휴대폰에서는 홈 화면에 추가해 두면 알림 버튼으로 바로 기록할 수 있어요.'
          : '이 화면에서는 알림 버튼 없이 알림만 떠요. 앱 안 팝업으로도 같은 내용을 보여 드려요.'}{' '}
        로컬 버전은 브라우저가 켜져 있는 동안 알려요.
      </span>
      {msg && (
        <p className="t-label accent" role="status" style={{ margin: 0 }}>
          {msg}
        </p>
      )}
      <div className="stack" style={{ gap: 8, marginTop: 'auto' }}>
        <button type="button" className="btn primary block" disabled={busy || support === 'none'} onClick={turnOn}>
          <Icon name="bell" size={18} /> {busy ? '허용 창을 확인해 주세요…' : '알림 켜기'}
        </button>
        <div className="row" style={{ gap: 8 }}>
          <button type="button" className="btn" onClick={onBack}>
            이전
          </button>
          <button type="button" className="btn grow" onClick={onDone}>
            {msg ? '계속' : '나중에 · 앱 안 팝업만'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 설문(7일째·28일째): 없어지면 얼마나 아쉬운지
// ---------------------------------------------------------------------------

const ANSWERS: { id: 'very' | 'some' | 'not' | 'stopped'; label: string }[] = [
  { id: 'very', label: '매우 아쉬워요' },
  { id: 'some', label: '조금 아쉬워요' },
  { id: 'not', label: '아쉽지 않아요' },
  { id: 'stopped', label: '이미 안 써요' },
];

export function SurveyCard({ s, now, toast }: { s: AppState; now: Date; toast: (t: string) => void }) {
  const due = surveyDue(s, now);
  const [answer, setAnswer] = useState<(typeof ANSWERS)[number]['id'] | null>(null);
  const [best, setBest] = useState('');
  const [worst, setWorst] = useState('');
  if (!due) return null;
  return (
    <section className="card tint stack" aria-label="짧은 설문">
      <div className="row between">
        <span className="t-h2">{due === 'd7' ? '일주일 써 보니 어때요?' : '한 달 써 보니 어때요?'}</span>
        <span className="t-label">1분</span>
      </div>
      <span className="t-body">DaySet을 더 이상 쓸 수 없게 되면 어떨 것 같아요?</span>
      <div className="chips" role="radiogroup" aria-label="없어지면">
        {ANSWERS.map((a) => (
          <button key={a.id} type="button" className="chip" role="radio" aria-checked={answer === a.id} onClick={() => setAnswer(a.id)}>
            {a.label}
          </button>
        ))}
      </div>
      {answer && (
        <>
          <input className="input" value={best} onChange={(e) => setBest(e.target.value)} placeholder="가장 좋았던 점(선택)" maxLength={200} />
          <input className="input" value={worst} onChange={(e) => setWorst(e.target.value)} placeholder="가장 불편했던 점(선택)" maxLength={200} />
        </>
      )}
      <div className="row" style={{ gap: 8 }}>
        <button
          type="button"
          className="btn primary grow"
          disabled={!answer}
          onClick={() => {
            answerSurvey({ key: due, answer: answer!, best: best.trim() || undefined, worst: worst.trim() || undefined });
            haptic(10);
            toast('답해 줘서 고마워요. 다음 일정 개선에 반영할게요');
          }}
        >
          보내기
        </button>
        <button type="button" className="btn" onClick={surveyLater}>
          나중에
        </button>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// 불편 신고·의견
// ---------------------------------------------------------------------------

const KINDS: { id: 'bug' | 'hard' | 'idea'; label: string }[] = [
  { id: 'bug', label: '오류' },
  { id: 'hard', label: '불편해요' },
  { id: 'idea', label: '제안' },
];

export function ReportSheet({ page, onClose, toast }: { page: string; onClose: () => void; toast: (t: string) => void }) {
  const [kind, setKind] = useState<'bug' | 'hard' | 'idea'>('hard');
  const [text, setText] = useState('');
  return (
    <Sheet title="불편 신고·의견" onClose={onClose}>
      <div className="chips" role="radiogroup" aria-label="종류">
        {KINDS.map((k) => (
          <button key={k.id} type="button" className="chip" role="radio" aria-checked={kind === k.id} onClick={() => setKind(k.id)}>
            {k.label}
          </button>
        ))}
      </div>
      <textarea className="input" style={{ height: 120, padding: 12, resize: 'none' }} value={text} onChange={(e) => setText(e.target.value)} placeholder="어느 화면에서 무엇을 하다가 어땠는지 적어 주세요" maxLength={1000} autoFocus />
      <span className="t-label">이 기기에 저장되고, 베타 지표 파일을 보낼 때 함께 담겨요.</span>
      <button
        type="button"
        className="btn primary block"
        disabled={!text.trim()}
        onClick={() => {
          addReport({ kind, text: text.trim(), page });
          toast('남겼어요. 지표 파일을 보낼 때 함께 전달돼요');
          onClose();
        }}
      >
        남기기
      </button>
    </Sheet>
  );
}

// ---------------------------------------------------------------------------
// 베타 지표: 미리 보기 + 파일 내보내기
// ---------------------------------------------------------------------------

export function MetricsCard({ s, now, toast }: { s: AppState; now: Date; toast: (t: string) => void }) {
  const report = useMemo(() => computeMetrics(s, now), [s, now]);
  const [show, setShow] = useState(false);
  const text = JSON.stringify(report, null, 2);
  const lastWeek = report.habit.weeks.at(-1);
  const survey = report.surveys.at(-1);
  const download = () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    a.download = `dayset-metrics-${report.anonId}-${report.generatedAt.slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    track('metrics_export');
    toast('지표 파일을 내려받았어요. 베타 설문 폼에 올려 주세요');
  };
  if (!s.consent?.metrics) {
    return (
      <section className="card stack" aria-label="베타 지표">
        <h2 className="t-h2">베타 지표</h2>
        <span className="t-label">지표 내보내기에 동의하지 않았어요. 아래 '동의 다시 보기'에서 바꿀 수 있어요.</span>
      </section>
    );
  }
  return (
    <section className="card stack" aria-label="베타 지표">
      <div className="row between">
        <h2 className="t-h2">베타 지표</h2>
        <span className="t-label">익명 {report.anonId}</span>
      </div>
      <div className="metric-grid">
        <div>
          <span className="t-label">쓴 날</span>
          <span className="num strong">{report.retention.activeDays}일</span>
        </div>
        <div>
          <span className="t-label">활성화</span>
          <span className="num strong">{report.activation.activated ? '완료' : '전'}</span>
        </div>
        <div>
          <span className="t-label">이번 주 셋 데이</span>
          <span className="num strong">{lastWeek?.setDays ?? 0}일</span>
        </div>
        <div>
          <span className="t-label">7일 유지</span>
          <span className="num strong">{report.retention.d7 ? '예' : '아직'}</span>
        </div>
      </div>
      <span className="t-label">
        담기는 것: 쓴 날 수, 주별 셋 데이 수, 기능 사용 횟수, 설문({survey ? '응답함' : '없음'}), 불편 신고 {report.feedback.length}건 · 담기지 않는 것: 이름, 기록 시각, 할 일·일정 제목, 위치
      </span>
      <div className="row wrap" style={{ gap: 8 }}>
        <button type="button" className="btn primary" onClick={download}>
          지표 파일 내보내기
        </button>
        <button
          type="button"
          className="btn"
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(text);
              toast('지표를 복사했어요');
            } catch {
              toast('복사하지 못했어요. 파일로 내보내 주세요');
            }
          }}
        >
          복사
        </button>
        <button type="button" className="btn ghost small" onClick={() => setShow(!show)}>
          {show ? '내용 접기' : '보낼 내용 보기'}
        </button>
      </div>
      {show && <pre className="metric-pre">{text}</pre>}
    </section>
  );
}
