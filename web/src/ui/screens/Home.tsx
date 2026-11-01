import { useMemo } from 'react';
import { ACTIVITIES, ACTIVITY_LABEL, type Activity, addDays, dateKey, dayStart, diffMin, formatDuration, formatHm, isAfter, isBefore, koreanDate, minutesUntil } from '../../engine/models';
import { DayRing, type RingSegment } from '../DayRing';
import { currentLog, observedDay, planFor, wakeRecord } from '../../app/derive';
import { acceptSuggestion, keepSuggestion, pendingInbox, recentResolved, storageAvailable, storageProblem } from '../../app/store';
import type { AppState } from '../../app/state';
import { Flame, Icon, kindLabel } from '../kit';
import { SurveyCard } from '../Preview';

export function Home({
  s,
  now,
  onTap,
  go,
  theme,
  toggleTheme,
  showGuide,
  streak,
  toast,
}: {
  toast: (t: string) => void;
  s: AppState;
  now: Date;
  onTap: (a: Activity) => void;
  go: (to: 'schedule' | 'settings' | 'evening' | 'review' | 'stats' | 'social') => void;
  streak: number;
  theme: 'dark' | 'light';
  toggleTheme: () => void;
  showGuide: () => void;
}) {
  const todayKey = dateKey(now);
  const plan = useMemo(() => planFor(s, todayKey, now), [s, todayKey, now]);
  const tomorrow = useMemo(() => planFor(s, dateKey(new Date(now.getTime() + 86400000)), now), [s, now]);
  const cur = currentLog(s);
  const upcoming = plan.blocks.filter((b) => isAfter(b.start, now) && b.activity !== 'sleep');
  const next = upcoming[0];
  const inbox = pendingInbox(s, now);
  const resolved = inbox ? null : recentResolved(s, now);
  const woke = wakeRecord(s, todayKey);
  const obs = s.observation;
  const recording = obs?.phase === 'recording';
  // 1일차(관찰한 날)에는 오늘 일정이 없다.
  const observingToday = !!obs && (recording || todayKey <= obs.day1);
  const showEvening = !observingToday && now.getHours() >= 19 && !s.eveningDone.includes(todayKey);

  // 다음 알람: 오늘 기상 전이면 기상, 아니면 오늘 밤 취침
  // 링: 바깥 = 오늘 자동 일정(관찰 중이면 기록), 안쪽 = 실제 기록
  const day0 = dayStart(now);
  const nowMin = diffMin(now, day0);
  /** 오늘(0~24시) 범위로 잘라 그리되, 눌렀을 때는 실제 시작·끝을 보여 준다. */
  const clip = (a: Date, b: Date, color: string, title: string, from = a, to = b): RingSegment | null => {
    const st = Math.max(0, diffMin(a, day0));
    const en = Math.min(1440, diffMin(b, day0));
    return en > st ? { start: st, end: en, color, title, from, to } : null;
  };
  const records = s.logs
    .filter((l) => l.source !== 'estimate')
    .map((l) => clip(l.start, l.end ?? now, `var(--${l.activity})`, `${ACTIVITY_LABEL[l.activity]}${l.end ? '' : '(지금)'}`))
    .filter((x): x is RingSegment => x != null);
  const planSegs: RingSegment[] = observingToday
    ? []
    : [
        ...plan.blocks.map((b) => {
          if (b.kind === 'fixed' && !b.locked) return null; // 이동은 링에 그리지 않는다
          const color = b.kind === 'task' || b.kind === 'fixed' ? 'var(--work)' : `var(--${b.activity ?? 'work'})`;
          const title = b.kind === 'task' ? `할 일 · ${b.title}` : b.kind === 'fixed' ? `일정 · ${b.title}` : b.title;
          return clip(b.start, b.end, color, title);
        }),
        clip(tomorrow.bedTonight, addDays(day0, 1), 'var(--sleep)', '수면(오늘 밤)', tomorrow.bedTonight, tomorrow.wake),
      ].filter((x): x is RingSegment => x != null);
  const ringPlan = observingToday ? records : planSegs;
  const ringRecords = observingToday ? [] : records;

  const nextAlarm =
    !observingToday && !woke && isBefore(now, plan.wake)
      ? { label: '기상 알람', at: plan.wake, reason: plan.alarms[0].reason }
      : { label: '취침 알림', at: tomorrow.bedTonight, reason: tomorrow.alarms[1].reason };

  return (
    <div className="screen">
      <div className="topbar">
        <span className="row" style={{ gap: 10 }}>
          <span className="t-body muted" style={{ fontWeight: 500 }}>
            {koreanDate(now)}
          </span>
          {!observingToday && (
            <button type="button" className="streak-chip" aria-label={`${streak}일 연속 셋 데이, 소셜 보기`} onClick={() => go('social')}>
              <Flame size={16} color={streak > 0 ? 'var(--accent)' : 'var(--line-btn)'} />
              <span className="num">{streak}</span>
            </button>
          )}
        </span>
        <button
          type="button"
          className="theme-btn"
          aria-label={theme === 'dark' ? '밝은 화면으로 바꾸기' : '나이트 화면으로 바꾸기'}
          onClick={toggleTheme}
        >
          <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={18} />
          {theme === 'dark' ? '밝게' : '나이트'}
        </button>
      </div>
      <h1 className="t-title">
        {recording ? '오늘은 하루를 그대로 기록해요' : observingToday ? '내일 일정을 만들었어요' : '오늘 일정은 자동으로 짜뒀어요'}
      </h1>

      <SurveyCard s={s} now={now} toast={toast} />
      {!storageAvailable() && (
        <div className="banner">
          {storageProblem() === 'quota'
            ? '저장 공간이 가득 차 새 기록을 저장하지 못하고 있어요. 설정 → 데이터에서 백업을 내보낸 뒤 가져온 캘린더 연결을 끊거나 기록을 정리해 주세요.'
            : '이 브라우저에서는 기록을 저장할 수 없어요. 창을 닫으면 기록이 사라져요.'}
        </div>
      )}

      <section className="dayring" aria-label="오늘 24시간">
        <DayRing
          plan={ringPlan}
          records={ringRecords}
          recordsOnly={observingToday}
          nowMinutes={nowMin}
          label={`오늘 24시간 링. 지금 ${formatHm(now)}, ${cur ? `${ACTIVITY_LABEL[cur.activity]} 중` : '기록 없음'}`}
        >
          <span className="now-pill num">지금 {formatHm(now)}</span>
          <span className="status">{cur ? `${ACTIVITY_LABEL[cur.activity]} 중` : '기록 없음'}</span>
          <span className="t-body muted">{cur ? `${formatDuration(Math.max(0, minutesUntil(cur, now)))}째` : '아래 버튼으로 시작해요'}</span>
        </DayRing>
        <div className="legend">
          {(['sleep', 'meal', 'work', 'exercise'] as const).map((a) => (
            <span key={a}>
              <i style={{ background: `var(--${a})` }} />
              {ACTIVITY_LABEL[a]}
            </span>
          ))}
        </div>
        <span className="t-small">{observingToday ? '링은 오늘 기록한 하루예요' : '바깥 링은 자동 일정, 안쪽 선은 실제 기록이에요'}</span>
      </section>

      <div className="round-btns" role="group" aria-label="지금 상태 바꾸기">
        {ACTIVITIES.map((a) => (
          <button key={a} type="button" className="round-btn" aria-pressed={cur?.activity === a} aria-label={`${ACTIVITY_LABEL[a]} 시작`} onClick={() => onTap(a)}>
            <span className="c">
              <Icon name={a} size={24} />
            </span>
            <span>{ACTIVITY_LABEL[a]}</span>
          </button>
        ))}
      </div>

      {!recording && (
        <div className="mini-stats">
          <div>
            <span className="t-label">{observingToday ? '내일 기상 알람' : '다음'}</span>
            <span className="t-body strong ellipsis num">
              {observingToday ? formatHm(tomorrow.wake) : next ? `${formatHm(next.start)} ${next.title}` : '남은 일정 없음'}
            </span>
          </div>
          <div title={nextAlarm.reason}>
            <span className="t-label">{nextAlarm.label}</span>
            <span className="t-body strong num">{formatHm(nextAlarm.at)}</span>
          </div>
        </div>
      )}

      {recording && obs && todayKey < obs.day1 && (
        <button type="button" className="hint-chip" onClick={showGuide}>
          <Icon name="sleep" size={16} /> 내일이 1일차예요 · 잘 때 '수면' 누르기
        </button>
      )}
      {recording && obs && todayKey >= obs.day1 && <RecordingCard s={s} now={now} day1={obs.day1} onReview={() => go('review')} />}

      {inbox && (
        <section className="card" aria-label="코칭 제안" style={{ gap: 12 }}>
          <p className="t-body" style={{ margin: 0 }}>
            <Lead text={inbox.message} />
          </p>
          {inbox.kind === 'coach' ? (
            <div className="row" style={{ gap: 8 }}>
              <button type="button" className="btn primary" onClick={() => acceptSuggestion(inbox.id)}>
                바꾸기
              </button>
              <button type="button" className="btn" onClick={() => keepSuggestion(inbox.id)}>
                그대로 두기
              </button>
            </div>
          ) : (
            <div className="row">
              <button type="button" className="btn" onClick={() => keepSuggestion(inbox.id)}>
                확인
              </button>
            </div>
          )}
        </section>
      )}
      {resolved?.resultText && (
        <section className="card" aria-label="코칭 결과" style={{ gap: 10 }}>
          <p className="t-body" style={{ margin: 0 }}>
            <Lead text={resolved.resultText} />
          </p>
          {resolved.action === 'settings' && (
            <div className="row">
              <button type="button" className="btn small" onClick={() => go('settings')}>
                설정 열기
              </button>
            </div>
          )}
        </section>
      )}

      {showEvening && (
        <section className="card" aria-label="저녁 확인">
          <div className="row between">
            <div className="col" style={{ gap: 2 }}>
              <span className="t-h2">오늘 하루 확인</span>
              <span className="t-label">기록 없는 일정만 골라요 · 1분이면 끝나요</span>
            </div>
            <button type="button" className="btn primary small" onClick={() => go('evening')}>
              확인하기
            </button>
          </div>
        </section>
      )}

      {!observingToday && (<section aria-label="다음 일정" className="col" style={{ gap: 0 }}>
        <div className="section-title">
          <h2 className="t-h2">다음 일정</h2>
          <button type="button" className="btn ghost small" onClick={() => go('schedule')}>
            전체 보기
          </button>
        </div>
        {upcoming.length === 0 && <div className="empty">오늘 남은 일정이 없어요</div>}
        {upcoming.slice(0, 3).map((b) => (
          <div key={b.id} className="line-row">
            <span className="time">{formatHm(b.start)}</span>
            <span className="grow ellipsis">{b.title}</span>
            <span className={`tag ${b.adjusted ? 'on' : ''}`}>{kindLabel(b)}</span>
          </div>
        ))}
      </section>)}
    </div>
  );
}

