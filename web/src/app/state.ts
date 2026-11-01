// 기기에 저장하는 앱 상태. 서버 없이 브라우저 저장소(localStorage)에만 둔다.
// 앱으로 옮길 때는 같은 구조를 기기 DB(drift/SQLite) 테이블로 나눈다.

import type { CoachingSuggestion, CoachRecord } from '../engine/coaching';
import type { CorrectionPlan, WeeklyDecision } from '../engine/correction';
import {
  type Activity,
  type ActivityLog,
  DEFAULT_SETTINGS,
  type FixedEvent,
  type HabitGoals,
  type MissReason,
  type PersonalSettings,
  type TaskItem,
} from '../engine/models';
import type { DayPlan } from '../engine/scheduleBuilder';
import type { Friend } from './social';
import type { LearningLog } from './priorityModel';
import type { NearbyState } from './nearby';
import type { DurationLearning } from './duration';

export interface WakeRecord {
  day: string;
  at: Date;
  snoozes: number;
  source: 'alarm' | 'button';
}

export interface MissMark {
  day: string;
  blockId: string;
  activity: Activity;
  reason: MissReason;
  at: Date;
}

export interface SkipMark {
  day: string;
  blockId: string;
}

export interface TaskCredit {
  day: string;
  blockId: string;
  taskId: string;
  minutes: number;
}

export interface DayOverride {
  dinnerShift?: number;
  notes?: string[];
}

/** 저장한 하루 일정. 그 날이 시작되면(또는 전날 밤 확정하면) 고정한다. */
export interface StoredPlan extends DayPlan {
  inputsVersion: number;
  regen: number;
}

export interface InboxItem {
  id: string;
  day: string;
  createdAt: Date;
  kind: 'coach' | 'info';
  suggestion?: CoachingSuggestion;
  message: string;
  status: 'pending' | 'accepted' | 'kept' | 'seen';
  resultText?: string;
  /** 승인 뒤 열 화면(예: 설정). */
  action?: 'settings';
}

export interface AlarmState {
  snoozes: number;
  snoozeUntil?: Date | null;
  done?: boolean;
}

export interface CorrectionState {
  plan: CorrectionPlan;
  lastUpdateWeek: string;
  holdNext: boolean;
  history: { week: string; decision: WeeklyDecision; rate: number | null; target: number }[];
}

/**
 * 2일 관찰: 1일차는 설정 없이 기록만 하고(recording), 그 기록을 보며 바꿀 것만 고친 뒤(review 끝),
 * 2일차에 첫 일정을 써 본다(trial). 2일차 저녁 확인에서 어긋난 습관만 다시 묻고 끝낸다(done).
 */
export interface Observation {
  phase: 'recording' | 'trial' | 'done';
  /** 기록하는 날(1일차). 오후 3시 이후에 시작하면 다음 날이 1일차다. */
  day1: string;
  /** 첫 일정을 써 보는 날(2일차). */
  day2?: string;
  startedAt: Date;
}

/** 가져온 외부 캘린더. 다시 가져오면 그 캘린더의 일정을 통째로 바꾼다. */
export interface CalendarSource {
  id: string;
  kind: 'ics' | 'google';
  name: string;
  lastSync: Date;
  count: number;
  /** 마지막 동기화가 실패했을 때 이유(이전에 가져온 일정은 그대로 둔다). */
  error?: string;
  /** 구글 연결이 만료돼 다시 연결해야 하는지. */
  needsAuth?: boolean;
}

/** 처음 접속할 때 고르는 목표. 1일차 기록을 본 뒤 일정을 짤 때 기본값으로 쓴다. */
export type GoalFocus = 'wake' | 'sleep' | 'breakfast' | 'exercise' | 'tasks';
export interface GoalIntent {
  focus: GoalFocus[];
  wake: number;
  sleepMinutes: number;
  exerciseMinutes: number;
  /** '기타'에 적은 글에서 읽은 운동 이름(예: 달리기)과 시각(자정 기준 분). */
  exerciseTitle?: string;
  exerciseStart?: number;
  /** '기타'에 적은 글(이 기기에만 둔다, 지표로 내보내지 않는다). */
  note?: string;
  setAt: Date;
}

/** 건강 기록 수집·이용 동의(필수)와 베타 지표 내보내기 동의(선택). */
export interface Consent {
  health: boolean;
  metrics: boolean;
  at: Date;
  version: number;
}

