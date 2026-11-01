import { useEffect, useMemo, useState } from 'react';
import { applyChanges, CoachingEngine } from '../../engine/coaching';
import {
  addDays,
  blockMinutes,
  dayStart,
  diffMin,
  type FixedEvent,
  formatClock,
  formatDuration,
  formatHm,
  koreanDate,
  type ScheduleBlock,
  type TaskItem,
} from '../../engine/models';
import { buildDay, type DayPlan } from '../../engine/scheduleBuilder';
import { comparePlans, effectiveGoals, type PlanChange } from '../../app/derive';
import { type AppState, DEFAULT_GOALS } from '../../app/state';
import { DayRing, type RingSegment } from '../DayRing';
import { blockColor, Icon, TopBar } from '../kit';
import { haptic } from '../motion';

type ScenarioId = 'normal' | 'meeting' | 'lunch' | 'overload' | 'tired';

const SCENARIOS: { id: ScenarioId; label: string; desc: string }[] = [
  { id: 'normal', label: '평소 하루', desc: '목표 습관과 할 일 3개로 내일 일정을 짜요' },
  { id: 'meeting', label: '아침 8시 회의', desc: '이른 회의가 생기면 기상 알람을 당겨요' },
  { id: 'lunch', label: '점심 약속', desc: '겹치는 습관은 뒤로 밀어요' },
  { id: 'overload', label: '할 일 폭탄', desc: '빈 시간의 75%까지만 넣고 나머지는 넘겨요' },
  { id: 'tired', label: '5시간 40분 잔 날', desc: '적게 잔 날은 코칭이 운동과 집중 작업을 줄여요' },
];

interface Step {
  title: string;
  value: string;
  lines: string[];
  /** 이 단계에서 링에 새로 나타나는 블록. */
  blocks: ScheduleBlock[];
  nightSleep?: boolean;
}

interface Built {
  base: DayPlan;
  plan: DayPlan;
  changes: PlanChange[];
  steps: Step[];
  day: Date;
}

const hm = formatHm;

function demoTasks(day: Date, overload: boolean): TaskItem[] {
  const at = (plus: number, h: number) => new Date(day.getFullYear(), day.getMonth(), day.getDate() + plus, h);
  const base: TaskItem[] = [
    { id: 'd-report', title: '분기 보고서', estMinutes: 180, dueAt: at(2, 18), type: 'work', priority: 'high', focus: true, doneMinutes: 0 },
    { id: 'd-english', title: '영어 숙제', estMinutes: 60, dueAt: at(1, 23), type: 'homework', priority: 'normal', focus: false, doneMinutes: 0 },
    { id: 'd-call', title: '치과 예약 전화', estMinutes: 10, dueAt: at(0, 18), type: 'personal', priority: 'normal', focus: false, doneMinutes: 0 },
  ];
  if (!overload) return base;
  return [
    ...base,
    { id: 'd-proposal', title: '제안서 마감', estMinutes: 300, dueAt: at(0, 23), type: 'work', priority: 'high', focus: true, doneMinutes: 0 },
    { id: 'd-slides', title: '발표 자료', estMinutes: 240, dueAt: at(1, 18), type: 'work', priority: 'normal', focus: false, doneMinutes: 0 },
  ];
}

function demoEvents(day: Date, id: ScenarioId): FixedEvent[] {
  const at = (h: number, m = 0) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m);
  if (id === 'meeting') return [{ id: 'd-ev1', title: '팀 회의', start: at(8), end: at(9) }];
  if (id === 'lunch') return [{ id: 'd-ev2', title: '점심 미팅', start: at(11, 30), end: at(13) }];
  return [];
}

