// 알림: 권한 받기, 푸시 토큰, '지금 일정' 알림 띄워 두기, 알림 버튼으로 바로 기록.
//
// - 설치형(https·PWA)에서는 서비스 워커 알림을 쓴다: 버튼(기록하기 · 지금은 안 해요)이 붙고, 누르면 앱이 기록한다.
// - 파일로 연 화면에서는 기본 알림만 된다(버튼 없음, 누르면 앱이 열리고 일정 체크 팝업이 보인다).
// - 푸시 토큰: VITE_VAPID_PUBLIC_KEY가 있으면 푸시 구독을 만들고 그 주소의 지문을 남긴다.
//   앱이 닫혀 있을 때 보내는 푸시는 서버가 이 토큰으로 보낸다(앱 버전). 로컬 버전은 화면이 열려 있거나
//   브라우저가 백그라운드에서 살아 있는 동안 알린다.

import { ACTIVITY_LABEL, formatHm } from '../engine/models';
import type { NowCheck } from '../app/nowCheck';
import { hasBatchim, objectParticle } from '../engine/coaching';

export const NOW_TAG = 'dayset-now';

export type NotifySupport = 'none' | 'basic' | 'sw';

export function notifySupport(): NotifySupport {
  if (typeof window === 'undefined' || typeof Notification === 'undefined') return 'none';
  return 'serviceWorker' in navigator && location.protocol.startsWith('http') ? 'sw' : 'basic';
}

export const permission = (): NotificationPermission | 'unsupported' => (typeof Notification === 'undefined' ? 'unsupported' : Notification.permission);

async function registration(): Promise<ServiceWorkerRegistration | null> {
  if (notifySupport() !== 'sw') return null;
  try {
    const existing = await navigator.serviceWorker.getRegistration();
    const reg = existing ?? (await navigator.serviceWorker.register('./sw.js'));
    return reg;
  } catch {
    return null;
  }
}

function fingerprint(text: string): string {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return `pt-${(h >>> 0).toString(36)}`;
}

