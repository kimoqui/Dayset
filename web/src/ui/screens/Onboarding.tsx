import { useState } from 'react';
import { formatClock, type HabitGoals } from '../../engine/models';
import { demoState } from '../../app/seed';
import { DEFAULT_GOALS } from '../../app/state';
import { completeOnboarding, ensureDay, now, replaceState, startObservation, useAppState } from '../../app/store';
import { AccountSheet } from '../Account';
import { ConsentPanel, GoalStep, NotifyStep } from '../Preview';
import { Icon, NumberField, Switch, TimeField } from '../kit';

type Step = 0 | 1 | 2 | 'goal' | 'consent' | 'notify';

export function Onboarding({ toast }: { toast: (t: string) => void }) {
  const [login, setLogin] = useState(false);
  const st = useAppState();
  const [step, setStep] = useState<Step>(0);
  /** 'obs' = 첫날 기록부터, 'direct' = 기록 없이 바로 설정. */
  const [mode, setMode] = useState<'obs' | 'direct'>('obs');
  const [goals, setGoals] = useState<HabitGoals>(structuredClone(DEFAULT_GOALS));
  const [usual, setUsual] = useState(7 * 60 + 40);
  const [prep, setPrep] = useState(50);
  const [travel, setTravel] = useState(40);
  const gap = Math.abs(usual - goals.wake);
  const weeks = Math.ceil(gap / 30);

  if (step === 'goal') {
    return <GoalStep s={st} onBack={() => setStep(0)} onNext={() => setStep('consent')} />;
  }
  if (step === 'consent') {
    return <ConsentPanel s={st} onBack={() => setStep('goal')} onDone={() => setStep('notify')} />;
  }
  if (step === 'notify') {
    return (
      <NotifyStep
        onBack={() => setStep('consent')}
        onDone={() => {
          if (mode === 'obs') startObservation();
          else {
            // 처음 고른 목표를 바로 설정 화면의 기본값으로
            const i = st.intent;
            if (i) setGoals((g) => ({ ...g, wake: i.wake, sleepMinutes: i.sleepMinutes, exercise: i.focus.includes('exercise') ? { ...(g.exercise ?? DEFAULT_GOALS.exercise!), minutes: i.exerciseMinutes } : g.exercise }));
            setStep(1);
          }
        }}
      />
    );
  }

  if (step === 0) {
    return (
      <div className="screen plain" style={{ justifyContent: 'space-between', paddingTop: 48 }}>
        <div className="stack">
          <span className="pill">DaySet</span>
          <h1 className="ob-hero">
            자동으로 짜주는 일정으로
            <br />
            편하게 생활습관 잡기
          </h1>
          <div className="card" style={{ gap: 14 }}>
            {[
              ['sun', '바꾸고 싶은 것(기상·수면·아침·운동·할 일)만 골라요'],
              ['check', "첫날은 '지금' 버튼으로 하루를 그대로 기록해요"],
              ['calendar', '저녁에 기록한 하루를 보고 바꾸고 싶은 시각만 고쳐요'],
              ['bell', '다음 날부터 일정과 알람을 매일 자동으로 짜요'],
            ].map(([icon, text]) => (
              <div key={text} className="row">
                <span style={{ width: 36, height: 36, borderRadius: 18, background: 'var(--tint)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Icon name={icon as 'bell'} size={18} />
                </span>
                <span className="t-body">{text}</span>
              </div>
            ))}
          </div>
          <p className="t-label" style={{ margin: 0 }}>
            기록은 이 기기에 저장돼요. 계정에 로그인하면 웹과 안드로이드 앱에서 같은 기록을 이어 써요.
          </p>
        </div>
        <div className="stack" style={{ gap: 10 }}>
          <button
            type="button"
            className="btn primary block"
            onClick={() => {
              setMode('obs');
              setStep('goal');
            }}
          >
            시작하기 · 목표만 고르고 기록부터
          </button>
          <button
            type="button"
            className="btn block"
            onClick={() => {
              replaceState(demoState(now()));
              ensureDay();
            }}
          >
            예시 데이터로 둘러보기
          </button>
          <button
            type="button"
            className="btn ghost small"
            style={{ alignSelf: 'center' }}
            onClick={() => {
              setMode('direct');
              setStep('goal');
            }}
          >
            기록 없이 바로 설정하기
          </button>
          <button type="button" className="btn ghost small" style={{ alignSelf: 'center' }} onClick={() => setLogin(true)}>
            계정이 있어요 · 로그인해서 이어 쓰기
          </button>
          {login && <AccountSheet onClose={() => setLogin(false)} toast={toast} />}
        </div>
      </div>
    );
  }

  if (step === 1) {
    return (
      <div className="screen plain" style={{ paddingTop: 24 }}>
        <span className="t-label">1 / 2</span>
        <h1 className="t-title">언제 일어나고 싶어요?</h1>
        <section className="card stack">
          <TimeField label="목표 기상 시각" value={goals.wake} onChange={(v) => setGoals({ ...goals, wake: v })} />
          <TimeField label="지금 보통 일어나는 시각" value={usual} onChange={setUsual} />
          <NumberField label="목표 수면 시간" unit="시간" value={goals.sleepMinutes / 60} step={0.5} min={4} max={12} onChange={(v) => setGoals({ ...goals, sleepMinutes: Math.round(v * 60) })} />
        </section>
        <div className="card tint">
          {gap > 30 ? (
            <span className="t-body">
              지금보다 {gap}분 {usual > goals.wake ? '일찍' : '늦게'} 일어나야 해요. 한 번에 바꾸지 않고 <strong>{weeks}주</strong>에 걸쳐 매주 30분씩 옮겨요. 이번 주
              기상 목표는 <strong>{formatClock(usual)}</strong>이에요.
            </span>
          ) : (
            <span className="t-body">지금 기상 시각과 가까워서 바로 {formatClock(goals.wake)} 알람으로 시작해요.</span>
          )}
        </div>
        <div className="row" style={{ gap: 8, marginTop: 'auto' }}>
          <button type="button" className="btn" onClick={() => setStep('notify')}>
            이전
          </button>
          <button type="button" className="btn primary grow" onClick={() => setStep(2)}>
            다음
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="screen plain" style={{ paddingTop: 24 }}>
      <span className="t-label">2 / 2</span>
      <h1 className="t-title">식사·운동 시간을 알려 주세요</h1>
      <p className="t-label" style={{ margin: 0 }}>
        매일 일정의 뼈대가 돼요. 회의와 겹치면 2시간 안에서 자동으로 옮겨요.
      </p>
      <section className="card stack">
        {goals.meals.map((m, i) => (
          <TimeField
            key={m.title}
            label={m.title}
            value={m.start}
            onChange={(v) => setGoals({ ...goals, meals: goals.meals.map((x, j) => (j === i ? { ...x, start: v } : x)) })}
          />
        ))}
        <Switch checked={!!goals.exercise} onChange={(v) => setGoals({ ...goals, exercise: v ? { ...DEFAULT_GOALS.exercise! } : null })} label="운동도 넣기" onText="넣기" offText="빼기" />
        {goals.exercise && (
          <div className="field-row">
            <TimeField label="운동 시각" value={goals.exercise.start} onChange={(v) => setGoals({ ...goals, exercise: { ...goals.exercise!, start: v } })} />
            <NumberField label="운동 시간" value={goals.exercise.minutes} min={5} max={180} onChange={(v) => setGoals({ ...goals, exercise: { ...goals.exercise!, minutes: v } })} />
          </div>
        )}
      </section>
      <section className="card stack">
        <span className="t-body strong">아침 준비와 이동</span>
        <div className="field-row">
          <NumberField label="아침 준비" value={prep} onChange={setPrep} />
          <NumberField label="이동" value={travel} onChange={setTravel} />
        </div>
      </section>
      <div className="row" style={{ gap: 8, marginTop: 'auto' }}>
        <button type="button" className="btn" onClick={() => setStep(1)}>
          이전
        </button>
        <button
          type="button"
          className="btn primary grow"
          onClick={() => completeOnboarding({ goals, settings: { prepMinutes: prep, travelMinutes: travel }, usualWake: usual })}
        >
          시작하기
        </button>
      </div>
    </div>
  );
}
