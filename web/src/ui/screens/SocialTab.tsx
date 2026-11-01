import QRCode from 'qrcode';
import { useEffect, useMemo, useRef, useState } from 'react';
import { anonName, cellOf, nearbyBoard } from '../../app/nearby';
import { makeFriendCode, readFriendCode } from '../../app/social';
import type { AppState } from '../../app/state';
import type { StreakInfo } from '../../app/streak';
import { addFriend, addNearby, now as clockNow, removeNearby, setNearbyOn } from '../../app/store';
import { Flame, Icon, Segmented, Sheet, Switch, TopBar } from '../kit';
import { haptic } from '../motion';
import { Friends, StreakCard } from '../Social';

type View = 'nearby' | 'friends';

/**
 * 프리뷰 빌드는 위치를 읽지 않는다(위치기반서비스 신고·검토 전). QR·코드를 주고받은 사람만 근처 순위에 올라온다.
 * 위치를 쓰려면 빌드할 때 VITE_NEARBY_LOCATION=on.
 */
export const NEARBY_USES_LOCATION = import.meta.env.VITE_NEARBY_LOCATION === 'on';

/** 소셜: 내 연속 기록 공유, 근처 사람들(익명)과 겨루기, 친구와 겨루기. */
export function SocialTab({ s, info, toast }: { s: AppState; info: StreakInfo; toast: (t: string) => void }) {
  const [view, setView] = useState<View>('nearby');
  return (
    <div className="screen">
      <TopBar title="소셜" />
      <StreakCard s={s} info={info} toast={toast} />
      <Segmented<View>
        label="누구와"
        value={view}
        onChange={setView}
        options={[
          { value: 'nearby', label: '근처 (익명)' },
          { value: 'friends', label: '친구' },
        ]}
      />
      {view === 'nearby' ? <Nearby s={s} info={info} toast={toast} /> : <Friends s={s} info={info} toast={toast} />}
    </div>
  );
}

const MEDAL = ['#F4B04F', '#C3CADB', '#C9895A'];