function vapidKey(): Uint8Array | null {
  const raw = (import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined) ?? '';
  if (!raw) return null;
  const b64 = (raw + '='.repeat((4 - (raw.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

export interface EnableResult {
  permission: NotificationPermission | 'unsupported';
  /** 푸시 토큰 지문(서버 키가 있을 때만). */
  token?: string;
  /** 사람이 읽는 결과. */
  text: string;
}

/** 버튼을 눌렀을 때 부른다: 알림 권한을 받고, 가능하면 푸시 토큰을 만든다. */
export async function enableNotifications(): Promise<EnableResult> {
  if (notifySupport() === 'none') return { permission: 'unsupported', text: '이 브라우저는 알림을 지원하지 않아요. 앱 안 팝업으로만 알려 드려요' };
  let p: NotificationPermission;
  try {
    p = await Notification.requestPermission();
  } catch {
    p = Notification.permission;
  }
  if (p !== 'granted') {
    return { permission: p, text: p === 'denied' ? '알림이 막혀 있어요. 브라우저 설정에서 이 사이트 알림을 허용해 주세요' : '알림을 허용하지 않았어요. 앱 안 팝업으로 알려 드려요' };
  }
  const reg = await registration();
  const key = vapidKey();
  if (reg && key && 'pushManager' in reg) {
    try {
      const sub = (await reg.pushManager.getSubscription()) ?? (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key as BufferSource }));
      return { permission: p, token: fingerprint(sub.endpoint), text: '알림을 켜고 푸시 토큰을 만들었어요' };
    } catch {
      return { permission: p, text: '알림을 켰어요. 푸시 토큰은 만들지 못해서, 화면이 열려 있는 동안 알려 드려요' };
    }
  }
  return { permission: p, text: '알림을 켰어요. 지금 일정을 알림에 띄워 두고, 기록할 때를 알려 드려요' };
}

export interface NowNotice {
  title: string;
  body: string;
  /** 알림 버튼으로 기록할 활동. */
  activity?: string;
  /** '지금은 안 해요'로 넘길 열쇠. */
  skipId?: string;
  /** 소리·진동 없이 조용히 바꾸기(이미 기록 중일 때). */
  silent: boolean;
}

const act = (a?: string | null) => (a ? ACTIVITY_LABEL[a as keyof typeof ACTIVITY_LABEL] : '');

/** 일정 체크 결과를 알림 문구로 바꾼다. 알릴 게 없으면 null. */
export function noticeFor(c: NowCheck): NowNotice | null {
  const next = c.next ? ` · 다음 ${formatHm(c.next.start)} ${c.next.title}` : '';
  if (c.kind === 'due' && c.block) {
    return {
      title: `${formatHm(c.block.start)} ${c.block.title} 시간이에요`,
      body: c.current ? `지금 기록은 ${act(c.current)}${hasBatchim(act(c.current)) ? '이에요' : '예요'}. ${act(c.expected)}${objectParticle(act(c.expected))} 시작했으면 '기록하기'를 눌러 주세요` : `시작했으면 '기록하기'를 눌러 주세요`,
      activity: c.expected,
      skipId: c.block.id,
      silent: c.skipped,
    };
  }
  if (c.kind === 'over' && c.block) {
    return { title: `${c.block.title} 끝났어요?`, body: `끝났으면 '기록하기'를 눌러 휴식으로 바꿔 주세요${next}`, activity: 'rest', skipId: `${c.block.id}:over`, silent: c.skipped };
  }
  if (c.kind === 'ok' && c.block) {
    return { title: `지금 ${c.block.title} · ${formatHm(c.block.start)}–${formatHm(c.block.end)}`, body: `${act(c.current)} 기록 중${next}`, silent: true };
  }
  if (c.kind === 'next' && c.next) return { title: `다음 ${formatHm(c.next.start)} ${c.next.title}`, body: '시작하면 알려 드릴게요', silent: true };
  return null;
}

/** '지금 일정' 알림을 띄우거나 바꾼다. 같은 tag라 알림은 하나만 남는다. */
export async function showNowNotification(n: NowNotice, sticky: boolean): Promise<void> {
  if (permission() !== 'granted') return;
  const opts: NotificationOptions & { renotify?: boolean; actions?: { action: string; title: string }[] } = {
    body: n.body,
    tag: NOW_TAG,
    silent: n.silent,
    renotify: !n.silent,
    requireInteraction: sticky,
    data: { activity: n.activity, skipId: n.skipId },
  };
  const reg = await registration();
  try {
    if (reg) {
      if (n.activity) opts.actions = [{ action: 'record', title: '기록하기' }, { action: 'skip', title: '지금은 안 해요' }];
      await reg.showNotification(n.title, opts);
    } else {
      const note = new Notification(n.title, opts);
      note.onclick = () => {
        window.focus();
        note.close();
      };
    }
  } catch {
    // 알림을 띄울 수 없는 환경: 앱 안 팝업으로 충분하다.
  }
}

export async function clearNowNotification(): Promise<void> {
  const reg = await registration();
  try {
    const list = reg ? await reg.getNotifications({ tag: NOW_TAG }) : [];
    list.forEach((x) => x.close());
  } catch {
    // 무시
  }
}

export interface NotifyAction {
  action: 'record' | 'skip' | 'open';
  activity?: string;
  skipId?: string;
}

/** 서비스 워커가 보낸 알림 버튼 동작을 받는다. 앱이 닫혀 있다가 열렸으면 주소의 ?n= 값으로 받는다. */
export function listenNotifyActions(on: (a: NotifyAction) => void): () => void {
  const handler = (e: MessageEvent) => {
    const d = e.data as { type?: string } & NotifyAction;
    if (d?.type === 'dayset-notify') on({ action: d.action, activity: d.activity, skipId: d.skipId });
  };
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('message', handler);
  try {
    const q = new URLSearchParams(location.search);
    const a = q.get('n');
    if (a === 'record' || a === 'skip') {
      on({ action: a, activity: q.get('a') ?? undefined, skipId: q.get('b') ?? undefined });
      q.delete('n');
      q.delete('a');
      q.delete('b');
      history.replaceState(null, '', `${location.pathname}${q.toString() ? `?${q}` : ''}`);
    }
  } catch {
    // 주소를 읽을 수 없는 환경
  }
  return () => {
    if ('serviceWorker' in navigator) navigator.serviceWorker.removeEventListener('message', handler);
  };
}
