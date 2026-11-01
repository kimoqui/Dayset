// 공유: 연속 기록 카드 이미지를 만들어 카카오톡·인스타그램으로 보낸다.
//
// 로컬(웹) 버전은 휴대폰의 공유 창(Web Share)을 연다. 공유 창에서 카카오톡이나
// 인스타그램을 고르면 된다. 공유 창이 없는 환경(데스크톱 등)에서는 이미지를 저장하고
// 문구를 복사한다. 앱 버전에서는 카카오 SDK·인스타그램 스토리 연동으로 바로 보낸다.

import type { DayMark } from '../app/streak';

export const FLAME_PATH = 'M12 1C13.5 5 18.5 8.5 18.5 14.5A6.5 6.5 0 0 1 5.5 14.5C5.5 11.2 7.3 9.1 8.6 7.6 8.8 9.4 9.7 10.6 11 11 10.5 7.5 11 4 12 1Z';

export interface CardData {
  name: string;
  streak: number;
  best: number;
  week: { key: string; mark: DayMark }[];
  weekSetDays: number;
  monthSetDays: number;
}

const FONT = "'Pretendard', 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif";
const C = { bg1: '#0D1220', bg2: '#1A2340', ink: '#EEF1F7', muted: '#9AA4BB', line: '#263049', amber: '#F4B04F', amberInk: '#1A1300' };
const WEEK = ['월', '화', '수', '목', '금', '토', '일'];

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function flame(ctx: CanvasRenderingContext2D, cx: number, cy: number, size: number, color: string) {
  ctx.save();
  ctx.translate(cx - size / 2, cy - size / 2);
  ctx.scale(size / 24, size / 24);
  ctx.fillStyle = color;
  ctx.fill(new Path2D(FLAME_PATH));
  ctx.restore();
}

