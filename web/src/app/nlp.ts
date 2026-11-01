// 한 줄 일정 입력 해석: "내일 오전 9시 팀 회의 1시간" → 날짜·시작·끝·제목.
// 서버·AI 없이 규칙으로 읽는다. 앱 버전의 대화형 비서(AI)가 나오기 전까지 쓰는 빠른 입력이다.

import { addDays, addMin, dayStart } from '../engine/models';

export interface ParsedEvent {
  title: string;
  start: Date;
  end: Date;
  /** 무엇을 알아들었는지(화면에 칩으로 보여 준다). */
  found: { date?: string; time?: string; length?: string };
}

const DAY_WORDS: Record<string, number> = { 오늘: 0, 내일: 1, 모레: 2, 글피: 3 };
const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

export function parseEventText(input: string, now: Date): ParsedEvent | null {
  let text = ` ${input.trim()} `;
  if (!text.trim()) return null;
  const found: ParsedEvent['found'] = {};
  const cut = (m: RegExpMatchArray) => {
    text = text.replace(m[0], ' ');
  };

  // 1) 날짜
  let day = dayStart(now);
  let m = text.match(/(오늘|내일|모레|글피)/);
  if (m) {
    day = addDays(day, DAY_WORDS[m[1]]);
    found.date = m[1];
    cut(m);
  } else if ((m = text.match(/(이번\s*주|다음\s*주)?\s*([월화수목금토일])요일/))) {
    const target = WEEKDAYS.indexOf(m[2]);
    const mon = addDays(day, -((day.getDay() + 6) % 7));
    const idx = (target + 6) % 7; // 월=0
    let d = addDays(mon, idx + (m[1]?.startsWith('다음') ? 7 : 0));
    if (!m[1] && d < day) d = addDays(d, 7);
    day = d;
    found.date = `${m[1] ? m[1].replace(/\s/g, ' ') + ' ' : ''}${m[2]}요일`;
    cut(m);
  } else if ((m = text.match(/(\d{1,2})\s*월\s*(\d{1,2})\s*일/)) || (m = text.match(/\b(\d{1,2})\/(\d{1,2})\b/))) {
    day = new Date(now.getFullYear(), Number(m[1]) - 1, Number(m[2]));
    if (day < dayStart(now)) day = new Date(now.getFullYear() + 1, Number(m[1]) - 1, Number(m[2]));
    found.date = `${Number(m[1])}월 ${Number(m[2])}일`;
    cut(m);
  }

  // 2) 시작 시각
  let startMin: number | null = null;
  const ampm = (word: string | undefined, h: number): number => {
    if (word && /오후|저녁|밤/.test(word) && h < 12) return h + 12;
    if (word && /오전|아침|새벽/.test(word) && h === 12) return 0;
    if (word && /낮/.test(word) && h < 7) return h + 12;
    // 시간대 말이 없으면 1~7시는 오후로 본다("3시 회의" = 15시).
    if (!word && h >= 1 && h <= 7) return h + 12;
    return h;
  };
  if ((m = text.match(/(오전|오후|아침|저녁|밤|낮|새벽)?\s*(\d{1,2}):(\d{2})/))) {
    startMin = ampm(m[1], Number(m[2])) * 60 + Number(m[3]);
    cut(m);
  } else if ((m = text.match(/(오전|오후|아침|저녁|밤|낮|새벽)?\s*(\d{1,2})\s*시\s*(반|(\d{1,2})\s*분)?(?!\s*간)/))) {
    const min = m[3] === '반' ? 30 : m[4] ? Number(m[4]) : 0;
    startMin = ampm(m[1], Number(m[2])) * 60 + min;
    cut(m);
  }
  if (startMin != null) {
    found.time = `${String(Math.floor(startMin / 60) % 24).padStart(2, '0')}:${String(startMin % 60).padStart(2, '0')}`;
  }

  // 3) 끝 시각("~11시", "11시까지") 또는 길이("1시간 반", "90분")
  let length = 60;
  let endMin: number | null = null;
  if ((m = text.match(/(?:~|-|부터)?\s*(오전|오후|저녁|밤)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(반)?)\s*까지/)) || (m = text.match(/~\s*(오전|오후|저녁|밤)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(반)?)?/))) {
    let h = Number(m[2]);
    if (m[1]) h = ampm(m[1], h);
    else if (startMin != null && h * 60 <= startMin) h += 12;
    endMin = h * 60 + (m[3] ? Number(m[3]) : m[4] ? 30 : 0);
    cut(m);
  } else if ((m = text.match(/(\d{1,2})\s*시간\s*(반)?/))) {
    length = Number(m[1]) * 60 + (m[2] ? 30 : 0);
    found.length = `${m[1]}시간${m[2] ? ' 반' : ''}`;
    cut(m);
  } else if ((m = text.match(/(\d{2,3})\s*분/))) {
    length = Number(m[1]);
    found.length = `${length}분`;
    cut(m);
  }
  if (startMin == null) return null;
  if (endMin != null && endMin > startMin) {
    length = endMin - startMin;
    found.length = `${found.time}~${String(Math.floor(endMin / 60) % 24).padStart(2, '0')}:${String(endMin % 60).padStart(2, '0')}`;
  }

  // 4) 제목: 남은 말에서 조사·잡음을 걷어 낸다.
  const title =
    text
      .replace(/\s(에|부터|까지|에서|동안|쯤|정도)(?=\s)/g, ' ')
      .replace(/(\S)(에|부터|까지)\s/g, '$1 ')
      .replace(/[~,.]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim() || '일정';

  const start = addMin(day, startMin);
  return { title, start, end: addMin(start, Math.max(10, length)), found };
}

/** 입력 예시(칩으로 보여 준다). */
export const EXAMPLES = ['내일 오전 9시 팀 회의', '모레 3시 치과 30분', '금요일 저녁 7시 친구 약속 2시간', '내일 10:30~12:00 수업'];
