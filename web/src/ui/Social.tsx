import { useState } from 'react';
import { fromKey, weekdayLabel } from '../engine/models';
import { leaderboard, makeFriendCode, readFriendCode } from '../app/social';
import type { AppState } from '../app/state';
import type { StreakInfo } from '../app/streak';
import { addFriend, now, removeFriend, setProfileName, track } from '../app/store';
import { Flame, Icon, Sheet } from './kit';
import { haptic } from './motion';
import { type CardData, RESULT_TEXT, shareCard, shareMessage, shareText } from './share';

export function cardData(s: AppState, info: StreakInfo): CardData {
  return {
    name: s.profile.name,
    streak: info.current,
    best: info.best,
    week: info.week,
    weekSetDays: info.weekSetDays,
    monthSetDays: info.monthSetDays,
  };
}

/** 카카오톡·인스타그램 공유 버튼. */
export function ShareButtons({ s, info, toast }: { s: AppState; info: StreakInfo; toast: (t: string) => void }) {
  const [busy, setBusy] = useState(false);
  const run = async (kind: 'kakao' | 'insta') => {
    if (busy) return;
    setBusy(true);
    haptic(8);
    const d = cardData(s, info);
    const code = makeFriendCode(s.profile, info, now());
    const r = await shareCard(kind === 'insta' ? 'story' : 'square', d, shareMessage(d, kind === 'kakao' ? code : undefined));
    setBusy(false);
    if (r !== 'cancelled') {
      toast(RESULT_TEXT[r]);
      track('share', kind);
    }
  };
  return (
    <div className="share-row">
      <button type="button" className="btn share-kakao" disabled={busy} onClick={() => run('kakao')}>
        <Icon name="chat" size={18} /> 카카오톡 공유
      </button>
      <button type="button" className="btn share-insta" disabled={busy} onClick={() => run('insta')}>
        <Icon name="share" size={18} /> 인스타 스토리
      </button>
    </div>
  );
}

const MARK_LABEL = { set: '셋 데이', rest: '쉬는 날', miss: '놓친 날', today: '오늘', none: '기록 없음', future: '예정' } as const;

/** 듀오링고식 연속 기록 카드. */
export function StreakCard({ s, info, toast, share = true }: { s: AppState; info: StreakInfo; toast: (t: string) => void; share?: boolean }) {
  return (
    <section className="card streak-card" aria-label="연속 셋 데이">
      <div className="row" style={{ gap: 14, alignItems: 'center' }}>
        <span className={`streak-flame ${info.current > 0 ? 'on' : ''}`}>
          <Flame size={40} color={info.current > 0 ? 'var(--accent)' : 'var(--line-btn)'} />
        </span>
        <div className="col grow" style={{ gap: 0 }}>
          <span className="streak-num num">
            {info.current}
            <small>일 연속</small>
          </span>
          <span className="t-label">
            최고 기록 {info.best}일{info.nextMilestone != null ? ` · 다음 기념일까지 ${info.nextMilestone}일` : ''}
          </span>
        </div>
      </div>
      {!info.todayDone && (
        <p className="t-body accent strong" style={{ margin: 0 }}>
          오늘 셋 데이를 채우면 {info.current + 1}일 연속이에요
        </p>
      )}
      <div className="streak-week">
        {info.week.map((d) => (
          <span key={d.key} className={`sw ${d.mark}`} title={`${weekdayLabel(fromKey(d.key))} ${MARK_LABEL[d.mark]}`}>
            <span className="sw-c">{d.mark === 'set' ? <Flame size={16} color="var(--accent-ink)" /> : d.mark === 'rest' ? <span className="dot" /> : null}</span>
            <span className="t-small">{weekdayLabel(fromKey(d.key))}</span>
          </span>
        ))}
      </div>
      {share && <ShareButtons s={s} info={info} toast={toast} />}
    </section>
  );
}

