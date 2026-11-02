import { APK_URL, appTarget, getAppUrl, isGetAppLink, platformOf } from '../appLinks';

describe('휴대폰 앱 받는 곳', () => {
  it('휴대폰 종류를 가린다', () => {
    expect(platformOf('Mozilla/5.0 (Linux; Android 14; SM-S921N)')).toBe('android');
    expect(platformOf('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)')).toBe('ios');
    expect(platformOf('Mozilla/5.0 (Windows NT 10.0; Win64; x64)')).toBe('other');
  });

  it('QR 주소는 웹 주소 + ?get=app', () => {
    expect(getAppUrl({ origin: 'https://kimoqui.github.io', pathname: '/Dayset/' })).toBe('https://kimoqui.github.io/Dayset/?get=app');
    expect(isGetAppLink('?get=app')).toBe(true);
    expect(isGetAppLink('?t=2026-11-02')).toBe(false);
  });

  it('스토어 출시 전: 안드로이드는 APK, 아이폰은 준비 중 안내', () => {
    expect(appTarget('android').url).toBe(APK_URL);
    expect(appTarget('ios').url).toBeNull();
    expect(appTarget('ios').note).toContain('홈 화면에 추가');
  });
});