/** 알림: 권한을 받으면 지금 일정을 알림에 띄워 두고, 기록할 때를 알린다. */
export interface NotifyPrefs {
  enabled: boolean;
  /** 지금 일정을 알림에 계속 띄워 두기. */
  sticky: boolean;
  /** 일정이 시작됐는데 기록이 없으면 알리기. */
  remind: boolean;
  /** 푸시 토큰(구독 주소의 지문). 앱 버전 서버에 등록할 때 쓴다. */
  token?: string;
  tokenAt?: Date;
}

export interface SurveyAnswer {
  key: 'd7' | 'd28';
  answer: 'very' | 'some' | 'not' | 'stopped';
  best?: string;
  worst?: string;
  at: Date;
}
export interface FeedbackReport {
  at: Date;
  kind: 'bug' | 'hard' | 'idea';
  text: string;
  page: string;
}

/** 베타 지표: 연 날과 몇 가지 행동만 남긴다(기록 내용·이름은 남기지 않는다). */
export interface MetricsLog {
  installAt: Date;
  opens: string[];
  events: { at: Date; k: string; v?: string }[];
}

export interface AppState {
  version: 1;
  observation: Observation | null;
  /** 필요한 순간에 한 번만 묻는 질문을 이미 물었는지. */
  asked: { travel?: boolean; obsIntroAt?: Date; obsLate?: boolean; celebrated?: string };
  /** 공유 카드·친구 순위에 쓰는 이름. id는 기기마다 하나. */
  profile: { id: string; name: string };
  friends: Friend[];
  /** 할 일 우선순위 학습 기록. */
  learning: LearningLog;
  /** 근처 익명 보드. */
  nearby: NearbyState;
  /** 걸리는 시간 자동 보정(예상 vs 실제). */
  durations: DurationLearning;
  /** 가져온 캘린더(구글 연결, .ics 파일). */
  calendars: CalendarSource[];
  /** 구글 OAuth 클라이언트 ID(빌드에 넣지 않았을 때 설정에서 넣는다). */
  googleClientId: string;
  intent: GoalIntent | null;
  consent: Consent | null;
  notify: NotifyPrefs;
  /** 일정 체크 팝업에서 '지금은 안 해요'로 넘긴 일정 조각. */
  checkSkips: string[];
  feedback: { surveys: SurveyAnswer[]; reports: FeedbackReport[]; surveyLater?: string };
  metrics: MetricsLog;
  onboarded: boolean;
  demo: boolean;
  goals: HabitGoals;
  settings: PersonalSettings;
  correction: CorrectionState | null;
  events: FixedEvent[];
  tasks: TaskItem[];
  logs: ActivityLog[];
  wakes: WakeRecord[];
  plans: Record<string, StoredPlan>;
  overrides: Record<string, DayOverride>;
  misses: MissMark[];
  skips: SkipMark[];
  restDays: string[];
  credits: TaskCredit[];
  coachHistory: CoachRecord[];
  inbox: InboxItem[];
  alarms: Record<string, AlarmState>;
  /** 코칭 R6로 켠 습관 미리 알림(몇 분 전). */
  reminders: Partial<Record<Activity, number>>;
  eveningDone: string[];
  /** 할 일·캘린더·설정이 바뀔 때마다 올린다. 저장한 일정이 오래됐는지 판단한다. */
  inputsVersion: number;
}

export const DEFAULT_GOALS: HabitGoals = {
  wake: 7 * 60,
  sleepMinutes: 420,
  meals: [
    { title: '아침 식사', activity: 'meal', start: 7 * 60 + 30, minutes: 30 },
    { title: '점심 식사', activity: 'meal', start: 12 * 60, minutes: 60 },
    { title: '저녁 식사', activity: 'meal', start: 18 * 60 + 30, minutes: 60 },
  ],
  exercise: { title: '운동', activity: 'exercise', start: 20 * 60 + 30, minutes: 30 },
};

