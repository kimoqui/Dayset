import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ACTIVITY_LABEL, type Activity, dateKey } from '../engine/models';
import { canUndo, canUndoPlan, dueAlarms, ensureDay, markAsked, markNudged, markOpen, now, type Ring, skipCheck, tap, track, undoPlanChange, undoTap, useAppState } from '../app/store';
import { checkKey, nowCheck } from '../app/nowCheck';
import { NowDock } from './NowDock';
import { ConsentPanel } from './Preview';
import { clearNowNotification, listenNotifyActions, noticeFor, permission, showNowNotification } from './notify';
import { currentLog } from '../app/derive';
import { AlarmOverlay } from './AlarmOverlay';
import { haptic, useSwipeTabs } from './motion';
import { Celebrate } from './Social';
import { computeStreak, reachedMilestone } from '../app/streak';
import { ObsPopup, type ObsPopupKind } from './ObsPopup';
import { Icon, type IconName } from './kit';
import { Evening } from './screens/Evening';
import { Home } from './screens/Home';
import { Onboarding } from './screens/Onboarding';
import { Review } from './screens/Review';
import { SocialTab } from './screens/SocialTab';
import { Demo } from './screens/Demo';
import { Schedule } from './screens/Schedule';
import { Settings, type Theme } from './screens/Settings';
import { Stats } from './screens/Stats';
import { Tasks } from './screens/Tasks';
import { useCalendarAutoSync } from './CalendarConnect';
import { loadIssue } from '../app/state';

type Tab = 'home' | 'schedule' | 'tasks' | 'stats' | 'social' | 'settings';
type Page = Tab | 'evening' | 'review' | 'demo';

const TABS: { id: Tab; label: string; icon: IconName }[] = [
  { id: 'home', label: '홈', icon: 'home' },
  { id: 'schedule', label: '일정', icon: 'calendar' },
  { id: 'tasks', label: '할 일', icon: 'tasks' },
  { id: 'stats', label: '기록', icon: 'stats' },
  { id: 'social', label: '소셜', icon: 'users' },
  { id: 'settings', label: '설정', icon: 'settings' },
];

const THEME_KEY = 'dayset:theme';

function readTheme(): Theme {
  try {
    const v = localStorage.getItem(THEME_KEY);
    if (v === 'light' || v === 'dark' || v === 'system') return v;
  } catch {
    // 저장소 없음
  }
  return 'dark';
}

function notify(title: string, body: string): void {
  try {
    if (typeof Notification !== 'undefined' && Notification.permission === 'granted') new Notification(title, { body });
  } catch {
    // 알림을 지원하지 않는 환경
  }
}

/** 화면이 켜져 있는 동안 15초마다 시각을 갱신한다. */
function useNow(): Date {
  const [t, setT] = useState(now);
  useEffect(() => {
    const id = window.setInterval(() => setT(now()), 15000);
    const onVis = () => document.visibilityState === 'visible' && setT(now());
    document.addEventListener('visibilitychange', onVis);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', onVis);
    };
  }, []);
  return t;
}

