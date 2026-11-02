// 화면 모션(토스 참고): 손가락을 따라오는 탭 스와이프, 스프링 복귀, 방향이 있는 탭 전환.
// 모션 줄이기 설정을 켠 기기에서는 애니메이션 없이 바로 바뀐다.

import { useCallback, useEffect, useRef, useState } from 'react';

export const EASE_OUT = 'cubic-bezier(0.16, 1, 0.3, 1)'; // 빠르게 나가서 부드럽게 멈춤
export const EASE_IN = 'cubic-bezier(0.4, 0, 1, 1)';
export const SPRING = 'cubic-bezier(0.34, 1.56, 0.64, 1)'; // 살짝 튕김

export const reducedMotion = (): boolean => {
  try {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    return false;
  }
};

/** 짧은 진동(지원하는 기기만). 토스처럼 스위치·버튼에 가벼운 손맛을 준다. */
export function haptic(ms = 8): void {
  try {
    navigator.vibrate?.(ms);
  } catch {
    // 진동을 지원하지 않는 기기
  }
}

const IGNORE = 'input, textarea, select, [contenteditable], .sheet-back, .pop-back, .no-swipe';

/**
 * 탭 페이지 스와이프.
 * - 가로로 움직이면 화면이 손가락을 따라오고, 양 끝 탭에서는 고무줄처럼 덜 따라온다.
 * - 화면 너비의 22% 이상 밀거나 빠르게 넘기면 옆 탭으로, 아니면 스프링으로 제자리.
 * - 세로 스크롤은 그대로 둔다(touch-action: pan-y).
 */