function Nearby({ s, info, toast }: { s: AppState; info: StreakInfo; toast: (t: string) => void }) {
  const [busy, setBusy] = useState(false);
  const [exchange, setExchange] = useState(false);
  const me = anonName(s.profile.id);
  const n = s.nearby;
  const board = useMemo(() => nearbyBoard(s.profile.id, info, n, clockNow()), [s.profile.id, info, n]);
  const hasDemo = n.people.some((p) => p.demo);

  const turnOn = (on: boolean) => {
    if (!on) {
      setNearbyOn(false);
      toast('근처에 보이지 않게 했어요');
      return;
    }
    if (!NEARBY_USES_LOCATION) {
      setNearbyOn(true);
      toast("익명으로 켰어요. QR을 주고받은 사람만 순위에 보여요");
      return;
    }
    if (!('geolocation' in navigator)) {
      setNearbyOn(true);
      toast('위치 없이 켰어요. 거리 표시는 빠져요');
      return;
    }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (p) => {
        setBusy(false);
        setNearbyOn(true, cellOf(p.coords.latitude, p.coords.longitude));
        toast('약 2km 범위로만 근처에 익명으로 보여요');
      },
      () => {
        setBusy(false);
        setNearbyOn(true);
        toast('위치를 쓰지 않고 켰어요. 거리 표시는 빠져요');
      },
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 10 * 60000 },
    );
  };

  return (
    <>
      <section className="card" aria-label="근처 공개">
        <Switch
          checked={n.on}
          onChange={turnOn}
          label="근처에 익명으로 보이기"
          sub={busy ? '위치를 확인하는 중…' : NEARBY_USES_LOCATION ? `실명 대신 '${me}'로 보여요 · 위치는 약 2km 칸으로만` : `실명 대신 '${me}'로 보여요 · 프리뷰에서는 위치를 쓰지 않아요`}
          onText="보이는 중"
          offText="꺼짐"
        />
      </section>

      {n.on ? (
        <>
          <section className="card" aria-label="내 주변 이번 주 순위">
            <div className="row between">
              <h2 className="t-h2">내 주변 이번 주</h2>
              {hasDemo && <span className="demo-tag">예시 포함</span>}
            </div>
            <div className="near-sum">
              <div>
                <span className="t-label">내 순위</span>
                <span className="num strong">
                  {board.myRank}위<small> / {board.rows.length}명</small>
                </span>
              </div>
              <div>
                <span className="t-label">상위</span>
                <span className="num strong accent">{board.topPercent}%</span>
              </div>
              <div>
                <span className="t-label">근처 평균</span>
                <span className="num strong">{board.avgWeek.toFixed(1)}일</span>
              </div>
            </div>
            <div className="rank-list">
              {board.rows.map((r, i) => (
                <div key={r.id} className={`rank-row ${r.me ? 'me' : ''}`}>
                  <span className="rank-no" style={i < 3 && board.rows.length > 1 ? { background: MEDAL[i], color: '#1A1300' } : undefined}>
                    {i + 1}
                  </span>
                  <span className="col grow" style={{ gap: 0, minWidth: 0 }}>
                    <span className="strong ellipsis">
                      {r.name}
                      {r.me && <span className="t-label"> · 나</span>}
                      {r.demo && <span className="demo-tag sm">예시</span>}
                    </span>
                    <span className="t-small row" style={{ gap: 4 }}>
                      <Flame size={12} color={r.streak > 0 ? 'var(--accent)' : 'var(--line-btn)'} /> {r.streak}일 연속
                      {r.band && ` · ${r.band}`}
                    </span>
                  </span>
                  <span className="rank-score num">
                    {r.weekSetDays}
                    <small>일</small>
                  </span>
                  {!r.me && (
                    <button type="button" className="icon-btn" aria-label={`${r.name} 빼기`} onClick={() => removeNearby(r.id)} style={{ width: 36, height: 36, marginRight: -8 }}>
                      <Icon name="close" size={16} />
                    </button>
                  )}
                </div>
              ))}
            </div>
            <button type="button" className="btn primary block" onClick={() => setExchange(true)}>
              <Icon name="share" size={18} /> 가까운 사람과 QR로 주고받기
            </button>
            <span className="t-label">
              로컬 버전은 서버 없이, 옆에 있는 사람과 QR·코드를 직접 주고받아 순위에 올려요. 앱 버전에서는 같은 동네 사람들이 자동으로 보여요.
            </span>
          </section>
        </>
      ) : (
        <div className="card">
          <span className="t-body">켜면 이름 없이 별명과 셋 데이 수만 근처 사람들에게 보여요. 끄면 바로 사라져요.</span>
          <span className="t-label">{NEARBY_USES_LOCATION ? '보이는 것: 익명 별명, 이번 주 셋 데이 수, 연속 일수, 대략 거리(2km 단위) · 보이지 않는 것: 이름, 정확한 위치, 기록 내용' : '보이는 것: 익명 별명, 이번 주 셋 데이 수, 연속 일수 · 보이지 않는 것: 이름, 위치, 기록 내용. 프리뷰에서는 QR을 주고받은 사람만 순위에 올라와요.'}</span>
        </div>
      )}

      {exchange && <Exchange s={s} info={info} me={me} onClose={() => setExchange(false)} toast={toast} />}
    </>
  );
}

