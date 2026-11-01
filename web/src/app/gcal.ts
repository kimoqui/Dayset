// 구글 캘린더 직접 연결(읽기 전용).
//
// 구글 로그인(Google Identity Services)으로 1시간짜리 읽기 토큰을 받아, 켜 둔 캘린더들의 일정을 가져온다.
// - 필요한 것: 구글 클라우드 'OAuth 클라이언트 ID'(웹 애플리케이션). 승인된 출처에 이 앱 주소를 넣는다.
// - 파일(file://)로 연 화면에서는 구글 로그인이 막힌다. 배포 주소나 `npm run dev`(localhost)에서 연결한다.
// - 토큰은 이 탭의 sessionStorage에만 둔다. 만료되면 '다시 연결'을 눌러 새로 받는다(서버가 없어서).
//   앱 버전에서는 서버가 새로 고침 토큰으로 계속 동기화한다.

import type { ImportedEvent } from './ics';

export const GOOGLE_SCOPE = 'https://www.googleapis.com/auth/calendar.readonly';
const GIS_SRC = 'https://accounts.google.com/gsi/client';
const API = 'https://www.googleapis.com/calendar/v3';
const TOKEN_KEY = 'dayset:gtoken';

interface TokenResponse {
  access_token?: string;
  expires_in?: number;
  error?: string;
}
interface TokenClient {
  requestAccessToken: (o?: { prompt?: string }) => void;
}
interface GoogleNs {
  accounts: { oauth2: { initTokenClient: (o: { client_id: string; scope: string; callback: (r: TokenResponse) => void; error_callback?: (e: { type?: string }) => void }) => TokenClient } };
}
const g = (): GoogleNs | undefined => (window as unknown as { google?: GoogleNs }).google;

export const envClientId = (): string => (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined) ?? '';

/** 이 화면에서 구글 로그인을 쓸 수 있는지(https 또는 localhost). */
export function originAllowed(): boolean {
  try {
    return location.protocol === 'https:' || ['localhost', '127.0.0.1'].includes(location.hostname);
  } catch {
    return false;
  }
}

let loading: Promise<void> | null = null;
function loadGis(): Promise<void> {
  if (g()?.accounts?.oauth2) return Promise.resolve();
  if (loading) return loading;
  loading = new Promise((resolve, reject) => {
    const el = document.createElement('script');
    el.src = GIS_SRC;
    el.async = true;
    el.onload = () => (g()?.accounts?.oauth2 ? resolve() : reject(new Error('구글 로그인을 불러오지 못했어요')));
    el.onerror = () => {
      loading = null;
      reject(new Error('구글 로그인을 불러오지 못했어요. 인터넷 연결을 확인해 주세요'));
    };
    document.head.appendChild(el);
  });
  return loading;
}

export interface GoogleToken {
  token: string;
  expiresAt: number;
}

export function savedToken(): GoogleToken | null {
  try {
    const raw = sessionStorage.getItem(TOKEN_KEY);
    if (!raw) return null;
    const t = JSON.parse(raw) as GoogleToken;
    return t.expiresAt > Date.now() + 60000 ? t : null;
  } catch {
    return null;
  }
}

function keepToken(t: GoogleToken | null): void {
  try {
    if (t) sessionStorage.setItem(TOKEN_KEY, JSON.stringify(t));
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch {
    // 저장소를 못 쓰면 이번 화면에서만 쓴다.
  }
}

export const forgetToken = (): void => keepToken(null);

/** 사용자가 버튼을 눌렀을 때 부른다(구글 창이 뜬다). */
export async function requestToken(clientId: string, firstTime: boolean): Promise<GoogleToken> {
  await loadGis();
  return new Promise((resolve, reject) => {
    const client = g()!.accounts.oauth2.initTokenClient({
      client_id: clientId,
      scope: GOOGLE_SCOPE,
      callback: (r) => {
        if (!r.access_token) {
          reject(new Error(r.error === 'access_denied' ? '구글 캘린더 읽기를 허용하지 않았어요' : '구글 연결에 실패했어요'));
          return;
        }
        const t = { token: r.access_token, expiresAt: Date.now() + (r.expires_in ?? 3600) * 1000 };
        keepToken(t);
        resolve(t);
      },
      error_callback: (e) => reject(new Error(e?.type === 'popup_closed' ? '구글 창을 닫았어요' : '구글 창을 열지 못했어요. 팝업 차단을 확인해 주세요')),
    });
    client.requestAccessToken({ prompt: firstTime ? 'consent' : '' });
  });
}

export class TokenExpired extends Error {}

async function get<T>(token: string, path: string): Promise<T> {
  const r = await fetch(`${API}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (r.status === 401) {
    keepToken(null);
    throw new TokenExpired('구글 연결이 만료됐어요');
  }
  if (!r.ok) throw new Error(`구글 캘린더를 읽지 못했어요 (${r.status})`);
  return (await r.json()) as T;
}

interface GEvent {
  id: string;
  status?: string;
  summary?: string;
  transparency?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
}

export interface GoogleResult {
  calendars: string[];
  events: ImportedEvent[];
  skipped: { allDay: number; long: number; free: number };
}

/** 켜 둔(목록에서 선택한) 캘린더의 from~to 일정. 최대 10개 캘린더. */
export async function fetchGoogleEvents(token: string, from: Date, to: Date): Promise<GoogleResult> {
  const list = await get<{ items?: { id: string; summary?: string; selected?: boolean; primary?: boolean }[] }>(token, '/users/me/calendarList?minAccessRole=reader');
  const cals = (list.items ?? []).filter((c) => c.selected || c.primary).slice(0, 10);
  const skipped = { allDay: 0, long: 0, free: 0 };
  const events: ImportedEvent[] = [];
  for (const c of cals) {
    const q = new URLSearchParams({ timeMin: from.toISOString(), timeMax: to.toISOString(), singleEvents: 'true', orderBy: 'startTime', maxResults: '250' });
    const r = await get<{ items?: GEvent[] }>(token, `/calendars/${encodeURIComponent(c.id)}/events?${q}`);
    for (const e of r.items ?? []) {
      if (e.status === 'cancelled') continue;
      if (!e.start?.dateTime || !e.end?.dateTime) {
        skipped.allDay++;
        continue;
      }
      if (e.transparency === 'transparent') {
        skipped.free++;
        continue;
      }
      const start = new Date(e.start.dateTime);
      const end = new Date(e.end.dateTime);
      if (end.getTime() - start.getTime() > 12 * 3600000) {
        skipped.long++;
        continue;
      }
      events.push({ uid: `${c.id}/${e.id}`, title: e.summary?.trim() || '일정', start, end });
    }
  }
  events.sort((a, b) => a.start.getTime() - b.start.getTime());
  return { calendars: cals.map((c) => c.summary ?? c.id), events, skipped };
}
