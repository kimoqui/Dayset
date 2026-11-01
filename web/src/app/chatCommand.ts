// 채팅으로 일정 바꾸기: "내일 운동 7시로 옮겨줘", "오늘 점심 30분 늦춰", "금요일 3시 치과 추가" 같은 말을
// 일정 바꾸기 목록(edits.ts의 ScheduleEdit)으로 읽는다. 서버·AI 없이 기기 안에서 규칙으로 읽는다.
// 같은 목록을 나중에 서버 AI(Claude)가 만들어 주면 화면·적용 흐름은 그대로 쓴다.
// 바로 바꾸지 않는다: 화면이 바뀌는 내용을 보여 주고, 사용자가 '바꾸기'를 눌러야 적용한다.

import { addDays, addMin, dateKey, dayStart, diffMin, formatClock, type TaskType } from '../engine/models';
import { type EditScope, habitOn, habitTitles, type ScheduleEdit } from './edits';
import { EXERCISES, nativeNumbers } from './goalText';
import { parseEventText } from './nlp';
import type { AppState } from './state';

export interface ChatReading {
  edits: ScheduleEdit[];
  /** 읽은 것을 설명하는 답(바꿀 것이 없으면 도움말). */
  reply: string;
  /** 읽지 못한 부분. */
  unknown: string[];
}

export const CHAT_EXAMPLES = ['내일 운동 7시로 옮겨줘', '오늘 점심 30분 늦춰', '금요일 3시 치과 1시간 추가', '내일 6시 반에 깨워줘', '오늘 운동 빼줘', '할 일 보고서 2시간 추가'];

const SKIP = /빼|취소|건너뛰|없애|안\s*해|안\s*할|쉴래|쉬어|쉴게|생략|패스|지워/;
const RESET = /원래대로|되돌려|초기화|다시\s*원래/;
const EVERY = /매일|항상|앞으로|계속|매번|평소/;
const ADD = /추가|넣어|넣기|잡아|등록|만들어|생겼|있어/;
const WAKE = /기상|알람|일어나|일어날|깨워|깨우|깨줘/;
const LATER = /늦|미뤄|미루|뒤로|나중/;
const EARLIER = /일찍|당겨|앞당|빨리|앞으로/;
const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

/** 날짜 말: 오늘·내일·모레·글피·요일·M월 D일. 없으면 null. */
function readDay(text: string, now: Date): string | null {
  const today = dayStart(now);
  const m1 = text.match(/(오늘|내일|모레|글피)/);
  if (m1) return dateKey(addDays(today, { 오늘: 0, 내일: 1, 모레: 2, 글피: 3 }[m1[1] as '오늘']));
  const m2 = text.match(/(이번\s*주|다음\s*주)?\s*([월화수목금토일])요일/);
  if (m2) {
    const target = WEEKDAYS.indexOf(m2[2]);
    const mon = addDays(today, -((today.getDay() + 6) % 7));
    let d = addDays(mon, ((target + 6) % 7) + (m2[1]?.startsWith('다음') ? 7 : 0));
    if (!m2[1] && d < today) d = addDays(d, 7);
    return dateKey(d);
  }
  const m3 = text.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/);
  if (m3) {
    let d = new Date(now.getFullYear(), Number(m3[1]) - 1, Number(m3[2]));
    if (d < today) d = new Date(now.getFullYear() + 1, Number(m3[1]) - 1, Number(m3[2]));
    return dateKey(d);
  }
  return null;
}

/** 'N시(반|M분)' 또는 'H:MM'. 낮·밤 말이 있으면 반영, 없으면 null(쓰는 곳에서 가까운 쪽으로 고른다). */
function readClock(text: string): { h: number; m: number; ampm: 'am' | 'pm' | null } | null {
  const m = text.match(/(오전|오후|아침|저녁|밤|새벽|낮)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(?:(반)|(\d{1,2})\s*분)?)(?!\s*간)/);
  if (!m) return null;
  const h = Number(m[2]);
  const min = m[3] ? Number(m[3]) : m[4] ? 30 : m[5] ? Number(m[5]) : 0;
  if (h > 24 || min > 59) return null;
  const w = m[1];
  return { h, m: min, ampm: !w ? null : /오전|아침|새벽/.test(w) ? 'am' : 'pm' };
}

/** 낮·밤 말이 없으면 기준 시각(지금 값)에 가까운 쪽(오전·오후)으로. */
function resolveClock(c: { h: number; m: number; ampm: 'am' | 'pm' | null }, near: number): number {
  if (c.ampm === 'am') return (c.h % 12) * 60 + c.m;
  if (c.ampm === 'pm') return ((c.h % 12) + 12) * 60 + c.m;
  if (c.h > 12) return c.h * 60 + c.m;
  const a = (c.h % 12) * 60 + c.m;
  const p = a + 12 * 60;
  return Math.abs(a - near) <= Math.abs(p - near) ? a : p;
}

