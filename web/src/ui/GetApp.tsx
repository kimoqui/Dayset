// 휴대폰 앱 연결: 설정의 QR 카드, QR로 연 '앱 받기' 화면(?get=app).
// QR은 늘 같은 주소를 담는다. 스토어 출시 뒤에는 src/app/appLinks.ts의 PLAY_URL·APPSTORE_URL만 채우면 된다.

import QRCode from 'qrcode';
import { useEffect, useState } from 'react';
import { appTarget, getAppUrl, platformOf } from '../app/appLinks';
import { useCloud } from './Account';
import { Icon } from './kit';

function useQr(text: string): string | null {
  const [qr, setQr] = useState<string | null>(null);
  useEffect(() => {
    // QR은 어두운 화면에서도 읽히도록 흰 바탕·짙은 점으로 고정한다.
    QRCode.toDataURL(text, { margin: 1, width: 360, errorCorrectionLevel: 'M', color: { dark: '#0D1220', light: '#FFFFFF' } })
      .then(setQr)
      .catch(() => setQr(null));
  }, [text]);
  return qr;
}

/** 설정: 휴대폰 앱 연결 카드. */
export function AppConnectCard({ toast }: { toast: (t: string) => void }) {
  const url = getAppUrl();
  const qr = useQr(url);
  const v = useCloud();
  const android = appTarget('android');
  return (
    <section className="card app-connect" aria-label="휴대폰 앱 연결">
      <div className="col" style={{ gap: 2 }}>
        <span className="t-h2">휴대폰 앱 연결</span>
        <span className="t-label">휴대폰 카메라로 QR을 찍으면 앱 받는 곳으로 가요</span>
      </div>
      <div className="app-connect-body">
        {qr ? <img className="qr" src={qr} width={160} height={160} alt="휴대폰 앱 받는 곳 QR 코드" /> : <div className="qr" aria-hidden="true" />}
        <ol className="app-steps">
          <li>QR을 찍어 앱을 설치해요 <span className="t-label">(안드로이드 베타 · 아이폰 준비 중)</span></li>
          <li>{v.session ? <>앱에서 <strong>{v.session.email}</strong>으로 로그인해요</> : '이 브라우저와 같은 계정으로 로그인해요'}</li>
          <li>기록·일정이 웹과 앱에서 이어져요</li>
        </ol>
      </div>
      {!v.session && <span className="t-label">아직 로그인하지 않았어요. 위 '계정'에서 로그인하면 앱과 기록이 이어져요.</span>}
      <div className="row" style={{ gap: 8, flexWrap: 'wrap' }}>
        {android.url && (
          <a className="btn small" href={android.url}>
            {android.label}
          </a>
        )}
        <button
          type="button"
          className="btn small"
          onClick={() => {
            navigator.clipboard?.writeText(url).then(
              () => toast('앱 받는 주소를 복사했어요'),
              () => toast(url),
            );
          }}
        >
          주소 복사
        </button>
      </div>
    </section>
  );
}

/** QR로 연 화면: 휴대폰 종류에 맞는 받는 곳을 보여 준다. */
export function GetAppPage({ onContinue }: { onContinue: () => void }) {
  const p = platformOf(navigator.userAgent);
  const target = appTarget(p);
  const qr = useQr(getAppUrl());
  return (
    <div className="app">
      <div className="screen plain get-app" style={{ paddingTop: 48 }}>
        <span className="nav-logo">DaySet</span>
        <h1 className="t-title">휴대폰에서 이어 쓰기</h1>
        <p className="t-body muted" style={{ margin: 0 }}>
          자동으로 짜주는 일정을 휴대폰 앱으로 받아요. 알람·기록 버튼은 앱에서 더 잘 동작해요.
        </p>
        {p === 'other' ? (
          <section className="card stack" style={{ alignItems: 'center' }}>
            {qr && <img className="qr" src={qr} width={200} height={200} alt="휴대폰 앱 받는 곳 QR 코드" />}
            <span className="t-body">휴대폰 카메라로 이 QR을 찍어 주세요.</span>
          </section>
        ) : (
          <section className="card stack">
            <span className="t-h2">{p === 'ios' ? '아이폰' : '안드로이드'}</span>
            <span className="t-body">{target.note}</span>
            {target.url ? (
              <a className="btn primary block" href={target.url}>
                <Icon name="forward" size={18} /> {target.label}
              </a>
            ) : (
              <span className="pill gray">{target.label}</span>
            )}
          </section>
        )}
        <button type="button" className="btn block" onClick={onContinue}>
          웹에서 계속 쓰기
        </button>
      </div>
    </div>
  );
}
