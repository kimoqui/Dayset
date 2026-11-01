// DaySet 도메인 모델.
//
// 화면·저장소와 무관한 순수 TypeScript 코드다. Flutter 버전(lib/core/model)과
// 같은 구조를 유지해, 이후 앱으로 옮길 때 그대로 대응시킬 수 있다.

/** '지금' 버튼과 기록에 쓰는 다섯 가지 상태. */
export type Activity = 'sleep' | 'meal' | 'work' | 'exercise' | 'rest';

export const ACTIVITIES: Activity[] = ['sleep', 'meal', 'work', 'exercise', 'rest'];

export const ACTIVITY_LABEL: Record<Activity, string> = {
  sleep: '수면',
  meal: '식사',
  work: '업무',
  exercise: '운동',
  rest: '휴식',
};

/** 기록이 어디서 왔는지. 추정 기록은 달성률 계산에서 뺀다. */
export type LogSource = 'alarm' | 'button' | 'widget' | 'shortcut' | 'health' | 'evening' | 'estimate';

export const SOURCE_LABEL: Record<LogSource, string> = {
  alarm: '알람',
  button: '버튼',
  widget: '위젯',
  shortcut: '단축어',
  health: '건강',
  evening: '확인',
  estimate: '추정',
};

/** 하루 일정 블록의 종류. */
export type BlockKind = 'habit' | 'fixed' | 'task' | 'buffer';

export type BlockStatus = 'planned' | 'active' | 'done' | 'skipped';

export type TaskPriority = 'high' | 'normal' | 'low';

export const PRIORITY_ORDER: Record<TaskPriority, number> = { high: 0, normal: 1, low: 2 };
export const PRIORITY_LABEL: Record<TaskPriority, string> = { high: '높음', normal: '보통', low: '낮음' };

export type TaskType = 'work' | 'assignment' | 'homework' | 'personal';

/** 소요시간을 모를 때 쓰는 기본값(엔진·규칙 명세 6번). */
export const TASK_TYPE: Record<TaskType, { label: string; defaultMinutes: number }> = {
  work: { label: '업무', defaultMinutes: 60 },
  assignment: { label: '과제', defaultMinutes: 90 },
  homework: { label: '숙제', defaultMinutes: 45 },
  personal: { label: '개인', defaultMinutes: 30 },
};

/** 실패 이유(9. 경험 보완 · 엔진 명세 7번). */
export type MissReason = 'tired' | 'forgot' | 'conflict' | 'unwilling' | 'other';

export const MISS_REASONS: MissReason[] = ['tired', 'forgot', 'conflict', 'unwilling', 'other'];

export const MISS_LABEL: Record<MissReason, string> = {
  tired: '피곤함',
  forgot: '깜빡함',
  conflict: '일·약속 겹침',
  unwilling: '하기 싫었음',
  other: '기타',
};

/**
 * 시각은 자정 기준 분으로 다룬다(ClockTime). 25:00처럼 24시를 넘는 값도
 * 허용해 자정을 넘는 취침을 다룬다.
 */
export type ClockMinutes = number;

/** 식사·운동처럼 매일 반복되는 습관 자리. */
export interface HabitSlot {
  title: string;
  activity: Activity;
  start: ClockMinutes;
  minutes: number;
}

/** 사용자의 습관 목표. */
export interface HabitGoals {
  wake: ClockMinutes;
  sleepMinutes: number;
  meals: HabitSlot[];
  exercise: HabitSlot | null;
}

/** 개인 설정. 수치는 엔진 명세의 초기값이다. */
export interface PersonalSettings {
  prepMinutes: number;
  travelMinutes: number;
  sleepLatencyMinutes: number;
  windDownMinutes: number;
  focusStart: ClockMinutes;
  focusEnd: ClockMinutes;
  chunkMinutes: number;
  restMinutes: number;
  /** 빈 시간 중 할 일로 채울 비율. */
  fillRatio: number;
  /** 코칭 R4로 앞당긴 취침 시각(분). 기본 0. */
  bedEarlierMinutes: number;
}

export const DEFAULT_SETTINGS: PersonalSettings = {
  prepMinutes: 50,
  travelMinutes: 40,
  sleepLatencyMinutes: 15,
  windDownMinutes: 30,
  focusStart: 9 * 60,
  focusEnd: 12 * 60,
  chunkMinutes: 50,
  restMinutes: 10,
  fillRatio: 0.75,
  bedEarlierMinutes: 0,
};

/** 캘린더에서 가져온(지금은 직접 입력한) 고정 일정. */
export interface FixedEvent {
  id: string;
  title: string;
  start: Date;
  end: Date;
  /** 외부 캘린더에서 가져온 일정이면 그 캘린더 id. 다시 가져올 때 통째로 바꾼다. */
  source?: string;
}