/** 'N분' 'N시간(반)' → 분 */
function readMinutes(text: string): number | null {
  const h = text.match(/(\d{1,2}(?:\.\d)?)\s*시간\s*(반)?(?:\s*(\d{1,2})\s*분)?/);
  if (h) return Math.round(Number(h[1]) * 60 + (h[2] ? 30 : 0) + (h[3] ? Number(h[3]) : 0));
  const m = text.match(/(\d{1,3})\s*분/);
  return m ? Number(m[1]) : null;
}

/** 이 말에서 가리키는 습관 이름(목표에 있는 것). */
function habitTarget(clause: string, s: AppState): string | null {
  const titles = habitTitles(s);
  for (const t of titles) if (clause.includes(t)) return t;
  const ex = s.goals.exercise?.title;
  if (ex && EXERCISES.some(([re]) => re.test(clause))) return ex;
  const meal = (word: string) => titles.find((t) => t.startsWith(word)) ?? null;
  if (/점심/.test(clause)) return meal('점심');
  // '아침 7시'·'저녁 8시'처럼 시각 앞의 말은 식사가 아니다.
  if (/아침(?!\s*\d)/.test(clause) && /아침\s*(식사|밥|먹)|조식|아침(?=\s|$|을|은|도)/.test(clause)) return meal('아침');
  if (/저녁(?!\s*\d)/.test(clause) && /저녁\s*(식사|밥|먹)|석식|저녁(?=\s|$|을|은|도)/.test(clause)) return meal('저녁');
  return null;
}

const cleanTitle = (t: string) =>
  t
    .replace(/(을|를)?\s*(추가|넣어|넣기|잡아|등록|만들어|생겼|있어)\S*/g, ' ')
    .replace(/(해\s*)?(줘|주세요|줄래|요)$/g, '')
    .replace(/\s+/g, ' ')
    .trim();

const eventKey = (t: string) => t.replace(/\s+/g, '');

