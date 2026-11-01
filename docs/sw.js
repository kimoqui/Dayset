// 오프라인 캐시: 한 번 연 화면은 인터넷 없이도 열린다. 새 버전이 있으면 다음에 열 때 반영된다.
const CACHE = 'dayset-v2';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  e.respondWith(
    caches.open(CACHE).then(async (cache) => {
      try {
        const res = await fetch(req);
        if (res.ok && (new URL(req.url).origin === location.origin || req.url.includes('fonts.g'))) cache.put(req, res.clone());
        return res;
      } catch {
        const hit = await cache.match(req);
        if (hit) return hit;
        throw new Error('offline');
      }
    }),
  );
});

// 알림 버튼: '기록하기'·'지금은 안 해요'를 열려 있는 앱에 전하고, 앱이 닫혀 있으면 열면서 주소로 전한다.
self.addEventListener('notificationclick', (e) => {
  const n = e.notification;
  const data = n.data || {};
  const action = e.action === 'record' || e.action === 'skip' ? e.action : 'open';
  n.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (list) => {
      const msg = { type: 'dayset-notify', action, activity: data.activity, skipId: data.skipId };
      if (list.length) {
        const c = list[0];
        c.postMessage(msg);
        if ('focus' in c) await c.focus();
        return;
      }
      const q = action === 'open' ? '' : `?n=${action}&a=${data.activity || ''}&b=${encodeURIComponent(data.skipId || '')}`;
      await self.clients.openWindow(`./${q}`);
    }),
  );
});

// 서버 푸시(앱 버전): 받은 내용을 그대로 알림으로 띄운다.
self.addEventListener('push', (e) => {
  let d = {};
  try {
    d = e.data ? e.data.json() : {};
  } catch {
    d = { title: 'DaySet', body: e.data ? e.data.text() : '' };
  }
  e.waitUntil(self.registration.showNotification(d.title || 'DaySet', { body: d.body || '', tag: d.tag || 'dayset-now', data: d.data || {} }));
});