/** 가까운 사람과 익명 코드 주고받기: 내 QR 보여 주기 + 상대 QR 찍기(지원 기기) 또는 코드 붙여 넣기. */
function Exchange({ s, info, me, onClose, toast }: { s: AppState; info: StreakInfo; me: string; onClose: () => void; toast: (t: string) => void }) {
  const code = useMemo(() => makeFriendCode({ id: s.profile.id, name: me }, info, clockNow(), { anon: true, cell: s.nearby.cell }), [s.profile.id, me, info, s.nearby.cell]);
  const [qr, setQr] = useState<string | null>(null);
  const [mode, setMode] = useState<'show' | 'scan'>('show');
  const [text, setText] = useState('');
  const canScan = typeof window !== 'undefined' && 'BarcodeDetector' in window;

  useEffect(() => {
    QRCode.toDataURL(code, { margin: 1, width: 480, errorCorrectionLevel: 'M', color: { dark: '#0D1220', light: '#FFFFFF' } })
      .then(setQr)
      .catch(() => setQr(null));
  }, [code]);

  const accept = (raw: string) => {
    const f = readFriendCode(raw);
    if (!f) {
      toast('코드를 찾지 못했어요');
      return false;
    }
    haptic(14);
    const r = f.anon ? addNearby(f) : addFriend(f);
    toast(r === 'self' ? '내 코드예요' : f.anon ? `${f.name}님이 근처 순위에 올라왔어요` : `${f.name}님을 친구 순위에 넣었어요`);
    if (r !== 'self') onClose();
    return r !== 'self';
  };

  return (
    <Sheet title="가까운 사람과 주고받기" onClose={onClose}>
      <Segmented<'show' | 'scan'>
        label="주고받기"
        value={mode}
        onChange={setMode}
        options={[
          { value: 'show', label: '내 QR 보여 주기' },
          { value: 'scan', label: '상대 QR 받기' },
        ]}
      />
      {mode === 'show' ? (
        <div className="qr-box">
          {qr ? <img src={qr} alt={`${me}의 익명 코드 QR`} width={220} height={220} /> : <div className="qr-ph">QR을 만드는 중…</div>}
          <span className="strong">{me}</span>
          <span className="t-label">이번 주 셋 데이 {info.weekSetDays}일 · {info.current}일 연속 · 이름과 정확한 위치는 들어 있지 않아요</span>
          <button
            type="button"
            className="btn small"
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(code);
                toast('코드를 복사했어요');
              } catch {
                toast('복사하지 못했어요');
              }
            }}
          >
            코드 복사
          </button>
        </div>
      ) : (
        <div className="stack" style={{ gap: 10 }}>
          {canScan ? <Scanner onCode={accept} /> : <span className="t-label">이 브라우저는 QR 찍기를 지원하지 않아요. 상대 화면의 '코드 복사'를 받아 붙여 넣어 주세요.</span>}
          <textarea className="input" style={{ height: 96, padding: 12, resize: 'none' }} value={text} onChange={(e) => setText(e.target.value)} placeholder="DS1-… 코드 붙여 넣기" />
          <button type="button" className="btn primary block" disabled={!text.trim()} onClick={() => accept(text)}>
            넣기
          </button>
        </div>
      )}
    </Sheet>
  );
}

interface Detector {
  detect: (src: CanvasImageSource) => Promise<{ rawValue: string }[]>;
}

/** 카메라로 QR 읽기(BarcodeDetector가 있는 기기에서만). */
function Scanner({ onCode }: { onCode: (raw: string) => boolean }) {
  const video = useRef<HTMLVideoElement>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let stream: MediaStream | null = null;
    let timer: number | undefined;
    let done = false;
    const Ctor = (window as unknown as { BarcodeDetector: new (o: { formats: string[] }) => Detector }).BarcodeDetector;
    const det = new Ctor({ formats: ['qr_code'] });
    navigator.mediaDevices
      ?.getUserMedia({ video: { facingMode: 'environment' } })
      .then((st) => {
        stream = st;
        if (!video.current) return;
        video.current.srcObject = st;
        void video.current.play();
        const tick = async () => {
          if (done || !video.current) return;
          try {
            const r = await det.detect(video.current);
            if (r[0]?.rawValue && onCode(r[0].rawValue)) {
              done = true;
              return;
            }
          } catch {
            // 다음 프레임에 다시
          }
          timer = window.setTimeout(tick, 300);
        };
        void tick();
      })
      .catch(() => setErr('카메라를 쓸 수 없어요. 코드를 붙여 넣어 주세요.'));
    return () => {
      done = true;
      window.clearTimeout(timer);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [onCode]);
  return err ? <span className="t-label miss">{err}</span> : <video ref={video} className="qr-video" playsInline muted />;
}