function build(s: AppState, id: ScenarioId, now: Date): Built {
  const day = addDays(dayStart(now), 1);
  const useMine = s.onboarded && s.observation?.phase !== 'recording';
  const key = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
  const goals = useMine ? effectiveGoals(s, key) : DEFAULT_GOALS;
  const settings = { ...s.settings, travelMinutes: s.settings.travelMinutes || 40 };
  const input = (events: FixedEvent[], overload: boolean) => ({ date: day, goals, settings, fixedEvents: events, tasks: demoTasks(day, overload) });
  const base = buildDay(input([], false));
  let plan = buildDay(input(demoEvents(day, id), id === 'overload'));
  const changes = id === 'normal' ? [] : comparePlans(base, plan);

  let coachLines: string[] | null = null;
  if (id === 'tired') {
    const sg = new CoachingEngine().evaluate({ type: 'wakeLogged', sleepMinutes: 340 }, { today: plan.blocks, now: plan.wake })[0];
    if (sg) {
      const applied = applyChanges(plan.blocks, sg.changes);
      plan = { ...plan, blocks: applied.blocks };
      const ex = applied.blocks.find((b) => b.adjusted);
      coachLines = [
        sg.message,
        ...(ex ? [`운동 ${formatDuration(blockMinutes(base.blocks.find((b) => b.activity === 'exercise') ?? ex))} → ${formatDuration(blockMinutes(ex))}`] : []),
        ...(applied.deferred.length ? [`집중 작업 ${applied.deferred.length}개는 다음 날로`] : []),
      ];
      changes.push(...(coachLines.slice(1).map((t) => ({ kind: 'moved' as const, text: t }))));
    }
  }

  // 단계별로 나누기
  const blocks = plan.blocks;
  const sleep = blocks[0];
  const fixed = blocks.filter((b) => b.kind === 'fixed');
  const habits = blocks.filter((b) => b.kind === 'habit' && b.activity !== 'sleep');
  const tasks = blocks.filter((b) => b.kind === 'task');
  const budget = Math.floor(plan.freeMinutes * settings.fillRatio);
  const slotOf = (title: string) => [...goals.meals, ...(goals.exercise ? [goals.exercise] : [])].find((h) => h.title === title);
  const deferredMin = plan.deferred.reduce((n, d) => n + d.minutes, 0);

  const steps: Step[] = [
    {
      title: '① 기상 시각 정하기',
      value: `${hm(plan.wake)} 기상`,
      lines: [plan.alarms[0].reason, fixed.length ? '첫 일정이 이르면 준비·이동 시간만큼 알람을 당겨요' : '첫 일정이 늦어서 목표 기상을 그대로 써요'],
      blocks: [],
    },
    {
      title: '② 전날 밤 취침 시각',
      value: `${hm(plan.bedTonight)} 취침`,
      lines: [plan.alarms[1].reason],
      blocks: [sleep],
      nightSleep: true,
    },
    {
      title: '③ 캘린더 일정 고정',
      value: fixed.length ? `${fixed.filter((b) => b.locked).length}개 고정` : '없음',
      lines: fixed.length ? fixed.map((b) => `${hm(b.start)}–${hm(b.end)} ${b.title}`) : ['캘린더 일정이 없어요. 엔진이 움직이지 않는 블록이에요'],
      blocks: fixed,
    },
    {
      title: '④ 식사·운동 자리 잡기',
      value: `습관 ${habits.length}개`,
      lines: habits.map((b) => {
        const slot = slotOf(b.title);
        const moved = slot && formatClock(slot.start) !== hm(b.start);
        return `${hm(b.start)} ${b.title}${moved ? ` (겹쳐서 ${formatClock(slot!.start)} → ${hm(b.start)})` : ''}`;
      }),
      blocks: habits,
    },
    {
      title: '⑤ 빈 시간 계산',
      value: formatDuration(plan.freeMinutes),
      lines: [`빈 시간 ${formatDuration(plan.freeMinutes)} 중 75%인 ${formatDuration(budget)}까지만 할 일을 넣어요`, '나머지 25%는 쉬는 틈과 예상 못 한 일에 남겨요'],
      blocks: [],
    },
    {
      title: '⑥ 할 일 넣기',
      value: `할 일 ${formatDuration(plan.taskMinutes)}`,
      lines: [
        '마감이 빠른 순서 → 우선순위, 50분씩 나누고 10분 쉬어요',
        '집중이 필요한 일은 09–12시에 먼저 넣어요',
        ...tasks.map((b) => `${hm(b.start)}–${hm(b.end)} ${b.title}${b.focus ? ' · 집중' : ''}`),
        ...(deferredMin ? [`다 넣지 못한 ${formatDuration(deferredMin)}은 다음 날로 넘겨요`] : []),
      ],
      blocks: tasks,
    },
    {
      title: '⑦ 알람 맞추기',
      value: '알람 3개',
      lines: [`기상 ${hm(plan.wake)}`, `마무리 ${hm(plan.alarms[2].at)} · ${plan.alarms[2].reason}`, `취침 ${hm(plan.bedTonight)}`],
      blocks: [],
    },
  ];
  if (coachLines) {
    steps.push({ title: '⑧ 코칭으로 조정', value: '자동 조정', lines: coachLines, blocks: blocks.filter((b) => b.adjusted) });
  }
  return { base, plan, changes, steps, day };
}

function toSegments(blocks: ScheduleBlock[], day: Date, plan: DayPlan, nightSleep: boolean): RingSegment[] {
  const clip = (b: { start: Date; end: Date }, color: string, title: string, from = b.start, to = b.end): RingSegment | null => {
    const st = Math.max(0, diffMin(b.start, day));
    const en = Math.min(1440, diffMin(b.end, day));
    return en > st ? { start: st, end: en, color, title, from, to } : null;
  };
  const segs = blocks.map((b) => {
    if (b.kind === 'fixed' && !b.locked) return clip(b, 'var(--calendar)', b.title);
    const color = b.kind === 'task' || b.kind === 'fixed' ? 'var(--work)' : `var(--${b.activity ?? 'work'})`;
    return clip(b, color, b.kind === 'task' ? `할 일 · ${b.title}` : b.title);
  });
  if (nightSleep) segs.push(clip({ start: plan.dayEnd, end: addDays(day, 1) }, 'var(--sleep)', '수면(그날 밤)'));
  return segs.filter((x): x is RingSegment => x != null);
}