/** 받침이 있으면 '과', 없으면 '와'. */
function withParticle(word: string): string {
  const c = word.codePointAt(word.length - 1) ?? 0;
  return c >= 0xac00 && c <= 0xd7a3 && (c - 0xac00) % 28 !== 0 ? '과' : '와';
}

const MEDAL = ['#F4B04F', '#C3CADB', '#C9895A'];

function ago(d: Date | null, t: Date): string {
  if (!d) return '';
  const m = Math.max(0, Math.round((t.getTime() - d.getTime()) / 60000));
  if (m < 60) return `${m}분 전`;
  if (m < 60 * 24) return `${Math.round(m / 60)}시간 전`;
  return `${Math.round(m / 1440)}일 전`;
}

/** 친구와 겨루기: 이번 주 셋 데이 순위. */
export function Friends({ s, info, toast }: { s: AppState; info: StreakInfo; toast: (t: string) => void }) {
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState(s.profile.name);
  const t = now();
  const rows = leaderboard(s.profile, info, s.friends, t);
  const myRank = rows.findIndex((r) => r.me) + 1;
  const leader = rows[0];
  const gap = leader && !leader.me ? leader.weekSetDays - info.weekSetDays : 0;

  const sendCode = async () => {
    haptic(8);
    const code = makeFriendCode(s.profile, info, t);
    const r = await shareText(shareMessage(cardData(s, info), code));
    if (r !== 'cancelled') {
      toast(RESULT_TEXT[r]);
      track('share', 'code');
    }
  };

  return (
    <>
      {!s.profile.name && (
        <section className="card" aria-label="내 이름">
          <span className="t-h2">친구에게 보일 이름</span>
          <div className="row" style={{ gap: 8 }}>
            <input className="input grow" value={name} maxLength={12} placeholder="예: 대희" onChange={(e) => setName(e.target.value)} />
            <button type="button" className="btn primary" disabled={!name.trim()} onClick={() => setProfileName(name)}>
              저장
            </button>
          </div>
        </section>
      )}

      <section className="card" aria-label="이번 주 순위">
        <div className="row between">
          <h2 className="t-h2">이번 주 순위</h2>
          <span className="t-label">셋 데이 → 연속 기록 순</span>
        </div>
        <p className="t-body" style={{ margin: 0 }}>
          {rows.length === 1
            ? '아직 친구가 없어요. 내 코드를 보내고 친구 코드를 받아 보세요.'
            : myRank === 1
              ? <><strong className="accent">1위</strong>예요. 이번 주를 지켜요.</>
              : <>지금 <strong className="accent">{myRank}위</strong> · 1위까지 셋 데이 {Math.max(1, gap)}일</>}
        </p>
        <div className="rank-list">
          {rows.map((r, i) => (
            <div key={r.id} className={`rank-row ${r.me ? 'me' : ''}`}>
              <span className="rank-no" style={i < 3 && rows.length > 1 ? { background: MEDAL[i], color: '#1A1300' } : undefined}>
                {i + 1}
              </span>
              <span className="col grow" style={{ gap: 0, minWidth: 0 }}>
                <span className="strong ellipsis">
                  {r.name}
                  {r.me && <span className="t-label"> · 나</span>}
                </span>
                <span className="t-small row" style={{ gap: 4 }}>
                  <Flame size={12} color={r.streak > 0 ? 'var(--accent)' : 'var(--line-btn)'} /> {r.streak}일 연속
                  {!r.me && ` · ${r.stale ? '지난주 기록 · ' : ''}${ago(r.updatedAt, t)}`}
                </span>
              </span>
              <span className="rank-score num">
                {r.weekSetDays}
                <small>일</small>
              </span>
              {!r.me && (
                <button type="button" className="icon-btn" aria-label={`${r.name} 빼기`} onClick={() => removeFriend(r.id)} style={{ width: 36, height: 36, marginRight: -8 }}>
                  <Icon name="close" size={16} />
                </button>
              )}
            </div>
          ))}
        </div>
        <div className="share-row">
          <button type="button" className="btn share-kakao" onClick={sendCode}>
            <Icon name="chat" size={18} /> 내 코드 보내기
          </button>
          <button type="button" className="btn" onClick={() => setAdding(true)}>
            <Icon name="plus" size={18} /> 친구 코드 넣기
          </button>
        </div>
        <span className="t-label">
          로컬 버전은 서로 코드를 보낼 때 순위가 바뀌어요. 앱 버전에서는 친구 순위가 실시간으로 바뀌어요.
        </span>
      </section>

      {s.profile.name && (
        <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => setProfileName('')}>
          이름 바꾸기 ({s.profile.name})
        </button>
      )}

      {adding && <AddFriend onClose={() => setAdding(false)} toast={toast} />}
    </>
  );
}

