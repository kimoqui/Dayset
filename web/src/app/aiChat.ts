// 말로 일정 바꾸기를 서버 AI(Claude)로 읽기. 서버 함수: supabase/functions/dayset-chat.
// AI는 해석만 한다: 돌려받은 목록을 여기서 검사해 ScheduleEdit으로 바꾸고, 화면이 미리보기 → '바꾸기'를 거친다.
// 로그인하지 않았거나 서버·AI가 안 되면 null → 화면은 기기 안 규칙(chatCommand.ts)으로 읽는다.

import { addDays, dateKey, formatHm, type TaskType } from '../engine/models';
import { type ChatReading } from './chatCommand';
import { habitOn, habitTitles, type ScheduleEdit } from './edits';
import { planFor } from './derive';
import type { AppState } from './state';

const TASK_TYPES: TaskType[] = ['work', 'assignment', 'homework', 'personal'];
const WEEK = ['일', '월', '화', '수', '목', '금', '토'];
const pad = (n: number) => String(n).padStart(2, '0');
const local = (d: Date) => `${dateKey(d)}T${formatHm(d)}`;

/** AI에 넘길 일정 요약(오늘부터 7일). 기록·건강 정보는 넣지 않는다. */
export function aiContext(s: AppState, now: Date) {
  const days = [0, 1, 2, 3, 4, 5, 6].map((i) => dateKey(addDays(now, i)));
  const until = addDays(now, 8).getTime();
  return {
    now: local(now),
    weekday: WEEK[now.getDay()],
    habits: habitTitles(s),
    days: days.slice(0, 3).map((day) => {
      const p = planFor(s, day, now);
      return {
        day,
        wake: formatHm(p.wake),
        habits: habitTitles(s)
          .map((title) => {
            const h = habitOn(s, day, title);
            return h && { title, start: `${pad(Math.floor(h.start / 60) % 24)}:${pad(h.start % 60)}`, minutes: h.minutes };
          })
          .filter(Boolean),
      };
    }),
    events: s.events
      .filter((e) => e.end.getTime() > now.getTime() - 86_400_000 && e.start.getTime() < until)
      .slice(0, 40)
      .map((e) => ({ id: e.id, title: e.title, start: local(e.start), end: local(e.end), imported: !!e.source })),
    tasks: s.tasks.filter((t) => !t.done).slice(0, 20).map((t) => t.title),
  };
}

const HM = /^(\d{1,2}):(\d{2})$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const DT = /^(\d{4})-(\d{2})-(\d{2})T(\d{1,2}):(\d{2})/;

function hm(v: unknown): number | null {
  const m = typeof v === 'string' ? v.match(HM) : null;
  if (!m) return null;
  const h = +m[1];
  const mi = +m[2];
  return h < 24 && mi < 60 ? h * 60 + mi : null;
}
function dt(v: unknown): Date | null {
  const m = typeof v === 'string' ? v.match(DT) : null;
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
  return Number.isNaN(d.getTime()) ? null : d;
}
const day = (v: unknown, fallback: string): string => (typeof v === 'string' && DAY.test(v) ? v : fallback);
const text = (v: unknown, max = 60): string => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/** AI가 돌려준 값을 검사해 바꾸기 목록으로. 이상한 항목은 버린다. 읽을 것이 없으면 null. */
export function readAiReply(raw: unknown, s: AppState, now: Date): ChatReading | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as { reply?: unknown; edits?: unknown };
  const reply = text(r.reply, 300);
  const list = Array.isArray(r.edits) ? r.edits.slice(0, 8) : [];
  const today = dateKey(now);
  const titles = habitTitles(s);
  const edits: ScheduleEdit[] = [];
  const dropped: string[] = [];
  for (const it of list) {
    if (!it || typeof it !== 'object') continue;
    const e = it as Record<string, unknown>;
    const scope = e.scope === 'every' ? 'every' : 'day';
    const d = day(e.day, today);
    if (d < today) {
      dropped.push('지난 날');
      continue;
    }
    switch (e.kind) {
      case 'habit': {
        const title = text(e.title);
        if (!titles.includes(title)) {
          dropped.push(title || '습관');
          break;
        }
        const start = hm(e.start);
        const minutes = typeof e.minutes === 'number' && e.minutes >= 5 && e.minutes <= 240 ? Math.round(e.minutes) : null;
        if (e.skip === true) edits.push({ kind: 'habit', day: d, title, patch: { skip: true }, scope });
        else if (start != null || minutes != null)
          edits.push({ kind: 'habit', day: d, title, patch: { ...(start != null ? { start } : {}), ...(minutes != null ? { minutes } : {}) }, scope });
        break;
      }
      case 'wake': {
        const m = hm(e.start);
        if (m != null && m >= 3 * 60 && m <= 13 * 60) edits.push({ kind: 'wake', day: d, minutes: m, scope });
        else dropped.push('기상 시각');
        break;
      }
      case 'event-add': {
        const title = text(e.title);
        const start = dt(e.start);
        const end = dt(e.end);
        if (title && start && end && end > start && start.getTime() > now.getTime() - 3_600_000) edits.push({ kind: 'event-add', title, start, end });
        else dropped.push(title || '일정');
        break;
      }
      case 'event-move': {
        const ev = s.events.find((x) => x.id === e.id);
        const start = dt(e.start);
        const end = dt(e.end);
        if (ev && !ev.source && start && end && end > start) edits.push({ kind: 'event-move', id: ev.id, start, end });
        else dropped.push(ev?.title ?? '일정');
        break;
      }
      case 'event-delete': {
        const ev = s.events.find((x) => x.id === e.id);
        if (ev && !ev.source) edits.push({ kind: 'event-delete', id: ev.id });
        else dropped.push(ev?.title ?? '일정');
        break;
      }
      case 'task-add': {
        const title = text(e.title);
        const minutes = typeof e.minutes === 'number' && e.minutes >= 5 && e.minutes <= 600 ? Math.round(e.minutes) : 60;
        const type = TASK_TYPES.includes(e.taskType as TaskType) ? (e.taskType as TaskType) : 'work';
        const due = typeof e.due === 'string' && DAY.test(e.due) && e.due >= today ? new Date(+e.due.slice(0, 4), +e.due.slice(5, 7) - 1, +e.due.slice(8, 10), 23, 0) : undefined;
        if (title) edits.push({ kind: 'task-add', title, minutes, type, ...(due ? { dueAt: due } : {}) });
        break;
      }
      case 'reset':
        edits.push({ kind: 'reset', day: d });
        break;
      default:
        break;
    }
  }
  if (!reply && !edits.length && !dropped.length) return null;
  const note = dropped.length ? ` 바꿀 수 없는 것은 뺐어요: ${[...new Set(dropped)].join(', ')}.` : '';
  return { edits, reply: (reply || (edits.length ? '이렇게 바꿀까요?' : '그대로 둘게요.')) + note, unknown: dropped };
}