export function interpretChat(input: string, s: AppState, now: Date): ChatReading {
  const text = nativeNumbers(input.trim()).slice(0, 300);
  const edits: ScheduleEdit[] = [];
  const unknown: string[] = [];
  if (!text) return { edits, unknown, reply: help() };
  const today = dateKey(now);
  const allDay = readDay(text, now);

  for (const raw of text.split(/[,，\n]|그리고|(?<=[가-힣])(?:고|하고)\s+(?=\S*\s*(?:오늘|내일|모레|[월화수목금토일]요일|\d))/)) {
    const clause = (raw ?? '').trim();
    if (!clause) continue;
    const day = readDay(clause, now) ?? allDay;
    const scope: EditScope = EVERY.test(clause) ? 'every' : 'day';
    const before = edits.length;

    // 1) 되돌리기
    if (RESET.test(clause) && !habitTarget(clause, s)) {
      edits.push({ kind: 'reset', day: day ?? today });
      continue;
    }

    // 2) 기상
    if (WAKE.test(clause)) {
      const d = day ?? (now.getHours() >= 12 ? dateKey(addDays(now, 1)) : today);
      const cur = habitWake(s, d);
      const c = readClock(clause);
      const shift = readMinutes(clause);
      let minutes: number | null = null;
      if (c) minutes = c.ampm === 'pm' && c.h < 12 ? (c.h + 12) * 60 + c.m : (c.h % 24) * 60 + c.m;
      else if (shift && LATER.test(clause)) minutes = cur + shift;
      else if (shift && EARLIER.test(clause)) minutes = cur - shift;
      if (minutes != null) {
        edits.push({ kind: 'wake', day: d, minutes: Math.max(4 * 60, Math.min(12 * 60, minutes)), scope });
        continue;
      }
    }

    // 3) 습관(식사·운동)
    const title = habitTarget(clause, s);
    if (title) {
      let d = day ?? today;
      const cur = habitOn(s, d, title) ?? habitOn(s, dateKey(addDays(now, 1)), title);
      // 날짜 말이 없고 오늘 그 습관이 이미 지났으면 내일로 본다.
      if (!day && scope === 'day' && cur) {
        const startToday = addMin(dayStart(now), cur.start);
        if (diffMin(now, startToday) > cur.minutes) d = dateKey(addDays(now, 1));
      }
      if (RESET.test(clause)) {
        edits.push({ kind: 'reset', day: d });
        continue;
      }
      if (SKIP.test(clause)) {
        edits.push({ kind: 'habit', day: d, title, patch: { skip: true }, scope });
        continue;
      }
      const patch: { start?: number; minutes?: number } = {};
      const c = readClock(clause.replace(/\d{1,3}\s*분/g, ''));
      const mins = readMinutes(clause);
      if (c && cur) patch.start = resolveClock(c, cur.start);
      else if (c) patch.start = resolveClock(c, 12 * 60);
      if (mins != null && cur && (LATER.test(clause) || EARLIER.test(clause)) && !c) {
        patch.start = cur.start + (LATER.test(clause) ? mins : -mins);
      } else if (mins != null && (/줄|늘|동안|만\b|으로|로\s*(바꿔|해)|길게|짧게/.test(clause) || c)) {
        patch.minutes = Math.max(5, Math.min(240, mins));
      }
      if (patch.start != null) patch.start = Math.max(0, Math.min(23 * 60 + 55, patch.start));
      if (patch.start != null || patch.minutes != null) {
        edits.push({ kind: 'habit', day: d, title, patch, scope });
        continue;
      }
    }

    // 4) 할 일 넣기
    if (/할\s*일|과제|숙제|공부|보고서|레포트|리포트/.test(clause) && ADD.test(clause)) {
      const mins = readMinutes(clause) ?? 60;
      const type: TaskType = /숙제|공부/.test(clause) ? 'homework' : /과제|레포트|리포트/.test(clause) ? 'assignment' : /개인|집안|장보기/.test(clause) ? 'personal' : 'work';
      const name = cleanTitle(
        clause
          .replace(/(오늘|내일|모레|[월화수목금토일]요일)(까지)?/g, ' ')
          .replace(/할\s*일(에|로|으로)?/g, ' ')
          .replace(/\d{1,2}(?:\.\d)?\s*시간\s*(반)?|\d{1,3}\s*분/g, ' '),
      );
      edits.push({ kind: 'task-add', title: name || '할 일', minutes: Math.max(10, Math.min(600, mins)), type, ...(day ? { dueAt: addMin(new Date(`${day}T00:00:00`), 23 * 60) } : {}) });
      continue;
    }

    // 5) 이미 있는 캘린더 일정 옮기기·지우기
    const ev = s.events
      .filter((e) => !e.source && e.end > now)
      .find((e) => eventKey(clause).includes(eventKey(e.title)) || (eventKey(e.title).length >= 2 && eventKey(clause).includes(eventKey(e.title).slice(0, 2))));
    if (ev && !ADD.test(clause)) {
      if (SKIP.test(clause)) {
        edits.push({ kind: 'event-delete', id: ev.id });
        continue;
      }
      const len = diffMin(ev.end, ev.start);
      const c = readClock(clause.replace(/\d{1,3}\s*분/g, ''));
      const mins = readMinutes(clause);
      let start: Date | null = null;
      if (c) {
        const base = day ? new Date(`${day}T00:00:00`) : dayStart(ev.start);
        start = addMin(base, resolveClock(c, ev.start.getHours() * 60 + ev.start.getMinutes()));
      } else if (mins && LATER.test(clause)) start = addMin(ev.start, mins);
      else if (mins && EARLIER.test(clause)) start = addMin(ev.start, -mins);
      else if (day && day !== dateKey(ev.start)) start = addMin(new Date(`${day}T00:00:00`), ev.start.getHours() * 60 + ev.start.getMinutes());
      if (start) {
        edits.push({ kind: 'event-move', id: ev.id, start, end: addMin(start, len) });
        continue;
      }
    }

    // 6) 새 캘린더 일정
    const p = parseEventText(cleanTitle(clause), now);
    if (p && (ADD.test(clause) || !title)) {
      edits.push({ kind: 'event-add', title: p.title, start: p.start, end: p.end });
      continue;
    }

    if (edits.length === before) unknown.push(clause);
  }

  const reply = edits.length
    ? unknown.length
      ? `이렇게 바꿀게요. ‘${unknown.join('’, ‘')}’는 읽지 못했어요.`
      : '이렇게 바꿀게요. 맞으면 바꾸기를 눌러 주세요.'
    : help(unknown);
  return { edits, unknown, reply };
}

function habitWake(s: AppState, day: string): number {
  return s.overrides[day]?.wake ?? s.goals.wake;
}

function help(unknown: string[] = []): string {
  return `${unknown.length ? '어떻게 바꿀지 읽지 못했어요. ' : ''}이렇게 말해 주세요: ‘내일 운동 7시로 옮겨줘’, ‘오늘 점심 30분 늦춰’, ‘금요일 3시 치과 추가’, ‘내일 6시 반에 깨워줘’, ‘오늘 운동 빼줘’.`;
}

/** 기상 시각 표시(답 글에 쓴다). */
export const wakeText = (m: number): string => formatClock(m);