/** 일정 자동 생성 시연: 엔진이 내일 일정을 짜는 과정을 단계별로 보여 준다. 저장된 기록은 건드리지 않는다. */
export function Demo({ s, now, onBack }: { s: AppState; now: Date; onBack: () => void }) {
  const [id, setId] = useState<ScenarioId>('normal');
  const [step, setStep] = useState(0); // 0 = 시작 전, n = n단계까지 보임
  const [playing, setPlaying] = useState(false);
  const built = useMemo(() => build(s, id, now), [s, id, now]);
  const total = built.steps.length;

  useEffect(() => {
    if (!playing) return;
    if (step >= total) {
      setPlaying(false);
      return;
    }
    const t = window.setTimeout(() => {
      setStep((n) => n + 1);
      haptic(6);
    }, step === 0 ? 300 : 1500);
    return () => window.clearTimeout(t);
  }, [playing, step, total]);

  const shown = built.steps.slice(0, step);
  const cur = shown[shown.length - 1];
  const segs = useMemo(() => {
    const out: RingSegment[] = [];
    shown.forEach((st) => out.push(...toSegments(st.blocks, built.day, built.plan, !!st.nightSleep)));
    return out;
  }, [shown, built]);
  const revealed = shown.flatMap((st) => st.blocks).filter((b) => b.activity !== 'sleep');
  const uniq = [...new Map(revealed.map((b) => [b.id, b])).values()].sort((a, b) => a.start.getTime() - b.start.getTime());
  const wakeMin = diffMin(built.plan.wake, built.day);

  const pick = (x: ScenarioId) => {
    setId(x);
    setStep(0);
    setPlaying(true);
  };

  return (
    <div className="screen plain demo">
      <TopBar title="일정 자동 생성 시연" sub={`${koreanDate(built.day)} 일정을 짜는 과정`} onBack={onBack} />
      <div className="chips demo-scn" role="radiogroup" aria-label="상황">
        {SCENARIOS.map((x) => (
          <button key={x.id} type="button" className="chip" role="radio" aria-checked={id === x.id} onClick={() => pick(x.id)}>
            {x.label}
          </button>
        ))}
      </div>
      <p className="t-label" style={{ margin: 0 }}>
        {SCENARIOS.find((x) => x.id === id)!.desc}
      </p>

      <section className="dayring" aria-label="일정 링">
        <DayRing plan={segs} records={[]} nowMinutes={step >= 1 ? wakeMin : 0} label="시연 일정 링">
          {cur ? (
            <div className="ring-info" key={step}>
              <span className="sel-pill">{`${step} / ${total}`}</span>
              <span className="sel-title">{cur.value}</span>
              <span className="sel-sub">{cur.title.replace(/^[①-⑧]\s*/, '')}</span>
            </div>
          ) : (
            <div className="ring-info">
              <span className="sel-title">준비됐어요</span>
              <span className="sel-sub">▶ 재생을 누르세요</span>
            </div>
          )}
        </DayRing>
      </section>

      <div className="demo-ctrl">
        <button type="button" className="btn" onClick={() => { setStep(0); setPlaying(false); }} aria-label="처음부터">
          <Icon name="refresh" size={18} />
        </button>
        <button type="button" className="btn primary grow" onClick={() => { if (step >= total) setStep(0); setPlaying(!playing); }}>
          {playing ? '멈춤' : step >= total ? '다시 재생' : step === 0 ? '▶ 일정 짜기 시작' : '▶ 이어서 재생'}
        </button>
        <button type="button" className="btn" disabled={step >= total} onClick={() => { setPlaying(false); setStep((n) => Math.min(total, n + 1)); haptic(6); }}>
          다음 ›
        </button>
      </div>

      {cur && (
        <section className="card demo-step" key={`st-${step}`} aria-live="polite">
          <span className="t-h2">{cur.title}</span>
          {cur.lines.map((l) => (
            <span key={l} className="t-body">
              {l}
            </span>
          ))}
        </section>
      )}

      {uniq.length > 0 && (
        <section className="card list" aria-label="만들어진 일정">
          {uniq.map((b) => (
            <div key={b.id} className="line-row demo-row">
              <span className="time">{hm(b.start)}</span>
              <span className="bar" style={{ background: blockColor(b) }} />
              <span className="grow ellipsis">{b.kind === 'task' ? `${b.title} · ${formatDuration(blockMinutes(b))}` : b.title}</span>
              <span className={`tag ${b.adjusted ? 'on' : ''}`}>{b.adjusted ? '조정됨' : b.kind === 'task' ? '할 일' : b.kind === 'fixed' ? '캘린더' : '습관'}</span>
            </div>
          ))}
        </section>
      )}

      {step >= total && id !== 'normal' && (
        <section className="card tint demo-compare" aria-label="평소와 비교">
          <span className="t-h2">평소 하루와 비교하면</span>
          {built.changes.length ? built.changes.map((c) => <span key={c.text} className={`impact ${c.kind}`}>{c.text}</span>) : <span className="t-body">바뀐 것이 없어요</span>}
        </section>
      )}
      <p className="t-small" style={{ margin: 0, textAlign: 'center' }}>
        시연은 예시 할 일로 계산해요. 내 기록과 일정은 바뀌지 않아요.
      </p>
    </div>
  );
}

