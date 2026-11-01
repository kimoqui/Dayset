import { useMemo, useState } from 'react';
import { addDays, addMin, dateKey, diffMin, formatClock, formatDuration, formatHm, fromKey, type HabitGoals, type HabitSlot, koreanDate } from '../../engine/models';
import { MEAL_SLOTS, type MealSlot, observedDay, roundedClock } from '../../app/derive';
import { DEFAULT_GOALS, type AppState } from '../../app/state';
import { completeObservation } from '../../app/store';
import { fromHmValue, NumberField, Switch, toHmValue, TopBar } from '../kit';

interface HabitRow {
  title: string;
  include: boolean;
  recorded: { start: Date; minutes: number } | null;
  start: number;
  minutes: number;
}

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const round5 = (m: number) => Math.round(m / 5) * 5;

/** 1일차 기록을 보여 주고, 바꾸고 싶은 시각만 고친 뒤 다음 날 일정을 만든다. */
export function Review({ s, now, onBack, onDone }: { s: AppState; now: Date; onBack: () => void; onDone: () => void }) {
  const day1 = s.observation!.day1;
  const obs = useMemo(() => observedDay(s, day1, now), [s, day1, now]);
  const todayKey = dateKey(now);
  const isToday = day1 === todayKey;
  const day2 = dateKey(addDays(fromKey(day1), 1));

  const [actualWake, setActualWake] = useState<number>(() =>
    obs.wakeAt ? roundedClock(obs.wakeAt) : obs.firstLogAt ? round5(roundedClock(obs.firstLogAt) - 30) : 7 * 60 + 30,
  );
  // 처음 접속할 때 고른 목표가 있으면 그 시각을 앞으로의 기상으로 둔다.
  const intent = s.intent;
  const [wake, setWake] = useState<number>(intent?.focus.includes('wake') ? intent.wake : actualWake);
  const [sleepHours, setSleepHours] = useState<number>(() => {
    const morning = s.logs.find((l) => l.activity === 'sleep' && l.end && obs.wakeAt && l.end.getTime() === obs.wakeAt.getTime());
    if (intent?.focus.includes('sleep')) return intent.sleepMinutes / 60;
    const mins = morning?.end ? diffMin(morning.end, morning.start) : 420;
    return clamp(Math.round((mins / 60) * 2) / 2, 5, 10);
  });
  const [rows, setRows] = useState<HabitRow[]>(() => {
    const meal = (slot: MealSlot): HabitRow => {
      const r = obs.meals[slot];
      const def = DEFAULT_GOALS.meals.find((m) => m.title === slot)!;
      return r
        ? { title: slot, include: true, recorded: r, start: roundedClock(r.start), minutes: clamp(round5(r.minutes), 15, 90) }
        : { title: slot, include: slot === '아침 식사' && !!intent?.focus.includes('breakfast'), recorded: null, start: def.start, minutes: def.minutes };
    };
    const ex = obs.exercise;
    return [
      ...MEAL_SLOTS.map(meal),
      ex
        ? { title: '운동', include: true, recorded: ex, start: roundedClock(ex.start), minutes: clamp(round5(ex.minutes), 10, 120) }
        : { title: '운동', include: !!intent?.focus.includes('exercise'), recorded: null, start: 20 * 60 + 30, minutes: intent?.exerciseMinutes ?? 30 },
    ];
  });
  const up = (i: number, p: Partial<HabitRow>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...p } : r)));

  const focusStart = obs.work ? roundedClock(obs.work.start) : s.settings.focusStart;
  const gap = Math.abs(actualWake - wake);
  const firstAlarm = gap > 30 ? actualWake : wake;
  const weeks = Math.ceil(gap / 30);
  const sleepMinutes = Math.round(sleepHours * 60);
  const bed = firstAlarm - sleepMinutes - s.settings.sleepLatencyMinutes;

  const submit = () => {
    const slot = (r: HabitRow): HabitSlot => ({ title: r.title, activity: r.title === '운동' ? 'exercise' : 'meal', start: r.start, minutes: r.minutes });
    const goals: HabitGoals = {
      wake,
      sleepMinutes,
      meals: rows.filter((r) => r.include && r.title !== '운동').map(slot),
      exercise: rows[3].include ? slot(rows[3]) : null,
    };
    completeObservation({
      goals,
      settings: obs.work ? { focusStart, focusEnd: focusStart + 180 } : {},
      recordedWake: actualWake,
    });
    onDone();
  };

  return (
    <div className="screen plain">
      <TopBar
        title={isToday ? '오늘 이렇게 지냈어요' : '어제 이렇게 지냈어요'}
        sub={`${koreanDate(fromKey(day1))} · 바꾸고 싶은 시각만 고치세요`}
        onBack={onBack}
      />
      {obs.logCount < 3 && (
        <div className="banner">기록이 적어요. 기록하지 않은 습관은 기본 시각으로 넣거나 빼 주세요.</div>
      )}

      <section className="card stack" aria-label="기상과 수면">
        <h2 className="t-h2">기상과 수면</h2>
        <CompareRow
          label="일어난 시각"
          recorded={obs.wakeAt ? `기록 ${formatHm(obs.wakeAt)}` : '기록 없음'}
          value={actualWake}
          onChange={(v) => {
            if (wake === actualWake) setWake(v);
            setActualWake(v);
          }}
          hint={obs.wakeAt ? undefined : '몇 시에 일어났는지 알려 주세요'}
        />
        <CompareRow label="앞으로 일어날 시각" recorded={null} value={wake} onChange={setWake} changed={wake !== actualWake} />
        <NumberField label="수면 시간" unit="시간" value={sleepHours} step={0.5} min={4} max={12} onChange={setSleepHours} />
        {gap > 30 && (
          <p className="t-body" style={{ margin: 0 }}>
            {gap}분 차이는 한 번에 바꾸지 않고 <strong>{weeks}주</strong>에 걸쳐 매주 30분씩 옮겨요. 내일 알람은 {formatClock(firstAlarm)}이에요.
          </p>
        )}
      </section>

      <section className="card stack" aria-label="식사와 운동">
        <h2 className="t-h2">식사와 운동</h2>
        {rows.map((r, i) => (
          <div key={r.title} className="col" style={{ gap: 8 }}>
            <Switch checked={r.include} onChange={(v) => up(i, { include: v })} label={r.title} onText="일정에 넣기" offText="빼기" />
            <span className="t-label num">
              {r.recorded ? `기록 ${formatHm(r.recorded.start)} · ${formatDuration(Math.max(5, round5(r.recorded.minutes)))}` : '기록 없음'}
              {r.include ? '' : ' · 일정에서 빼요'}
              {r.include && r.recorded && r.start !== roundedClock(r.recorded.start) && <span className="accent strong"> · 바뀜</span>}
            </span>
            {r.include && (
              <div className="row" style={{ gap: 8 }}>
                <input
                  className="input num"
                  type="time"
                  aria-label={`${r.title} 시각`}
                  value={toHmValue(r.start)}
                  onChange={(e) => e.target.value && up(i, { start: fromHmValue(e.target.value) })}
                  style={{ flex: 1 }}
                />
                <input
                  className="input num"
                  type="number"
                  aria-label={`${r.title} 시간(분)`}
                  min={5}
                  step={5}
                  value={r.minutes}
                  onChange={(e) => up(i, { minutes: clamp(Number(e.target.value) || 5, 5, 180) })}
                  style={{ width: 84, flex: 'none' }}
                />
                <span className="t-label">분</span>
              </div>
            )}
            {i < rows.length - 1 && <div className="divider" />}
          </div>
        ))}
      </section>

      {obs.work && (
        <section className="card" aria-label="업무">
          <div className="row between t-body">
            <span className="strong">업무</span>
            <span className="num">
              {formatHm(obs.work.start)}–{formatHm(obs.work.end)} · {formatDuration(obs.work.minutes)}
            </span>
          </div>
          <span className="t-label">
            집중이 필요한 할 일은 업무를 시작하는 {formatClock(focusStart)}부터 3시간 안에 먼저 넣어요.
          </span>
        </section>
      )}

      <section className="card tint" aria-label="다음 날">
        <span className="t-label">{todayKey >= day2 ? '오늘' : '내일'}부터</span>
        <div className="row between t-body">
          <span>기상 알람</span>
          <span className="strong num">{formatClock(firstAlarm)}</span>
        </div>
        {todayKey < day2 && (
          <div className="row between t-body">
            <span>오늘 밤 취침</span>
            <span className="strong num">{formatHm(addMin(fromKey(day2), bed))}</span>
          </div>
        )}
        <span className="t-label">식사·운동은 위 시각으로, 할 일은 빈 시간에 자동으로 넣어요. 설정에서 언제든 바꿀 수 있어요.</span>
        <button type="button" className="btn primary block" onClick={submit}>
          {todayKey >= day2 ? '이대로 오늘 일정 만들기' : '이대로 내일 일정 만들기'}
        </button>
      </section>
    </div>
  );
}

function CompareRow({
  label,
  recorded,
  value,
  onChange,
  changed,
  hint,
}: {
  label: string;
  recorded: string | null;
  value: number;
  onChange: (v: number) => void;
  changed?: boolean;
  hint?: string;
}) {
  return (
    <label className="field">
      <span>
        {label}
        {recorded != null && <span className="t-label"> · {recorded}</span>}
        {changed && <span className="accent strong"> · 바뀜</span>}
      </span>
      <input className="input num" type="time" value={toHmValue(value)} onChange={(e) => e.target.value && onChange(fromHmValue(e.target.value))} />
      {hint && <span className="t-label">{hint}</span>}
    </label>
  );
}