/** 1일차: 설정 없이 기록만 한다. 저녁에 기록한 하루를 보고 내일 일정을 정한다. */
function RecordingCard({ s, now, day1, onReview }: { s: AppState; now: Date; day1: string; onReview: () => void }) {
  const todayKey = dateKey(now);
  const o = observedDay(s, day1, now);
  if (todayKey < day1) {
    return (
      <section className="card tint" aria-label="관찰 안내">
        <span className="t-h2">내일 하루를 그대로 기록해요</span>
        <span className="t-body">
          오늘 밤 잘 때 '수면'을 눌러 주세요. 내일은 식사·업무·운동을 시작할 때마다 버튼만 누르면 돼요. 내일 저녁에 기록한 하루를 보고 일정을 같이 정해요.
        </span>
      </section>
    );
  }
  const meals = Object.keys(o.meals).length;
  const chips = [
    { label: '기상', done: !!o.wakeAt },
    { label: `식사 ${meals}번`, done: meals > 0 },
    { label: o.work ? `업무 ${formatDuration(o.work.minutes)}` : '업무', done: !!o.work },
    { label: '운동', done: !!o.exercise },
  ];
  const late = todayKey > day1 || now.getHours() >= 18;
  return (
    <section className="card tint" aria-label="1일차 기록">
      <div className="row between">
        <span className="t-h2">{todayKey > day1 ? '어제 기록으로 일정을 만들어요' : '1일차 · 오늘은 기록만 해요'}</span>
        <span className="pill">관찰</span>
      </div>
      <div className="chips">
        {chips.map((c) => (
          <span key={c.label} className="chip" aria-checked={c.done} role="img" aria-label={`${c.label} ${c.done ? '기록됨' : '기록 없음'}`} style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            {c.done && <Icon name="check" size={14} stroke={2.6} />}
            {c.label}
          </span>
        ))}
      </div>
      {late ? (
        <button type="button" className="btn primary block" onClick={onReview}>
          {todayKey > day1 ? '어제 하루 정리하기' : '오늘 하루 정리하고 내일 일정 만들기'}
        </button>
      ) : (
        <span className="t-label">설정은 필요 없어요. 저녁에 기록한 하루를 보고, 바꾸고 싶은 시각만 고치면 내일부터 일정이 자동으로 짜여요.</span>
      )}
      {!late && o.logCount > 0 && (
        <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={onReview}>
          지금 정리하기
        </button>
      )}
    </section>
  );
}

/** 첫 문장을 굵게: "어젯밤 5시간 40분 잤어요. 오늘 운동을…" */
function Lead({ text }: { text: string }) {
  const i = text.indexOf('. ');
  if (i < 0) return <>{text}</>;
  return (
    <>
      <strong style={{ fontWeight: 700, color: 'var(--ink)' }}>{text.slice(0, i + 1)}</strong>
      {text.slice(i + 1)}
    </>
  );
}
