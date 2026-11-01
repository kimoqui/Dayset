import { type ReactNode, useEffect } from 'react';
import type { Activity, ScheduleBlock } from '../engine/models';
import { haptic } from './motion';

// 디자인 시안과 같은 선 아이콘(24px, 선 굵기 1.8).
const PATHS = {
  sleep: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z',
  meal: 'M3 11h18a9 9 0 0 1-18 0zM12 3v4M8 5v2M16 5v2',
  work: 'M5 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18',
  exercise: 'M6 7v10M18 7v10M3 10v4M21 10v4M6 12h12',
  rest: 'M4 9h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM17 11h1.5a2.5 2.5 0 0 1 0 5H17M8 3v3M12 3v3',
  home: 'M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z',
  calendar: 'M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM4 10h16M8 3v4M16 3v4',
  tasks: 'M10 6h10M10 12h10M10 18h10M4 6l1.5 1.5L8 5M4 12l1.5 1.5L8 11M4 18l1.5 1.5L8 17',
  stats: 'M5 20V11M11 20V5M17 20v-7M3 20h18',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z',
  sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  back: 'M15 5l-7 7 7 7',
  forward: 'M5 12h13M13 6l6 6-6 6',
  plus: 'M12 5v14M5 12h14',
  close: 'M6 6l12 12M18 6L6 18',
  check: 'M5 12l5 5 9-10',
  bell: 'M6 10a6 6 0 1 1 12 0c0 5 2 6 2 6H4s2-1 2-6zM10 20a2 2 0 0 0 4 0',
  moon: 'M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z',
  chat: 'M4 5h16v11H8l-4 4z',
  link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
  trash: 'M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13',
  share: 'M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M12 3v12M7 8l5-5 5 5',
  users: 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21v-1a6 6 0 0 1 6-6h2a6 6 0 0 1 6 6v1M16 3.5a4 4 0 0 1 0 7M22 21v-1a6 6 0 0 0-4-5.6',
  refresh: 'M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7',
} as const;

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 22, stroke = 1.8 }: { name: IconName; size?: number; stroke?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={PATHS[name]} />
    </svg>
  );
}

export const activityColor = (a?: Activity): string => (a ? `var(--${a})` : 'var(--calendar)');

export function blockColor(b: ScheduleBlock): string {
  if (b.kind === 'task') return 'var(--task)';
  if (b.kind === 'fixed') return 'var(--calendar)';
  return activityColor(b.activity);
}

export function kindLabel(b: ScheduleBlock): string {
  switch (b.kind) {
    case 'task':
      return '할 일';
    case 'fixed':
      return '캘린더';
    case 'buffer':
      return '여유';
    default:
      return b.adjusted ? '조정됨' : '습관';
  }
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
  label: string;
}) {
  return (
    <div
      className="seg"
      role="radiogroup"
      aria-label={label}
      style={{ ['--n' as string]: options.length, ['--i' as string]: Math.max(0, options.findIndex((o) => o.value === value)) }}
    >
      <span className="seg-ind" aria-hidden="true" />
      {options.map((o) => (
        <button key={o.value} type="button" role="radio" aria-checked={o.value === value} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className="sheet-back" onClick={onClose}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="grab" />
        <div className="row between">
          <h2 className="t-sub">{title}</h2>
          <button type="button" className="icon-btn" aria-label="닫기" onClick={onClose}>
            <Icon name="close" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function TopBar({ title, sub, onBack, right }: { title: string; sub?: string; onBack?: () => void; right?: ReactNode }) {
  return (
    <div className="topbar">
      <div className="row" style={{ gap: 4, minWidth: 0 }}>
        {onBack && (
          <button type="button" className="icon-btn" aria-label="뒤로" onClick={onBack} style={{ marginLeft: -12 }}>
            <Icon name="back" />
          </button>
        )}
        <div className="col" style={{ gap: 0, minWidth: 0 }}>
          <h1 className="t-title ellipsis">{title}</h1>
          {sub && <span className="t-label">{sub}</span>}
        </div>
      </div>
      {right}
    </div>
  );
}

/** 'HH:MM' ↔ 자정 기준 분 */
export const toHmValue = (minutes: number): string => {
  const m = ((minutes % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
};
export const fromHmValue = (v: string): number => {
  const [h, m] = v.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
};

export function TimeField({ label, value, onChange }: { label: string; value: number; onChange: (m: number) => void }) {
  return (
    <label className="field">
      <span>{label}</span>
      <input className="input num" type="time" value={toHmValue(value)} onChange={(e) => e.target.value && onChange(fromHmValue(e.target.value))} />
    </label>
  );
}

export function NumberField({
  label,
  value,
  onChange,
  min = 0,
  max = 600,
  step = 5,
  unit = '분',
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
}) {
  return (
    <label className="field">
      <span>
        {label} ({unit})
      </span>
      <input
        className="input num"
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        step={step}
        value={Number.isFinite(value) ? value : ''}
        onChange={(e) => {
          const n = Number(e.target.value);
          if (Number.isFinite(n)) onChange(Math.max(min, Math.min(max, n)));
        }}
      />
    </label>
  );
}

/** 크고 눈에 띄는 토글 스위치. 켜지면 앰버로 채워진다. */
export function Switch({
  checked,
  onChange,
  label,
  sub,
  onText = '켜짐',
  offText = '꺼짐',
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: ReactNode;
  sub?: ReactNode;
  onText?: string;
  offText?: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      className={`switch-row ${checked ? 'on' : ''}`}
      onClick={() => {
        haptic(8);
        onChange(!checked);
      }}
    >
      <span className="switch-text">
        <span className="switch-label">{label}</span>
        {sub && <span className="t-label">{sub}</span>}
      </span>
      <span className="switch-state" key={String(checked)}>
        {checked ? onText : offText}
      </span>
      <span className="switch" aria-hidden="true">
        <span className="knob" />
      </span>
    </button>
  );
}

/** 연속 기록 불꽃(채운 모양). */
export function Flame({ size = 20, color = 'var(--accent)' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 1C13.5 5 18.5 8.5 18.5 14.5A6.5 6.5 0 0 1 5.5 14.5C5.5 11.2 7.3 9.1 8.6 7.6 8.8 9.4 9.7 10.6 11 11 10.5 7.5 11 4 12 1Z" fill={color} />
    </svg>
  );
}

export const pct = (v: number | null | undefined): string => (v == null ? '–' : `${Math.round(v * 100)}%`);
