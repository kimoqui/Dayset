import { useRef, useState } from 'react';
import { weekTarget } from '../../engine/correction';
import { formatClock, formatHm, type HabitGoals, type HabitSlot, koreanDate, TASK_TYPE, type TaskType } from '../../engine/models';
import { demoState } from '../../app/seed';
import { deserialize, keepCopy, keptBackups, serialize, type AppState } from '../../app/state';
import { calibrationFor, MIN_TYPE_SAMPLES } from '../../app/duration';
import { CalendarSheet } from '../CalendarConnect';
import { notifyPlan, type ToastFn } from './Tasks';
import { getClockOffset, now, replaceState, resetAll, setClockOffset, setCorrection, setDurationAuto, setNotify, track, updateGoals, updateSettings } from '../../app/store';
import { ConsentPanel, MetricsCard, ReportSheet } from '../Preview';
import { AccountCard } from '../Account';
import { AppConnectCard } from '../GetApp';
import { enableNotifications } from '../notify';
import { Icon, NumberField, Segmented, Switch, TimeField, TopBar } from '../kit';

export type Theme = 'system' | 'light' | 'dark' | 'pastel';

export function Settings({
  s,
  openDemo,
  theme,
  setTheme,
  testRing,
  toast,
}: {
  s: AppState;
  openDemo: () => void;
  theme: Theme;
  setTheme: (t: Theme) => void;
  testRing: () => void;
  toast: ToastFn;
}) {
  const [calOpen, setCalOpen] = useState(false);
  const [reporting, setReporting] = useState(false);
  const [consentOpen, setConsentOpen] = useState(false);
  const [confirmWithdraw, setConfirmWithdraw] = useState(false);
  const kept = keptBackups();
  const durCount = s.durations.samples.filter((x) => !x.outlier).length;
  const durByType = (Object.keys(TASK_TYPE) as TaskType[])
    .map((k) => ({ k, c: calibrationFor(s.durations, { type: k, title: '' }) }))
    .filter((x) => x.c)
    .map((x) => `${TASK_TYPE[x.k].label} ${x.c!.ratio}배`);
  const g = s.goals;
  const st = s.settings;
  const [usual, setUsual] = useState<number>(s.correction?.plan.baseline ?? g.wake);
  const [confirmReset, setConfirmReset] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const perm = typeof Notification !== 'undefined' ? Notification.permission : 'unsupported';
  const [permState, setPermState] = useState<string>(perm);

  const setGoals = (p: Partial<HabitGoals>) => updateGoals({ ...g, ...p });
  const setMeal = (i: number, p: Partial<HabitSlot>) => setGoals({ meals: g.meals.map((m, j) => (j === i ? { ...m, ...p } : m)) });

  const exportData = () => {
    const blob = new Blob([serialize(s)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    const d = now();
    a.download = `dayset-backup-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };

  const importData = async (file: File) => {
    try {
      const next = deserialize(await file.text());
      // 지금 기록은 지우지 않고 보관한 뒤 바꾼다(잘못 불러와도 되돌릴 수 있게).
      keepCopy(serialize(s), 'before-import');
      replaceState(next);
      setMsg('백업을 불러왔어요. 불러오기 전 기록은 아래에 보관했어요');
    } catch (e) {
      setMsg(`불러오지 못했어요: ${(e as Error).message}`);
    }
  };

  const offset = getClockOffset();
  const [clockValue, setClockValue] = useState(() => {
    const d = now();
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  });

  return (
    <div className="screen two-col">
      <TopBar title="설정" />

      {s.demo && (
        <div className="card tint">
          <span className="t-body">예시 데이터로 보는 중이에요. 내 정보로 시작하면 예시 기록은 지워져요.</span>
          <button type="button" className="btn primary" onClick={() => resetAll()}>
            내 정보로 새로 시작
          </button>
        </div>
      )}

      <AccountCard toast={toast} />
      <AppConnectCard toast={toast} />

      <section className="card" aria-label="시연">
        <div className="row between">
          <div className="col" style={{ gap: 2 }}>
            <span className="t-h2">일정 자동 생성 시연</span>
            <span className="t-label">발표용 · 엔진이 일정을 짜는 과정을 단계별로 보여 줘요</span>
          </div>
          <button type="button" className="btn primary small" onClick={openDemo}>
            열기
          </button>
        </div>
      </section>

      <section className="card stack" aria-label="기상과 수면">
        <h2 className="t-h2">기상과 수면</h2>
        <div className="field-row">
          <TimeField label="목표 기상" value={g.wake} onChange={(v) => setGoals({ wake: v })} />
          <NumberField label="수면 시간" unit="시간" value={g.sleepMinutes / 60} step={0.5} min={4} max={12} onChange={(v) => setGoals({ sleepMinutes: Math.round(v * 60) })} />
        </div>
        <div className="divider" />
        <span className="t-body strong">단계적 교정</span>
        {s.correction && s.correction.plan.status === 'active' ? (
          <span className="t-body">
            이번 주 기상 목표 <strong>{formatClock(weekTarget(s.correction.plan))}</strong> → 최종 {formatClock(s.correction.plan.target)}
          </span>
        ) : (
          <span className="t-label">지금 기상 시각과 목표가 30분 넘게 차이 나면, 매주 30분씩 단계적으로 당겨요.</span>
        )}
        <div className="row" style={{ gap: 10, alignItems: 'flex-end' }}>
          <div className="grow">
            <TimeField label="지금 보통 일어나는 시각" value={usual} onChange={setUsual} />
          </div>
          <button type="button" className="btn" onClick={() => setCorrection(usual)}>
            {s.correction ? '다시 만들기' : '교정 시작'}
          </button>
        </div>
        {s.correction && (
          <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => setCorrection(null)}>
            교정 끄기 · 목표 기상을 바로 쓰기
          </button>
        )}
      </section>

      <section className="card stack" aria-label="습관 시간">
        <h2 className="t-h2">습관 시간</h2>
        {g.meals.map((m, i) => (
          <div key={m.title} className="field-row">
            <TimeField label={m.title} value={m.start} onChange={(v) => setMeal(i, { start: v })} />
            <NumberField label="걸리는 시간" value={m.minutes} min={10} max={120} onChange={(v) => setMeal(i, { minutes: v })} />
          </div>
        ))}
        <Switch
          checked={!!g.exercise}
          onChange={(v) => setGoals({ exercise: v ? { title: '운동', activity: 'exercise', start: 20 * 60 + 30, minutes: 30 } : null })}
          label="운동 넣기"
          onText="넣기"
          offText="빼기"
        />
        {g.exercise && (
          <div className="field-row">
            <TimeField label="운동" value={g.exercise.start} onChange={(v) => setGoals({ exercise: { ...g.exercise!, start: v } })} />
            <NumberField label="걸리는 시간" value={g.exercise.minutes} min={5} max={180} onChange={(v) => setGoals({ exercise: { ...g.exercise!, minutes: v } })} />
          </div>
        )}
      </section>

      <section className="card stack" aria-label="준비와 이동">
        <h2 className="t-h2">준비와 이동</h2>
        <p className="t-label" style={{ margin: 0 }}>
          첫 일정이 이르면 기상 = 첫 일정 − 준비 − 이동으로 알람을 당겨요.
        </p>
        <div className="field-row">
          <NumberField label="아침 준비" value={st.prepMinutes} onChange={(v) => updateSettings({ prepMinutes: v })} />
          <NumberField label="이동" value={st.travelMinutes} onChange={(v) => updateSettings({ travelMinutes: v })} />
          <NumberField label="잠들기까지" value={st.sleepLatencyMinutes} max={90} onChange={(v) => updateSettings({ sleepLatencyMinutes: v })} />
          <NumberField label="취침 전 마무리" value={st.windDownMinutes} max={120} onChange={(v) => updateSettings({ windDownMinutes: v })} />
        </div>
        {st.bedEarlierMinutes > 0 && (
          <div className="row between">
            <span className="t-body">코칭으로 취침 {st.bedEarlierMinutes}분 앞당김</span>
            <button type="button" className="btn small" onClick={() => updateSettings({ bedEarlierMinutes: 0 })}>
              되돌리기
            </button>
          </div>
        )}
      </section>

      <section className="card stack" aria-label="할 일 배치">
        <h2 className="t-h2">할 일 배치</h2>
        <div className="field-row">
          <TimeField label="집중 시간 시작" value={st.focusStart} onChange={(v) => updateSettings({ focusStart: v })} />
          <TimeField label="집중 시간 끝" value={st.focusEnd} onChange={(v) => updateSettings({ focusEnd: v })} />
          <NumberField label="한 조각" value={st.chunkMinutes} min={15} max={120} onChange={(v) => updateSettings({ chunkMinutes: v })} />
          <NumberField label="조각 사이 휴식" value={st.restMinutes} max={30} onChange={(v) => updateSettings({ restMinutes: v })} />
        </div>
        <Switch
          checked={s.durations.on}
          onChange={(on) => notifyPlan(toast, setDurationAuto(on), on ? '걸리는 시간 보정을 켜고 남은 일정을 다시 짰어요' : '보정을 끄고 적은 시간 그대로 다시 짰어요', on ? '걸리는 시간 보정을 켰어요' : '걸리는 시간 보정을 껐어요')}
          label="걸리는 시간 자동 보정"
          sub={
            durByType.length
              ? `지금 보정: ${durByType.join(' · ')} (끝낸 할 일 ${durCount}개 기준)`
              : `끝낸 할 일 ${durCount}개 기록 · 같은 종류 ${MIN_TYPE_SAMPLES}개부터 실제 걸린 시간으로 일정을 잡아요`
          }
          onText="켬"
          offText="끔"
        />
      </section>

      <section className="card stack" aria-label="캘린더 연결">
        <div className="row between">
          <h2 className="t-h2">캘린더 연결</h2>
          <button type="button" className="btn small primary" onClick={() => setCalOpen(true)}>
            {s.calendars.length ? '관리' : '연결하기'}
          </button>
        </div>
        {s.calendars.length === 0 ? (
          <span className="t-label">구글 캘린더나 .ics 파일을 연결하면 일정이 자동으로 들어와요.</span>
        ) : (
          s.calendars.map((c) => (
            <span key={c.id} className={`t-label ${c.error ? 'miss' : ''}`}>
              {c.name} · {c.count}개 · {koreanDate(c.lastSync)} {formatHm(c.lastSync)}
              {c.error ? ` · ${c.error}` : ''}
            </span>
          ))
        )}
      </section>
      {calOpen && <CalendarSheet s={s} onClose={() => setCalOpen(false)} toast={toast} />}

      <section className="card stack" aria-label="알람과 알림">
        <h2 className="t-h2">알람과 알림</h2>
        <p className="t-label" style={{ margin: 0 }}>
          지금 일정을 알림에 띄워 두고, 일정이 시작됐는데 기록이 없으면 알려요. 알림의 '기록하기'로 바로 기록돼요. 로컬 버전은 브라우저가 켜져 있는 동안 알리고, 휴대폰 기본 알람 연동은 앱 버전에서 해요.
        </p>
        {permState === 'granted' && s.notify.enabled ? (
          <>
            <Switch checked={s.notify.sticky} onChange={(v) => setNotify({ sticky: v })} label="지금 일정 알림 띄워 두기" sub="알림 목록에 지금·다음 일정을 계속 보여 줘요" onText="켬" offText="끔" />
            <Switch checked={s.notify.remind} onChange={(v) => setNotify({ remind: v })} label="기록할 때 알리기" sub="일정이 시작됐는데 기록이 없으면 소리·진동으로 알려요" onText="켬" offText="끔" />
            <span className="t-label">
              푸시 토큰: {s.notify.token ? `${s.notify.token} (앱 버전 서버에 등록해 앱이 닫혀 있어도 알려요)` : '서버 키가 없어 만들지 않았어요. 화면이 열려 있거나 브라우저가 켜져 있는 동안 알려요'}
            </span>
          </>
        ) : (
          <button
            type="button"
            className="btn primary"
            disabled={permState === 'unsupported'}
            onClick={async () => {
              const r = await enableNotifications();
              setPermState(r.permission);
              setNotify({ enabled: r.permission === 'granted', ...(r.token ? { token: r.token, tokenAt: now() } : {}) });
              track('notify_enable', String(r.permission));
              toast(r.text);
            }}
          >
            <Icon name="bell" size={18} /> 알림 켜기
          </button>
        )}
        {permState === 'denied' && <span className="t-label miss">브라우저 설정에서 이 사이트 알림이 막혀 있어요. 허용한 뒤 다시 눌러 주세요</span>}
        {permState === 'unsupported' && <span className="t-label">이 브라우저는 알림을 지원하지 않아요. 앱 안 일정 체크 팝업으로 알려 드려요</span>}
        <button type="button" className="btn" style={{ alignSelf: 'flex-start' }} onClick={testRing}>
          알람 미리 울려보기
        </button>
      </section>

      <MetricsCard s={s} now={now()} toast={toast} />

      <section className="card stack" aria-label="의견과 동의">
        <h2 className="t-h2">의견과 동의</h2>
        <div className="row wrap" style={{ gap: 8 }}>
          <button type="button" className="btn" onClick={() => setReporting(true)}>
            불편 신고·의견 남기기
          </button>
          <button type="button" className="btn" onClick={() => setConsentOpen(true)}>
            동의 다시 보기
          </button>
        </div>
        <span className="t-label">
          {s.consent ? `생활 기록 동의 ${s.consent.health ? '함' : '안 함'} · 베타 지표 내보내기 ${s.consent.metrics ? '동의' : '동의 안 함'} · ${koreanDate(s.consent.at)}` : '예시 데이터예요'}
          {s.feedback.reports.length ? ` · 남긴 의견 ${s.feedback.reports.length}건` : ''}
        </span>
        {confirmWithdraw ? (
          <div className="row" style={{ gap: 8 }}>
            <button type="button" className="btn danger" onClick={() => resetAll()}>
              동의 거두고 기록 지우기
            </button>
            <button type="button" className="btn" onClick={() => setConfirmWithdraw(false)}>
              취소
            </button>
          </div>
        ) : (
          <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => setConfirmWithdraw(true)}>
            생활 기록 동의 거두기
          </button>
        )}
      </section>
      {reporting && <ReportSheet page="설정" onClose={() => setReporting(false)} toast={toast} />}
      {consentOpen && (
        <div className="consent-overlay">
          <ConsentPanel s={s} title="동의 다시 보기" onBack={() => setConsentOpen(false)} onDone={() => { setConsentOpen(false); toast('동의를 바꿨어요'); }} />
        </div>
      )}

      <section className="card stack" aria-label="화면">
        <h2 className="t-h2">화면</h2>
        <Segmented<Theme>
          label="테마"
          value={theme}
          onChange={setTheme}
          options={[
            { value: 'dark', label: '나이트' },
            { value: 'light', label: '밝게' },
            { value: 'pastel', label: '파스텔' },
            { value: 'system', label: '기기' },
          ]}
        />
        {theme === 'pastel' && <p className="t-label muted">파스텔 다이어리: 크림 바탕에 둥근 글씨, 스티커처럼 테두리를 둘렀어요</p>}
      </section>

      <section className="card stack" aria-label="데이터">
        <h2 className="t-h2">데이터</h2>
        <p className="t-label" style={{ margin: 0 }}>
          기록은 이 브라우저에만 저장돼요. 다른 기기로 옮기거나 앱 버전으로 넘길 때 백업 파일을 쓰세요.
        </p>
        <div className="row wrap" style={{ gap: 8 }}>
          <button type="button" className="btn" onClick={exportData}>
            백업 내보내기
          </button>
          <button type="button" className="btn" onClick={() => fileRef.current?.click()}>
            백업 불러오기
          </button>
          <button type="button" className="btn" onClick={() => replaceState(demoState(now()))}>
            예시 데이터 넣기
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="application/json,.json"
            hidden
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void importData(f);
              e.target.value = '';
            }}
          />
        </div>
        {msg && <span className="t-label">{msg}</span>}
        {kept.length > 0 && (
          <div className="stack" style={{ gap: 6 }} aria-label="보관한 이전 데이터">
            <span className="t-label">보관한 이전 데이터 · 최근 3개까지</span>
            {kept.map((k) => (
              <div key={k.key} className="row between">
                <span className="t-label">
                  {koreanDate(k.at)} {formatHm(k.at)} · {k.reason === 'broken' ? '읽지 못한 데이터' : '불러오기 전 기록'}
                </span>
                <span className="row" style={{ gap: 6 }}>
                  <button
                    type="button"
                    className="btn small"
                    onClick={() => {
                      const text = localStorage.getItem(k.key) ?? '';
                      const a = document.createElement('a');
                      a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
                      a.download = `dayset-kept-${k.at.getTime()}.json`;
                      a.click();
                      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
                    }}
                  >
                    내려받기
                  </button>
                  {k.reason === 'before-import' && (
                    <button
                      type="button"
                      className="btn small"
                      onClick={() => {
                        try {
                          const prev = deserialize(localStorage.getItem(k.key) ?? '');
                          keepCopy(serialize(s), 'before-import');
                          replaceState(prev);
                          setMsg('불러오기 전 기록으로 되돌렸어요');
                        } catch (e) {
                          setMsg(`되돌리지 못했어요: ${(e as Error).message}`);
                        }
                      }}
                    >
                      되돌리기
                    </button>
                  )}
                </span>
              </div>
            ))}
          </div>
        )}
        {confirmReset ? (
          <div className="row" style={{ gap: 8 }}>
            <button type="button" className="btn danger" onClick={() => resetAll()}>
              정말 모두 지우기
            </button>
            <button type="button" className="btn" onClick={() => setConfirmReset(false)}>
              취소
            </button>
          </div>
        ) : (
          <button type="button" className="btn danger" style={{ alignSelf: 'flex-start' }} onClick={() => setConfirmReset(true)}>
            모든 기록 지우기
          </button>
        )}
      </section>

      <section className="card stack" aria-label="시험용 시각">
        <h2 className="t-h2">시험용 시각</h2>
        <p className="t-label" style={{ margin: 0 }}>
          알람·저녁 확인 흐름을 미리 보려면 앱 안의 시각을 옮겨요. 기록도 이 시각으로 남으니 시험 뒤 되돌려 주세요.
        </p>
        <div className="row" style={{ gap: 8, alignItems: 'flex-end' }}>
          <label className="field grow">
            <span>앱 시각</span>
            <input className="input num" type="datetime-local" value={clockValue} onChange={(e) => setClockValue(e.target.value)} />
          </label>
          <button
            type="button"
            className="btn"
            onClick={() => {
              const d = new Date(clockValue);
              if (!Number.isNaN(d.getTime())) setClockOffset(d.getTime() - Date.now());
            }}
          >
            적용
          </button>
        </div>
        {offset !== 0 && (
          <button type="button" className="btn small" style={{ alignSelf: 'flex-start' }} onClick={() => setClockOffset(0)}>
            실제 시각으로 되돌리기
          </button>
        )}
      </section>

      <p className="t-label" style={{ textAlign: 'center', margin: '8px 0 0' }}>
        DaySet 0.2.0 · 로컬 버전 · 서버 없이 기기 안에서 동작해요
      </p>
    </div>
  );
}