export interface TaskItem {
  id: string;
  title: string;
  estMinutes: number;
  dueAt: Date;
  type: TaskType;
  priority: TaskPriority;
  focus: boolean;
  doneMinutes: number;
  link?: string;
  done?: boolean;
  /** 사용자가 끌어서 정한 순서(0이 맨 위). 있으면 마감·우선순위보다 먼저 본다. */
  rank?: number;
  /** 만든 시각(오래된 할 일을 알아보는 데 쓴다). */
  createdAt?: Date;
  /** '30분 더'처럼 잡은 시간을 다 쓴 뒤 사용자가 늘린 시간. */
  extraMinutes?: number;
}

/** 종류만으로 집중이 필요한 일인지 정한다(업무·과제는 집중 시간대에 먼저). */
export const focusByType = (type: TaskType): boolean => type === 'work' || type === 'assignment';

export const remainingMinutes = (t: TaskItem): number => Math.max(0, t.estMinutes - t.doneMinutes);

export interface ScheduleBlock {
  id: string;
  kind: BlockKind;
  title: string;
  start: Date;
  end: Date;
  activity?: Activity;
  locked?: boolean;
  focus?: boolean;
  taskId?: string;
  status?: BlockStatus;
  /** 코칭으로 바뀐 블록인지(화면에 '조정됨' 표시). */
  adjusted?: boolean;
}

export const blockMinutes = (b: { start: Date; end: Date }): number => diffMin(b.end, b.start);

/** 엔진이 움직일 수 없는 블록인지(잠금·캘린더·수면). */
export const isImmovable = (b: ScheduleBlock): boolean =>
  !!b.locked || b.kind === 'fixed' || b.activity === 'sleep';

export const overlaps = (b: { start: Date; end: Date }, s: Date, e: Date): boolean =>
  b.start.getTime() < e.getTime() && s.getTime() < b.end.getTime();

export interface ActivityLog {
  id: string;
  activity: Activity;
  start: Date;
  end: Date | null;
  source: LogSource;
  confirmed: boolean;
  snoozeCount: number;
}

export const isOpen = (l: ActivityLog): boolean => l.end == null;
export const isEstimate = (l: ActivityLog): boolean => l.source === 'estimate' || !l.confirmed;
export const minutesUntil = (l: ActivityLog, now: Date): number => diffMin(l.end ?? now, l.start);

export function makeLog(p: Partial<ActivityLog> & Pick<ActivityLog, 'id' | 'activity' | 'start'>): ActivityLog {
  return { end: null, source: 'button', confirmed: true, snoozeCount: 0, ...p };
}

export type AlarmKind = 'wake' | 'bed' | 'windDown';

export interface PlannedAlarm {
  kind: AlarmKind;
  at: Date;
  /** 알람 시각의 근거. 비서가 "알람이 왜 6시 40분이야?"에 답할 때 쓴다. */
  reason: string;
}

// ---------------------------------------------------------------------------
// 시간 도구
// ---------------------------------------------------------------------------

/** 분 차이. Dart Duration.inMinutes처럼 0 쪽으로 버린다. */
export function diffMin(a: Date, b: Date): number {
  return Math.trunc((a.getTime() - b.getTime()) / 60000);
}

export function addMin(d: Date, minutes: number): Date {
  return new Date(d.getTime() + minutes * 60000);
}

export function dayStart(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(d: Date, days: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
}

export function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** ClockTime.on(day): 그 날 자정 + 분. */
export function clockOn(minutes: ClockMinutes, day: Date): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), 0, minutes);
}

export const isBefore = (a: Date, b: Date): boolean => a.getTime() < b.getTime();
export const isAfter = (a: Date, b: Date): boolean => a.getTime() > b.getTime();

const pad = (n: number): string => String(n).padStart(2, '0');

export function formatHm(t: Date): string {
  return `${pad(t.getHours())}:${pad(t.getMinutes())}`;
}

export function formatClock(minutes: ClockMinutes): string {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
}

export function formatDuration(minutes: number): string {
  const h = Math.trunc(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}분`;
  if (m === 0) return `${h}시간`;
  return `${h}시간 ${m}분`;
}

/** 'YYYY-MM-DD' 형식의 날짜 키(기기 현지 시각 기준). */
export function dateKey(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function fromKey(key: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/** 그 주 월요일. */
export function mondayOf(d: Date): Date {
  const day = dayStart(d);
  const w = (day.getDay() + 6) % 7; // 월=0
  return addDays(day, -w);
}

const WEEKDAY = ['일', '월', '화', '수', '목', '금', '토'];

export function koreanDate(d: Date): string {
  return `${d.getMonth() + 1}월 ${d.getDate()}일 ${WEEKDAY[d.getDay()]}요일`;
}

export function weekdayLabel(d: Date): string {
  return WEEKDAY[d.getDay()];
}
