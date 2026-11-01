import { type ReactNode, useEffect, useRef, useState } from 'react';
import { diffMin, formatClock, formatDuration, formatHm } from '../engine/models';
import { haptic } from './motion';

export interface RingSegment {
  /** 자정 기준 분(0~1440). 링에 그릴 범위(오늘로 잘린 범위). */
  start: number;
  end: number;
  color: string;
  /** 눌렀을 때 보여 줄 이름과 실제 시작·끝(자정을 넘는 수면도 그대로). */
  title: string;
  from: Date;
  to: Date;
}

interface Selection {
  minute: number;
  plan?: RingSegment;
  record?: RingSegment;
}

const R = 100;

/** 원 둘레의 한 구간. 0시가 위, 시계 방향으로 24시간. */
function Arc({ seg, r, width, opacity = 1 }: { seg: RingSegment; r: number; width: number; opacity?: number }) {
  const c = 2 * Math.PI * r;
  const len = ((seg.end - seg.start) / 1440) * c;
  if (len <= 0.2) return null;
  return (
    <circle
      cx="120"
      cy="120"
      r={r}
      fill="none"
      stroke={seg.color}
      strokeWidth={width}
      strokeDasharray={`${len.toFixed(2)} ${(c - len).toFixed(2)}`}
      strokeDashoffset={(-(seg.start / 1440) * c).toFixed(2)}
      opacity={opacity}
      style={{ transition: 'opacity 200ms ease, stroke-width 200ms ease' }}
    />
  );
}

const at = (seg: RingSegment[], m: number): RingSegment | undefined =>
  // 짧은 구간이 긴 구간 위에 그려지므로, 겹치면 짧은 것을 고른다.
  seg.filter((s) => s.start <= m && m < s.end).sort((a, b) => a.end - a.start - (b.end - b.start))[0];

const point = (minute: number, r: number) => {
  const a = (minute / 1440) * 2 * Math.PI;
  return { x: 120 + r * Math.sin(a), y: 120 - r * Math.cos(a) };
};

/**
 * 디자인 B '나이트 링': 하루 24시간을 한 바퀴로 보여 준다.
 * 바깥 굵은 링 = 자동으로 짠 일정, 안쪽 가는 링 = 실제 기록, 점 = 지금.
 * 링을 누르면 그 시각에 무엇을, 몇 시부터 몇 시까지 했는지(얼마나) 가운데에 보여 준다.
 */
export function DayRing({
  plan,
  records,
  nowMinutes,
  label,
  recordsOnly = false,
  children,
}: {
  recordsOnly?: boolean;
  plan: RingSegment[];
  records: RingSegment[];
  nowMinutes: number;
  label: string;
  children: ReactNode;
}) {
  const [sel, setSel] = useState<Selection | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  // 6초 뒤 '지금' 표시로 돌아간다.
  useEffect(() => {
    if (!sel) return;
    const t = window.setTimeout(() => setSel(null), 6000);
    return () => window.clearTimeout(t);
  }, [sel]);

  const pick = (clientX: number, clientY: number) => {
    const rect = svgRef.current?.getBoundingClientRect();
    if (!rect) return;
    const x = ((clientX - rect.left) / rect.width) * 240 - 120;
    const y = ((clientY - rect.top) / rect.height) * 240 - 120;
    const dist = Math.hypot(x, y);
    if (dist < 64 || dist > 118) {
      setSel(null); // 가운데나 바깥을 누르면 닫는다
      return;
    }
    const minute = Math.floor((((Math.atan2(x, -y) + 2 * Math.PI) % (2 * Math.PI)) / (2 * Math.PI)) * 1440);
    setSel({ minute, plan: at(plan, minute), record: at(records, minute) });
    haptic(6);
  };

  const dot = point(nowMinutes, R);
  const mark = sel ? point(sel.minute, R) : null;
  const dim = sel ? 0.3 : 1;
  const main = sel ? (sel.plan ?? sel.record) : undefined;
  const span = (s: RingSegment) => `${formatHm(s.from)}–${formatHm(s.to)} · ${formatDuration(Math.max(1, diffMin(s.to, s.from)))}`;

  return (
    <div className="wrap-ring">
      <svg
        ref={svgRef}
        width="248"
        height="248"
        viewBox="0 0 240 240"
        role="img"
        aria-label={`${label}. 링을 누르면 그 시각의 일정과 기록을 보여 줘요`}
        className="ring-svg"
        onClick={(e) => pick(e.clientX, e.clientY)}
      >
        <circle cx="120" cy="120" r={R} fill="none" stroke="var(--track)" strokeWidth="16" />
        <g transform="rotate(-90 120 120)">
          {plan.map((s, i) => (
            <Arc key={i} seg={s} r={R} width={sel?.plan === s ? 22 : 16} opacity={sel && sel.plan !== s ? dim : 1} />
          ))}
          {records.map((s, i) => (
            <Arc key={`r${i}`} seg={s} r={84} width={sel?.record === s ? 7 : 4} opacity={sel && sel.record !== s ? dim : 0.9} />
          ))}
        </g>
        <g fontSize="11" fill="var(--faint)" textAnchor="middle">
          <text x="120" y="46">0시</text>
          <text x="198" y="124">6시</text>
          <text x="120" y="202">12시</text>
          <text x="42" y="124">18시</text>
        </g>
        <circle cx={dot.x.toFixed(2)} cy={dot.y.toFixed(2)} r="9" fill="var(--accent)" stroke="var(--ring-bg)" strokeWidth="3" opacity={sel ? 0.5 : 1} />
        {mark && (
          <g className="ring-mark">
            <line x1="120" y1="120" x2={mark.x.toFixed(2)} y2={mark.y.toFixed(2)} stroke="var(--ink)" strokeWidth="1" strokeDasharray="2 3" opacity="0.35" />
            <circle cx={mark.x.toFixed(2)} cy={mark.y.toFixed(2)} r="7" fill="var(--ink)" stroke="var(--ring-bg)" strokeWidth="3" />
          </g>
        )}
      </svg>
      <div className="center">
        {sel ? (
          <div className="ring-info" key={sel.minute} aria-live="polite">
            <span className="sel-pill num">{formatClock(Math.round(sel.minute / 5) * 5)}</span>
            <span className="sel-title">
              {main && <i style={{ background: main.color }} />}
              {main ? main.title : '비어 있는 시간'}
            </span>
            {sel.plan && <span className="sel-sub num">{recordsOnly ? '기록 ' : ''}{span(sel.plan)}</span>}
            {sel.record ? (
              <span className="sel-rec num">
                실제 {sel.record.title} {span(sel.record)}
              </span>
            ) : (
              !recordsOnly && sel.plan && sel.minute < nowMinutes && <span className="sel-rec">실제 기록 없음</span>
            )}
          </div>
        ) : (
          children
        )}
      </div>
    </div>
  );
}