/** 공유 카드 그리기. story = 1080×1920(인스타 스토리), square = 1080×1080(카카오톡). */
export async function renderCard(kind: 'story' | 'square', d: CardData): Promise<Blob> {
  try {
    // 캔버스는 글꼴이 실제로 불러와진 뒤에만 그 글꼴로 그린다.
    await Promise.all(['500 32px Pretendard', '700 32px Pretendard'].map((f) => document.fonts?.load(f, '가나다0123')));
    await document.fonts?.ready;
  } catch {
    // 글꼴을 기다리지 못해도 기본 글꼴로 그린다
  }
  const W = 1080;
  const H = kind === 'story' ? 1920 : 1080;
  const cv = document.createElement('canvas');
  cv.width = W;
  cv.height = H;
  const ctx = cv.getContext('2d')!;
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, C.bg1);
  g.addColorStop(1, C.bg2);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, W, H);
  // 뒤쪽 큰 링(나이트 링 모티프)
  ctx.strokeStyle = C.line;
  ctx.lineWidth = 36;
  const ringY = kind === 'story' ? 760 : 420;
  const ringR = kind === 'story' ? 330 : 250;
  ctx.beginPath();
  ctx.arc(W / 2, ringY, ringR, 0, Math.PI * 2);
  ctx.stroke();
  const frac = Math.min(1, d.weekSetDays / 7);
  if (frac > 0) {
    ctx.strokeStyle = C.amber;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.arc(W / 2, ringY, ringR, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2);
    ctx.stroke();
  }

  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  const top = kind === 'story' ? 200 : 110;
  ctx.fillStyle = C.amber;
  ctx.font = `700 ${kind === 'story' ? 56 : 46}px ${FONT}`;
  ctx.fillText('DaySet', W / 2, top);

  flame(ctx, W / 2, ringY - (kind === 'story' ? 140 : 110), kind === 'story' ? 150 : 110, C.amber);
  ctx.fillStyle = C.ink;
  ctx.font = `700 ${kind === 'story' ? 220 : 170}px ${FONT}`;
  ctx.fillText(String(d.streak), W / 2, ringY + (kind === 'story' ? 110 : 80));
  ctx.font = `700 ${kind === 'story' ? 56 : 44}px ${FONT}`;
  ctx.fillText('일 연속 셋 데이', W / 2, ringY + (kind === 'story' ? 200 : 150));

  // 이번 주 7칸
  const rowY = kind === 'story' ? 1240 : 760;
  const cell = kind === 'story' ? 104 : 88;
  const gap = kind === 'story' ? 22 : 18;
  const startX = (W - (cell * 7 + gap * 6)) / 2;
  ctx.font = `500 ${kind === 'story' ? 30 : 26}px ${FONT}`;
  d.week.forEach((day, i) => {
    const x = startX + i * (cell + gap);
    ctx.fillStyle = C.muted;
    ctx.fillText(WEEK[i], x + cell / 2, rowY - 22);
    roundRect(ctx, x, rowY, cell, cell * 1.25, 22);
    if (day.mark === 'set') {
      ctx.fillStyle = C.amber;
      ctx.fill();
      flame(ctx, x + cell / 2, rowY + cell * 0.62, cell * 0.5, C.amberInk);
    } else {
      ctx.strokeStyle = day.mark === 'future' ? '#1E2638' : day.mark === 'today' ? C.amber : C.line;
      ctx.lineWidth = 5;
      ctx.stroke();
      if (day.mark === 'rest') {
        ctx.fillStyle = C.muted;
        ctx.beginPath();
        ctx.arc(x + cell / 2, rowY + cell * 0.62, 8, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  });

  const infoY = rowY + cell * 1.25 + (kind === 'story' ? 110 : 80);
  ctx.fillStyle = C.ink;
  ctx.font = `700 ${kind === 'story' ? 44 : 38}px ${FONT}`;
  ctx.fillText(`이번 주 ${d.weekSetDays}일 · 이번 달 ${d.monthSetDays}일 · 최고 ${d.best}일`, W / 2, infoY);
  ctx.fillStyle = C.muted;
  ctx.font = `500 ${kind === 'story' ? 34 : 30}px ${FONT}`;
  ctx.fillText('셋 데이 = 기상 알람 ±30분 + 습관 70%를 지킨 날', W / 2, infoY + (kind === 'story' ? 70 : 56));
  if (kind === 'story') {
    ctx.fillStyle = C.ink;
    ctx.font = `700 40px ${FONT}`;
    ctx.fillText(`${d.name || '나'}의 생활습관`, W / 2, H - 200);
    ctx.fillStyle = C.muted;
    ctx.font = `500 32px ${FONT}`;
    ctx.fillText('자동으로 짜주는 일정으로 편하게 생활습관 잡기', W / 2, H - 140);
  }
  return new Promise((resolve, reject) => cv.toBlob((b) => (b ? resolve(b) : reject(new Error('이미지를 만들지 못했어요'))), 'image/png'));
}

export function shareMessage(d: CardData, code?: string): string {
  const lines = [
    `DaySet에서 ${d.streak}일 연속 셋 데이를 지키고 있어요.`,
    `이번 주 ${d.weekSetDays}일 · 최고 기록 ${d.best}일`,
  ];
  if (code) lines.push('', '같이 겨뤄요! DaySet 기록 탭 → 친구 → 친구 코드 넣기', code);
  return lines.join('\n');
}

export type ShareResult = 'shared' | 'saved' | 'copied' | 'cancelled' | 'failed';

function download(blob: Blob, name: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1500);
}

async function copy(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

/** 카드 이미지 + 문구 공유. 공유 창이 없으면 이미지를 저장하고 문구를 복사한다. */
export async function shareCard(kind: 'story' | 'square', d: CardData, text: string): Promise<ShareResult> {
  let blob: Blob;
  try {
    blob = await renderCard(kind, d);
  } catch {
    return 'failed';
  }
  const file = new File([blob], kind === 'story' ? 'dayset-story.png' : 'dayset-streak.png', { type: 'image/png' });
  try {
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], text, title: 'DaySet' });
      return 'shared';
    }
  } catch (e) {
    if ((e as Error).name === 'AbortError') return 'cancelled';
  }
  download(blob, file.name);
  await copy(text);
  return 'saved';
}

/** 글만 공유(친구 코드 보내기). */
export async function shareText(text: string): Promise<ShareResult> {
  try {
    if (navigator.share) {
      await navigator.share({ text, title: 'DaySet 친구 코드' });
      return 'shared';
    }
  } catch (e) {
    if ((e as Error).name === 'AbortError') return 'cancelled';
  }
  return (await copy(text)) ? 'copied' : 'failed';
}

export const RESULT_TEXT: Record<ShareResult, string> = {
  shared: '공유했어요',
  saved: '카드 이미지를 저장하고 문구를 복사했어요. 카카오톡·인스타그램에 올려 주세요',
  copied: '복사했어요. 카카오톡에 붙여 넣어 보내 주세요',
  cancelled: '공유를 취소했어요',
  failed: '공유하지 못했어요',
};