export function useSwipeTabs<T extends string>(opts: { tabs: T[]; current: T | null; onChange: (t: T) => void }) {
  const ref = useRef<HTMLDivElement | null>(null);
  // 화면이 나중에 생겨도(온보딩 → 홈) 손가락 이벤트를 붙이도록 콜백 ref를 쓴다.
  const [node, setNode] = useState<HTMLDivElement | null>(null);
  const attach = useCallback((el: HTMLDivElement | null) => {
    ref.current = el;
    setNode(el);
  }, []);
  const optsRef = useRef(opts);
  optsRef.current = opts;
  const busy = useRef(false);

  const clear = (el: HTMLElement) => {
    // transform이 남아 있으면 안쪽의 고정(fixed) 창 위치가 틀어지므로 끝나면 지운다.
    el.style.transition = '';
    el.style.transform = '';
    el.style.opacity = '';
    el.style.willChange = '';
  };

  /** 방향이 있는 탭 전환: 지금 화면은 반대쪽으로 빠지고, 새 화면이 들어온다. */
  const go = useCallback((next: T, dirHint?: 1 | -1) => {
    const { tabs, current, onChange } = optsRef.current;
    const el = ref.current;
    if (!current || next === current) return;
    const dir = dirHint ?? (tabs.indexOf(next) > tabs.indexOf(current) ? 1 : -1);
    if (!el || reducedMotion()) {
      onChange(next);
      window.scrollTo(0, 0);
      return;
    }
    busy.current = true;
    el.style.willChange = 'transform, opacity';
    el.style.transition = `transform 150ms ${EASE_IN}, opacity 150ms ${EASE_IN}`;
    el.style.transform = `translateX(${-dir * 24}%)`;
    el.style.opacity = '0';
    window.setTimeout(() => {
      onChange(next);
      window.scrollTo(0, 0);
      el.style.transition = 'none';
      el.style.transform = `translateX(${dir * 24}%)`;
      requestAnimationFrame(() =>
        requestAnimationFrame(() => {
          el.style.transition = `transform 380ms ${EASE_OUT}, opacity 240ms ease-out`;
          el.style.transform = 'translateX(0)';
          el.style.opacity = '1';
          window.setTimeout(() => {
            clear(el);
            busy.current = false;
          }, 400);
        }),
      );
    }, 140);
  }, []);

  useEffect(() => {
    const el = node;
    if (!el) return;
    let start: { x: number; y: number; t: number; id: number } | null = null;
    let mode: 'undecided' | 'h' | 'v' = 'undecided';
    let dx = 0;
    let lastX = 0;
    let lastT = 0;
    let vx = 0;

    const down = (e: PointerEvent) => {
      if (busy.current || !optsRef.current.current) return;
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      if ((e.target as Element).closest(IGNORE)) return;
      start = { x: e.clientX, y: e.clientY, t: e.timeStamp, id: e.pointerId };
      mode = 'undecided';
      dx = 0;
      lastX = e.clientX;
      lastT = e.timeStamp;
      vx = 0;
    };
    const move = (e: PointerEvent) => {
      if (!start || e.pointerId !== start.id) return;
      const mx = e.clientX - start.x;
      const my = e.clientY - start.y;
      if (mode === 'undecided') {
        if (Math.abs(mx) < 10 && Math.abs(my) < 10) return;
        mode = Math.abs(mx) > Math.abs(my) * 1.2 ? 'h' : 'v';
        if (mode === 'h') {
          el.style.transition = 'none';
          el.style.willChange = 'transform';
          try {
            el.setPointerCapture(e.pointerId);
          } catch {
            // 캡처를 못 해도 동작에는 문제없다
          }
        }
      }
      if (mode !== 'h') return;
      e.preventDefault();
      const { tabs, current } = optsRef.current;
      const i = tabs.indexOf(current as T);
      const atEdge = (mx > 0 && i === 0) || (mx < 0 && i === tabs.length - 1);
      dx = atEdge ? mx * 0.25 : mx;
      const dt = Math.max(1, e.timeStamp - lastT);
      vx = (e.clientX - lastX) / dt;
      lastX = e.clientX;
      lastT = e.timeStamp;
      el.style.transform = `translateX(${dx}px)`;
      el.style.opacity = String(1 - Math.min(0.35, Math.abs(dx) / el.clientWidth));
    };
    const up = (e: PointerEvent) => {
      if (!start || e.pointerId !== start.id) return;
      const wasH = mode === 'h';
      start = null;
      if (!wasH) return;
      const { tabs, current } = optsRef.current;
      const i = tabs.indexOf(current as T);
      const w = el.clientWidth || 390;
      const fling = Math.abs(vx) > 0.45;
      const far = Math.abs(dx) > w * 0.22;
      const dir: 1 | -1 = dx < 0 ? 1 : -1; // 왼쪽으로 밀면 다음(오른쪽) 탭
      const target = tabs[i + dir];
      if ((far || fling) && target && Math.sign(vx || dx) === Math.sign(dx)) {
        go(target, dir);
      } else {
        el.style.transition = `transform 420ms ${SPRING}, opacity 300ms ease-out`;
        el.style.transform = 'translateX(0)';
        el.style.opacity = '1';
        window.setTimeout(() => clear(el), 440);
      }
      // 끌다가 놓은 손가락이 버튼 클릭으로 이어지지 않게 막는다.
      const stop = (ev: Event) => {
        ev.stopPropagation();
        ev.preventDefault();
      };
      window.addEventListener('click', stop, { capture: true, once: true });
      window.setTimeout(() => window.removeEventListener('click', stop, { capture: true }), 50);
    };

    el.addEventListener('pointerdown', down);
    el.addEventListener('pointermove', move, { passive: false });
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    return () => {
      el.removeEventListener('pointerdown', down);
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      el.removeEventListener('pointercancel', up);
    };
  }, [go, node]);

  return { ref: attach, go };
}

/** 넓은 화면(PC 브라우저, 1024px 이상)인지. 폰·태블릿 세로는 지금 화면 그대로 둔다. */
export const WIDE_QUERY = '(min-width: 1024px)';
function media(q: string): boolean {
  try {
    return window.matchMedia(q).matches;
  } catch {
    return false;
  }
}
export function useMedia(q: string): boolean {
  const [on, setOn] = useState(() => media(q));
  useEffect(() => {
    let mq: MediaQueryList;
    try {
      mq = window.matchMedia(q);
    } catch {
      return;
    }
    const f = () => setOn(mq.matches);
    f();
    mq.addEventListener?.('change', f);
    return () => mq.removeEventListener?.('change', f);
  }, [q]);
  return on;
}