function AddFriend({ onClose, toast }: { onClose: () => void; toast: (t: string) => void }) {
  const [text, setText] = useState('');
  const f = text.trim() ? readFriendCode(text) : null;
  return (
    <Sheet title="친구 코드 넣기" onClose={onClose}>
      <p className="t-label" style={{ margin: 0 }}>
        카카오톡으로 받은 메시지를 통째로 붙여 넣어도 돼요. 'DS1-'로 시작하는 코드를 찾아 읽어요.
      </p>
      <textarea className="input" style={{ height: 120, padding: 12, resize: 'none' }} value={text} onChange={(e) => setText(e.target.value)} placeholder="DS1-..." autoFocus />
      {text.trim() && !f && <span className="t-label miss">코드를 찾지 못했어요</span>}
      {f && (
        <div className="card" style={{ padding: '12px 14px' }}>
          <span className="strong">{f.name}</span>
          <span className="t-label">
            {f.streak}일 연속 · 이번 주 셋 데이 {f.weekSetDays}일
          </span>
        </div>
      )}
      <button
        type="button"
        className="btn primary block"
        disabled={!f}
        onClick={() => {
          if (!f) return;
          const r = addFriend(f);
          haptic(10);
          toast(r === 'self' ? '내 코드예요. 친구 코드를 넣어 주세요' : r === 'updated' ? `${f.name}의 기록을 새로 받았어요` : `${f.name}${withParticle(f.name)} 겨루기 시작!`);
          if (r !== 'self') onClose();
        }}
      >
        넣기
      </button>
    </Sheet>
  );
}

/** 기념일 축하(3·7·14·30일…). */
export function Celebrate({ s, info, days, onClose, toast }: { s: AppState; info: StreakInfo; days: number; onClose: () => void; toast: (t: string) => void }) {
  return (
    <div className="pop-back" onClick={onClose}>
      <div className="pop celebrate" role="alertdialog" aria-modal="true" aria-label={`${days}일 연속 달성`} onClick={(e) => e.stopPropagation()}>
        <div className="burst" aria-hidden="true">
          {Array.from({ length: 12 }, (_, i) => (
            <i key={i} style={{ ['--a' as string]: `${i * 30}deg` }} />
          ))}
        </div>
        <span className="celebrate-flame">
          <Flame size={84} />
        </span>
        <span className="streak-num num" style={{ textAlign: 'center', fontSize: 56, lineHeight: '60px' }}>
          {days}
          <small>일 연속</small>
        </span>
        <h2 style={{ textAlign: 'center' }}>셋 데이 {days}일 연속 달성!</h2>
        <p className="t-body" style={{ margin: 0, textAlign: 'center', color: 'var(--ink-soft)' }}>
          {days >= 30 ? '한 달을 지켰어요. 이제 습관이 됐어요.' : days >= 7 ? '일주일을 지켰어요. 이 흐름을 이어 가요.' : '좋은 시작이에요. 내일도 이어 가요.'}
        </p>
        <ShareButtons s={s} info={info} toast={toast} />
        <button type="button" className="btn block" onClick={onClose}>
          계속하기
        </button>
      </div>
    </div>
  );
}
