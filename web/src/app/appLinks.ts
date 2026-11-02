// 휴대폰 앱 받는 곳. 스토어에 올리면 PLAY_URL·APPSTORE_URL만 채우면 된다.
// 설정의 QR은 늘 같은 주소(웹 주소 + ?get=app)를 담고, 그 주소가 휴대폰 종류에 맞는 곳으로 안내한다.
// 그래서 스토어 출시 뒤에도 이미 나눠 준 QR·링크를 바꿀 필요가 없다.

export const APK_URL = 'https://github.com/kimoqui/Dayset/releases/latest/download/DaySet.apk';
/** 구글 플레이 주소(출시 전 빈 값 → APK로 안내). */
export const PLAY_URL = '';
/** 앱스토어 주소(출시 전 빈 값 → 웹을 홈 화면에 추가하도록 안내). */
export const APPSTORE_URL = '';

export type Platform = 'android' | 'ios' | 'other';

export function platformOf(ua: string): Platform {
  if (/Android/i.test(ua)) return 'android';
  if (/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && /Mobile/i.test(ua))) return 'ios';
  return 'other';
}

/** QR에 담는 주소: 지금 웹 주소 + ?get=app */
export function getAppUrl(loc: { origin: string; pathname: string } = location): string {
  return `${loc.origin}${loc.pathname}?get=app`;
}

/** ?get=app 으로 열었는지 */
export function isGetAppLink(search: string = location.search): boolean {
  return new URLSearchParams(search).get('get') === 'app';
}

export interface AppTarget {
  /** 누를 곳(없으면 아직 받을 곳이 없음) */
  url: string | null;
  label: string;
  note: string;
}

/** 휴대폰 종류에 맞는 받는 곳. */
export function appTarget(p: Platform): AppTarget {
  if (p === 'ios') {
    return APPSTORE_URL
      ? { url: APPSTORE_URL, label: '앱스토어에서 받기', note: '설치한 뒤 같은 계정으로 로그인하면 기록이 이어져요.' }
      : { url: null, label: '아이폰 앱 준비 중', note: '아이폰 앱은 준비 중이에요. 지금은 이 웹을 Safari 공유 → 홈 화면에 추가해 쓰고, 같은 계정으로 로그인하면 기록이 이어져요.' };
  }
  if (PLAY_URL) return { url: PLAY_URL, label: '구글 플레이에서 받기', note: '설치한 뒤 같은 계정으로 로그인하면 기록이 이어져요.' };
  return {
    url: APK_URL,
    label: '안드로이드 앱 받기',
    note: "베타 앱이에요. 처음 설치할 때 '출처를 알 수 없는 앱 설치'를 허용해야 해요. 설치한 뒤 같은 계정으로 로그인하면 기록이 이어져요.",
  };
}