export function App() {
  const s = useAppState();
  const tick = useNow();
  // 상태가 바뀔 때도 지금 시각으로 다시 계산한다(시험용 시각 이동 포함).
  const [nowValue, setNowValue] = useState(now);
  useEffect(() => setNowValue(now()), [s, tick]);

  const [page, setPage] = useState<Page>('home');
  const [ring, setRing] = useState<{ ring: Ring; test?: boolean } | null>(null);
  const [toast, setToast] = useState<{ text: string; undo: boolean | 'plan'; id: number } | null>(null);
  const [theme, setThemeState] = useState<Theme>(readTheme);
  const toastTimer = useRef<number | undefined>(undefined);
  const [popup, setPopup] = useState<ObsPopupKind | null>(null);
  const [celebrate, setCelebrate] = useState<number | null>(null);
  const streakInfo = useMemo(() => (s.onboarded ? computeStreak(s, nowValue) : null), [s, nowValue]);

  /** 지금 화면에 보이는 테마(기기 설정이면 기기 모드를 따른다). */
  const resolvedTheme = (): 'dark' | 'light' => {
    if (theme !== 'system') return theme;
    try {
      return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    } catch {
      return 'dark';
    }
  };
  const toggleTheme = () => setThemeState(resolvedTheme() === 'dark' ? 'light' : 'dark');

  useEffect(() => {
    const root = document.documentElement;
    root.setAttribute('data-theme', theme);
    try {
      localStorage.setItem(THEME_KEY, theme);
    } catch {
      // 저장소 없음
    }
  }, [theme]);

  const showToast = useCallback((text: string, undo: boolean | 'plan' = false) => {
    window.clearTimeout(toastTimer.current);
    setToast({ text, undo, id: Date.now() });
    toastTimer.current = window.setTimeout(() => setToast(null), undo === 'plan' ? 6500 : undo ? 5000 : 4000);
  }, []);

  useCalendarAutoSync(s.onboarded, showToast);

  // 베타 지표: 오늘 연 날을 남긴다(하루 한 번).
  const todayKey = dateKey(nowValue);
  useEffect(() => {
    if (s.onboarded) markOpen(nowValue);
  }, [s.onboarded, todayKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // 일정 체크: 지금 일정과 지금 기록을 맞춰 본다.
  const check = useMemo(() => nowCheck(s, nowValue), [s, nowValue]);

  /** 일정 체크 팝업·알림 버튼에서 기록한다. */
  const recordFrom = useCallback(
    (a: Activity, via: 'popup' | 'notify') => {
      const r = tap(a);
      haptic(12);
      track(via === 'popup' ? 'check_record' : 'notify_record', a);
      showToast(r.changed ? `${ACTIVITY_LABEL[a]} 시작을 기록했어요` : `이미 ${ACTIVITY_LABEL[a]} 기록 중이에요`, r.changed);
    },
    [showToast],
  );

  // 알림 버튼(기록하기 · 지금은 안 해요)
  useEffect(
    () =>
      listenNotifyActions((x) => {
        if (x.action === 'record' && x.activity) recordFrom(x.activity as Activity, 'notify');
        if (x.action === 'skip' && x.skipId) skipCheck(x.skipId);
      }),
    [recordFrom],
  );

  // '지금 일정' 알림을 띄워 두고, 기록할 때가 되면 알린다. 같은 상태면 다시 띄우지 않는다.
  const lastNotice = useRef('');
  useEffect(() => {
    if (!s.onboarded || !s.notify.enabled || permission() !== 'granted') return;
    const alertNow = (check.kind === 'due' || check.kind === 'over') && !check.skipped;
    const key = `${checkKey(check)}|${check.skipped}|${check.current}|${s.notify.sticky}|${s.notify.remind}`;
    if (key === lastNotice.current) return;
    lastNotice.current = key;
    const n = noticeFor(check);
    if (!n || (alertNow ? !s.notify.remind && !s.notify.sticky : !s.notify.sticky)) {
      void clearNowNotification();
      return;
    }
    void showNowNotification(alertNow && !s.notify.remind ? { ...n, silent: true } : n, s.notify.sticky || alertNow);
  }, [check, s.onboarded, s.notify]);

  // 하루 시작 처리와 알람 확인
  useEffect(() => {
    if (!s.onboarded) return;
    ensureDay(nowValue);
    if (ring) return;
    const due = dueAlarms(nowValue);
    if (due.ring) {
      setRing({ ring: due.ring });
      notify(due.ring.kind === 'wake' ? '기상 알람' : '취침 시간이에요', '앱을 열어 알람을 꺼 주세요');
    }
    if (due.nudges.length) {
      for (const n of due.nudges) notify(n.title, n.body);
      showToast(`${due.nudges[0].title} · ${due.nudges[0].body}`);
      markNudged(due.nudges.map((n) => n.key));
    }
  }, [s.onboarded, nowValue, ring, showToast]); // eslint-disable-line react-hooks/exhaustive-deps

  // 관찰 준비일(1일차 전날) 안내: 처음 한 번, 밤 10시가 넘으면 한 번 더. 10초 뒤 저절로 닫힌다.
  useEffect(() => {
    const obs = s.observation;
    if (!obs || obs.phase !== 'recording' || popup || ring) return;
    if (dateKey(nowValue) >= obs.day1) return;
    if (!s.asked.obsIntroAt) {
      setPopup('intro');
      markAsked({ obsIntroAt: nowValue });
      return;
    }
    const h = nowValue.getHours();
    const late = h >= 22 || h < 3;
    const sinceIntro = nowValue.getTime() - s.asked.obsIntroAt.getTime();
    if (late && !s.asked.obsLate && sinceIntro >= 30 * 60000 && currentLog(s)?.activity !== 'sleep') {
      setPopup('late');
      markAsked({ obsLate: true });
    }
  }, [s, nowValue, popup, ring]);

  const onTap = (a: Activity) => {
    const r = tap(a);
    if (!r.changed) return;
    haptic(10);
    showToast(r.merged ? `${ACTIVITY_LABEL[a]} 기록에 이어 붙였어요` : `${ACTIVITY_LABEL[a]} 시작을 기록했어요`, true);
  };

  // 기념일(3·7·14·30일…) 축하: 그날 처음 도달했을 때 한 번
  useEffect(() => {
    if (!streakInfo || celebrate || ring || popup) return;
    const todayKey = dateKey(nowValue);
    const hit = reachedMilestone(streakInfo, todayKey, s.asked.celebrated);
    if (hit) {
      setCelebrate(hit);
      haptic(20);
      markAsked({ celebrated: `${hit}@${todayKey}` });
    }
  }, [streakInfo, celebrate, ring, popup, nowValue, s.asked.celebrated]);

  const tab: Tab | null = page === 'evening' || page === 'review' || page === 'demo' ? null : page;
  const swipe = useSwipeTabs<Tab>({ tabs: TABS.map((t) => t.id), current: tab, onChange: setPage });
  /** 탭이면 방향 모션으로, 그 밖의 화면(저녁 확인·내 하루 보기)은 밀려 들어오는 모션으로 연다. */
  const open = (to: Page) => {
    if (tab && TABS.some((t) => t.id === to)) swipe.go(to as Tab);
    else {
      setPage(to);
      window.scrollTo(0, 0);
    }
  };

  // 동의 없이 쓰던 기록(이전 버전)이면 먼저 동의를 받는다. 예시 데이터는 묻지 않는다.
  if (s.onboarded && !s.demo && !s.consent?.health) {
    return (
      <div className="app">
        <ConsentPanel s={s} title="계속 쓰려면 동의가 필요해요" onDone={() => showToast('동의를 남겼어요')} />
      </div>
    );
  }

  if (!s.onboarded) {
    return (
      <div className="app">
        {/* 저장된 기록이 깨져 새로 시작한 경우: 깨진 데이터는 지우지 않고 보관해 둠 */}
        {loadIssue === 'broken' && (
          <div className="banner" role="status" style={{ margin: '12px 16px 0' }}>
            저장된 기록을 읽지 못해 새로 시작했어요. 이전 데이터는 지우지 않고 보관했어요(시작한 뒤 설정 → 데이터에서 내려받기).
          </div>
        )}
        <Onboarding />
      </div>
    );
  }


  const showDock = !!tab && !ring && !popup && !celebrate && check.kind !== 'none';

  return (
    <div className={`app ${showDock ? 'has-dock' : ''}`}>
      <div className="pager" ref={swipe.ref}>
      <div key={tab ? 'tabs' : page} className={tab ? 'page' : 'page push'}>
      {page === 'home' && (
        <Home s={s} now={nowValue} onTap={onTap} go={open} theme={resolvedTheme()} toggleTheme={toggleTheme} showGuide={() => setPopup('intro')} streak={streakInfo?.current ?? 0} toast={showToast} />
      )}
      {page === 'schedule' && <Schedule s={s} now={nowValue} toast={showToast} openDemo={() => open('demo')} />}
      {page === 'demo' && <Demo s={s} now={nowValue} onBack={() => setPage('schedule')} />}
      {page === 'tasks' && <Tasks s={s} now={nowValue} toast={showToast} />}
      {page === 'stats' && <Stats s={s} now={nowValue} openEvening={() => open('evening')} toast={showToast} />}
      {page === 'review' && s.observation && (
        <Review s={s} now={nowValue} onBack={() => setPage('home')} onDone={() => { setPage('home'); showToast('일정을 만들었어요. 설정에서 언제든 바꿀 수 있어요'); }} />
      )}
      {page === 'evening' && <Evening key={dateKey(nowValue)} s={s} now={nowValue} onBack={() => setPage('home')} />}
      {page === 'social' && streakInfo && <SocialTab s={s} info={streakInfo} toast={showToast} />}
      {page === 'settings' && (
        <Settings
          s={s}
          theme={theme}
          setTheme={setThemeState}
          openDemo={() => open('demo')}
          testRing={() => setRing({ ring: { kind: 'wake', key: 'test', at: now() }, test: true })}
          toast={showToast}
        />
      )}

      </div>
      </div>

      {showDock && <NowDock check={check} onRecord={recordFrom} onSkip={skipCheck} />}

      {tab && (
        <nav className="tabbar" aria-label="화면 이동">
          {TABS.map((t) => (
            <button key={t.id} type="button" aria-current={tab === t.id ? 'page' : undefined} onClick={() => swipe.go(t.id)}>
              <span className="ind">
                <Icon name={t.icon} size={22} />
              </span>
              {t.label}
            </button>
          ))}
        </nav>
      )}

      {toast && (
        <div className="toast" role="status" key={toast.id} style={tab ? undefined : { bottom: 24 }}>
          <span className="grow">{toast.text}</span>
          {toast.undo && (
            <button
              type="button"
              onClick={() => {
                if (toast.undo === 'plan' ? canUndoPlan() && undoPlanChange() : canUndo() && undoTap()) showToast('되돌렸어요');
                else setToast(null);
              }}
            >
              되돌리기
            </button>
          )}
        </div>
      )}

      {popup && (
        <ObsPopup
          kind={popup}
          onClose={() => setPopup(null)}
          onSleep={() => {
            setPopup(null);
            onTap('sleep');
          }}
        />
      )}

      {celebrate && streakInfo && (
        <Celebrate s={s} info={streakInfo} days={celebrate} onClose={() => setCelebrate(null)} toast={showToast} />
      )}

      {ring && <AlarmOverlay ring={ring.ring} test={ring.test} onDone={() => setRing(null)} />}
    </div>
  );
}
