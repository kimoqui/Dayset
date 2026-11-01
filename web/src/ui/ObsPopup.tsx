import { useEffect } from 'react';
import { Icon } from './kit';

export type ObsPopupKind = 'intro' | 'late';

const SECONDS = 10;

/**
 * 관찰 준비일(1일차 전날) 안내 팝업. 10초 뒤 저절로 닫힌다.
 * - intro: 처음 시작했을 때
 * - late: 밤 10시가 넘었는데 아직 '수면'을 누르지 않았을 때 한 번 더
 */
export function ObsPopup({ kind, onClose, onSleep }: { kind: ObsPopupKind; onClose: () => void; onSleep: () => void }) {
  useEffect(() => {
    const id = window.setTimeout(onClose, SECONDS * 1000);
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => {
      window.clearTimeout(id);
      window.removeEventListener('keydown', onKey);
    };
  }, [onClose]);

  return (
    <div className="pop-back" onClick={onClose}>
      <div className="pop" role="alertdialog" aria-modal="true" aria-label="관찰 안내" onClick={(e) => e.stopPropagation()}>
        <span className="badge">{kind === 'late' ? '잘 시간이 가까워요' : '내일이 1일차'}</span>
        <h2>내일 하루를 그대로 기록해요</h2>
        <div className="key">
          <span className="c">
            <Icon name="sleep" size={22} />
          </span>
          <span>오늘 밤 잘 때 '수면'을 눌러 주세요</span>
        </div>
        <p className="t-body" style={{ margin: 0, color: 'var(--ink-soft)' }}>
          내일은 식사·업무·운동을 시작할 때마다 버튼만 누르면 돼요. 내일 저녁에 기록한 하루를 보고 일정을 같이 정해요.
        </p>
        <div className="row" style={{ gap: 8 }}>
          {kind === 'late' ? (
            <>
              <button type="button" className="btn primary grow" onClick={onSleep}>
                지금 잘게요 · 수면 시작
              </button>
              <button type="button" className="btn" onClick={onClose}>
                조금 뒤에
              </button>
            </>
          ) : (
            <button type="button" className="btn primary grow" onClick={onClose}>
              알겠어요
            </button>
          )}
        </div>
        <span className="timer" style={{ animationDuration: `${SECONDS}s` }} />
      </div>
    </div>
  );
}
