// 외부 캘린더 동기화와 비정상 상황 처리.
//
// 원칙: 가져오기에 실패해도 이전에 가져온 일정은 지우지 않고 그대로 일정을 짠다.
//       실패 이유는 캘린더 옆에 남겨 사용자가 다음 행동(다시 연결, 파일 다시 고르기)을 알 수 있게 한다.

import { envClientId, fetchGoogleEvents, requestToken, savedToken, TokenExpired } from './gcal';
import { parseIcs } from './ics';
import { getState, type ImportOutcome, importCalendar, importWindow, markCalendarError } from './store';

export const GOOGLE_ID = 'google';
export const MAX_ICS_BYTES = 5 * 1024 * 1024;
/** 자동 동기화 간격. */
export const SYNC_EVERY_MS = 30 * 60000;
/** 이보다 오래 못 가져오면 '오래됨'으로 알린다. */
export const STALE_MS = 24 * 3600000;

export interface SyncResult {
  ok: boolean;
  text: string;
  outcome?: ImportOutcome;
}

export const clientIdOf = (): string => getState().googleClientId || envClientId();

function summary(o: ImportOutcome, skipped: { allDay: number; long: number; free: number }, what: string): string {
  const notes: string[] = [];
  if (skipped.allDay) notes.push(`하루 종일 ${skipped.allDay}개`);
  if (o.dupes) notes.push(`이미 있는 일정 ${o.dupes}개`);
  if (skipped.long) notes.push(`12시간 넘는 일정 ${skipped.long}개`);
  if (o.capped) notes.push(`너무 많아 ${o.capped}개`);
  const head = `${what} 일정 ${o.count}개를 가져왔어요${o.replanned ? '. 남은 일정을 바로 다시 짰어요' : ''}`;
  return notes.length ? `${head} · ${notes.join('·')}는 뺐어요` : head;
}

/** 구글 캘린더에서 앞으로 2주 일정을 가져온다. interactive면 필요할 때 구글 창을 띄운다. */
export async function syncGoogle(interactive: boolean): Promise<SyncResult> {
  const clientId = clientIdOf();
  if (!clientId) return { ok: false, text: '구글 클라이언트 ID가 없어요. 설정에서 넣어 주세요' };
  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    const text = '인터넷 연결이 없어요. 마지막으로 가져온 일정으로 짜요';
    markCalendarError(GOOGLE_ID, text);
    return { ok: false, text };
  }
  const first = !getState().calendars.some((c) => c.id === GOOGLE_ID);
  let tok = savedToken();
  try {
    if (!tok) {
      if (!interactive) {
        const text = '구글 연결이 만료됐어요. 다시 연결을 눌러 주세요';
        if (!getState().calendars.find((c) => c.id === GOOGLE_ID)?.needsAuth) markCalendarError(GOOGLE_ID, text, true);
        return { ok: false, text };
      }
      tok = await requestToken(clientId, first);
    }
    let r;
    try {
      r = await fetchGoogleEvents(tok.token, importWindow().from, importWindow().to);
    } catch (e) {
      if (!(e instanceof TokenExpired) || !interactive) throw e;
      tok = await requestToken(clientId, false); // 만료됐으면 한 번만 다시 받는다
      r = await fetchGoogleEvents(tok.token, importWindow().from, importWindow().to);
    }
    const outcome = importCalendar({ id: GOOGLE_ID, kind: 'google', name: r.calendars.length ? `구글 · ${r.calendars.slice(0, 2).join(', ')}${r.calendars.length > 2 ? ` 외 ${r.calendars.length - 2}` : ''}` : '구글 캘린더' }, r.events);
    markCalendarError(GOOGLE_ID, null);
    return { ok: true, text: summary(outcome, r.skipped, '구글 캘린더'), outcome };
  } catch (e) {
    const expired = e instanceof TokenExpired;
    const text = expired
      ? '구글 연결이 만료됐어요. 다시 연결을 눌러 주세요'
      : e instanceof TypeError
        ? '구글에 연결하지 못했어요. 마지막으로 가져온 일정으로 짜요'
        : (e as Error).message || '구글 캘린더를 가져오지 못했어요';
    if (!first) markCalendarError(GOOGLE_ID, text, expired);
    return { ok: false, text };
  }
}

/** 자동 동기화가 필요한지(연결돼 있고, 마지막 동기화가 간격보다 오래됐을 때). */
export function googleDue(t = Date.now()): boolean {
  const g = getState().calendars.find((c) => c.id === GOOGLE_ID);
  return !!g && !g.needsAuth && t - g.lastSync.getTime() >= SYNC_EVERY_MS - 1000;
}

export type IcsCheck =
  | { kind: 'error'; text: string }
  | { kind: 'empty-replace'; id: string; name: string; previous: number; text: string }
  | { kind: 'ready'; run: () => SyncResult };

const sourceIdFor = (name: string) => `ics:${name.replace(/\.ics$/i, '').trim().toLowerCase().slice(0, 60) || 'file'}`;

/** .ics 글을 검사한다. 0개로 기존 일정을 지우게 되면 먼저 묻는다. */
export function checkIcs(text: string, fileName: string, size: number): IcsCheck {
  if (size > MAX_ICS_BYTES) return { kind: 'error', text: '파일이 너무 커요(5MB 초과). 캘린더 하나만 골라 내보내 주세요' };
  if (!/BEGIN:VCALENDAR/i.test(text)) return { kind: 'error', text: '캘린더 파일(.ics)이 아니에요. 캘린더 앱의 내보내기로 받은 파일을 골라 주세요' };
  let parsed;
  try {
    parsed = parseIcs(text, importWindow().from, importWindow().to);
  } catch {
    return { kind: 'error', text: '파일을 읽다가 문제가 생겼어요. 다시 내보낸 파일로 해 주세요' };
  }
  const name = parsed.calName || fileName.replace(/\.ics$/i, '') || '가져온 캘린더';
  const id = sourceIdFor(parsed.calName || fileName);
  const previous = getState().calendars.find((c) => c.id === id)?.count ?? 0;
  if (parsed.events.length === 0) {
    const why = parsed.skipped.allDay ? ` (하루 종일 일정 ${parsed.skipped.allDay}개는 시각이 없어 빼요)` : '';
    if (previous > 0) return { kind: 'empty-replace', id, name, previous, text: `이 파일에는 앞으로 2주 안에 시각이 있는 일정이 없어요${why}.` };
    return { kind: 'error', text: `앞으로 2주 안에 시각이 있는 일정이 없어요${why}` };
  }
  return {
    kind: 'ready',
    run: () => {
      const outcome = importCalendar({ id, kind: 'ics', name }, parsed.events);
      return { ok: true, text: summary(outcome, parsed.skipped, `'${name}'`), outcome };
    },
  };
}