export function initialState(): AppState {
  return {
    version: 1,
    observation: null,
    asked: {},
    profile: { id: `u-${Math.random().toString(36).slice(2, 10)}`, name: '' },
    friends: [],
    learning: { reorders: [], completions: [] },
    nearby: { on: false, people: [] },
    durations: { on: true, samples: [] },
    calendars: [],
    googleClientId: '',
    intent: null,
    consent: null,
    notify: { enabled: false, sticky: true, remind: true },
    checkSkips: [],
    feedback: { surveys: [], reports: [] },
    metrics: { installAt: new Date(), opens: [], events: [] },
    onboarded: false,
    demo: false,
    goals: structuredClone(DEFAULT_GOALS),
    settings: { ...DEFAULT_SETTINGS },
    correction: null,
    events: [],
    tasks: [],
    logs: [],
    wakes: [],
    plans: {},
    overrides: {},
    misses: [],
    skips: [],
    restDays: [],
    credits: [],
    coachHistory: [],
    inbox: [],
    alarms: {},
    reminders: {},
    eveningDone: [],
    inputsVersion: 1,
  };
}

// ---------------------------------------------------------------------------
// 저장·불러오기
// ---------------------------------------------------------------------------

export const STORAGE_KEY = 'dayset:v1';
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/;

export function reviveDates(_key: string, value: unknown): unknown {
  return typeof value === 'string' && ISO.test(value) ? new Date(value) : value;
}

export function serialize(s: AppState): string {
  return JSON.stringify(s);
}

export function deserialize(text: string): AppState {
  const parsed = JSON.parse(text, reviveDates) as Partial<AppState>;
  if (parsed.version !== 1) throw new Error('지원하지 않는 데이터 형식이에요');
  // 새 필드가 생겨도 예전 데이터가 열리도록 기본값 위에 덮는다.
  const base = initialState();
  return {
    ...base,
    ...parsed,
    settings: { ...base.settings, ...(parsed.settings ?? {}) },
  } as AppState;
}

/** 시작할 때 생긴 문제. 'broken'이면 깨진 데이터를 지우지 않고 BROKEN_PREFIX 키로 따로 보관했다. */
export let loadIssue: 'broken' | null = null;
export const KEPT_PREFIX = 'dayset:kept:';
export type KeptReason = 'broken' | 'before-import';

/** 지금 데이터를 지우지 않고 따로 보관한다(깨진 데이터, 백업을 불러오기 직전 데이터). */
export function keepCopy(text: string, reason: KeptReason, at = Date.now()): boolean {
  try {
    localStorage.setItem(`${KEPT_PREFIX}${at}:${reason}`, text);
    // 최근 3개만 남긴다.
    keptBackups().slice(3).forEach((k) => localStorage.removeItem(k.key));
    return true;
  } catch {
    return false;
  }
}

export function loadState(): AppState {
  let text: string | null = null;
  try {
    text = localStorage.getItem(STORAGE_KEY);
  } catch {
    // 저장소를 못 쓰는 환경(사생활 보호 모드 등)에서는 새 상태로 시작한다.
    return initialState();
  }
  if (!text) return initialState();
  try {
    return deserialize(text);
  } catch {
    // 데이터가 깨졌거나 형식이 다르면 지우지 않고 보관한 뒤 새로 시작한다.
    if (keepCopy(text, 'broken')) {
      try {
        localStorage.removeItem(STORAGE_KEY);
      } catch {
        keepBroken = true;
      }
    } else {
      // 보관할 공간도 없으면 원래 키를 그대로 둔다(덮어쓰지 않도록 아래 saveState가 막는다).
      keepBroken = true;
    }
    loadIssue = 'broken';
    return initialState();
  }
}

/** 깨진 데이터를 보관하지 못했을 때 원래 키를 덮어쓰지 않는다. */
let keepBroken = false;

export type SaveResult = 'ok' | 'quota' | 'blocked';

export function saveState(s: AppState): SaveResult {
  if (keepBroken) return 'blocked';
  try {
    localStorage.setItem(STORAGE_KEY, serialize(s));
    return 'ok';
  } catch (e) {
    const name = (e as { name?: string })?.name ?? '';
    return /quota/i.test(name) || (e as { code?: number })?.code === 22 ? 'quota' : 'blocked';
  }
}

/** 보관해 둔 이전 데이터 목록(최신 순). */
export function keptBackups(): { key: string; at: Date; reason: KeptReason; size: number }[] {
  try {
    return Object.keys(localStorage)
      .filter((k) => k.startsWith(KEPT_PREFIX))
      .map((k) => {
        const [at, reason] = k.slice(KEPT_PREFIX.length).split(':');
        return { key: k, at: new Date(Number(at)), reason: (reason as KeptReason) ?? 'broken', size: localStorage.getItem(k)?.length ?? 0 };
      })
      .sort((a, b) => b.at.getTime() - a.at.getTime());
  } catch {
    return [];
  }
}
