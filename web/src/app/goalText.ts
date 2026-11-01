// 처음 목표 정하기의 '기타': 자유롭게 적은 글에서 목표를 읽는다.
// 서버·AI 없이 기기 안에서 규칙으로 읽는다(한 줄 일정 입력 nlp.ts와 같은 방식).
// 읽는 것: 기상 시각, 수면 시간(또는 잠드는 시각), 아침 식사, 운동 종류·시간·시각, 할 일·공부.
// 읽지 못한 부분은 숨기지 않고 그대로 돌려준다(화면에 '아직 자동으로 넣지 못해요'로 보여 준다).

import type { GoalFocus } from './state';

export interface GoalReading {
  focus: GoalFocus[];
  /** 목표 기상 시각(자정 기준 분). */
  wake?: number;
  /** 목표 수면 시간(분). */
  sleepMinutes?: number;
  /** 잠드는 시각(자정 기준 분, 다음 날 새벽이면 24시 넘게). 수면 시간을 계산할 때 쓴다. */
  bedtime?: number;
  exerciseMinutes?: number;
  /** 운동 이름(예: 달리기). */
  exerciseTitle?: string;
  /** 운동 시각(자정 기준 분). */
  exerciseStart?: number;
  /** 알아들은 것(화면 칩). */
  found: { focus: GoalFocus; text: string }[];
  /** 읽지 못한 부분. */
  unknown: string[];
}

const NATIVE: [string, number][] = [
  ['열두', 12], ['열한', 11], ['열', 10], ['아홉', 9], ['여덟', 8], ['일곱', 7],
  ['여섯', 6], ['다섯', 5], ['네', 4], ['세', 3], ['두', 2], ['한', 1],
];

/** '여섯 시', '일곱 시간' → '6시', '7시간' */
export function nativeNumbers(text: string): string {
  let t = text;
  for (const [w, n] of NATIVE) t = t.replace(new RegExp(`${w}\\s*(시간|시)`, 'g'), `${n}$1`);
  return t;
}

const SPLIT = /[,，.。!?！？\n·;/]|그리고|또한|(?<=[가-힣])(?:하고|고|며|면서|서|랑|이랑)\s+/;
const FILLER = /(하고\s*싶어요?|하고\s*싶다|싶어요?|싶다|싶음|싶고|하기|해요|할래요?|매일|매일매일|꾸준히|좀|더|많이|습관|만들기|만들고|정도|쯤|이상|목표|잘|제대로|최대한|있게|되게|되기|수\s*있게|요(?=\s|$)|\s)+/g;

export const EXERCISES: [RegExp, string][] = [
  [/러닝|달리기|조깅|뛰기|달리/, '달리기'],
  [/헬스|웨이트|근력|근육/, '헬스'],
  [/필라테스/, '필라테스'],
  [/요가/, '요가'],
  [/수영/, '수영'],
  [/스트레칭/, '스트레칭'],
  [/홈트/, '홈트'],
  [/산책|걷기|만보|걷/, '걷기'],
  [/자전거|라이딩/, '자전거'],
  [/등산/, '등산'],
  [/줄넘기/, '줄넘기'],
  [/클라이밍/, '클라이밍'],
  [/운동|체력|다이어트|살\s*빼/, '운동'],
];

const TASK_WORDS = /공부|과제|숙제|업무|미루|할\s*일|집중|시험|토익|토플|자격증|프로젝트|작업|코딩|레포트|리포트|마감/;
const WAKE_WORDS = /일어나|일어남|기상|늦잠|아침형|미라클\s*모닝|깨기|깨고|눈\s*뜨/;
const SLEEP_WORDS = /잠|수면|자기|자고|자는|잘\s*자|취침|잠들|밤샘|밤새|일찍\s*자|늦게\s*자|숙면|\d\s*시간\s*(이상\s*)?자|[\s에]자$/;
const BREAKFAST = /아침[^\d,]{0,5}?(밥|식사|먹|챙기|챙겨|거르)|조식|아침밥/;

const AM = /오전|아침|새벽/;
const PM = /오후|저녁|밤/;

/** 시각 하나 읽기: '6시 반', '6:30', '오전 6시 20분'. 낮·밤 말이 없으면 null(해석은 쓰는 곳에서). */
function readClock(clause: string): { h: number; m: number; am: boolean; pm: boolean } | null {
  const m = clause.match(/(오전|오후|아침|저녁|밤|새벽)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(?:(반)|(\d{1,2})\s*분)?)(?!\s*간)/);
  if (!m) return null;
  const h = Number(m[2]);
  if (h > 24) return null;
  const min = m[3] ? Number(m[3]) : m[4] ? 30 : m[5] ? Number(m[5]) : 0;
  if (min > 59) return null;
  return { h, m: min, am: !!m[1] && AM.test(m[1]), pm: !!m[1] && PM.test(m[1]) };
}

/** 'N시간(반)' → 분 */
function readHours(clause: string): number | null {
  const m = clause.match(/(\d{1,2}(?:\.\d)?)\s*시간\s*(반)?/);
  return m ? Math.round(Number(m[1]) * 60 + (m[2] ? 30 : 0)) : null;
}

/** 'N분' 또는 'N시간' → 분(운동 길이) */
function readLength(clause: string): number | null {
  const min = clause.match(/(\d{1,3})\s*분/);
  if (min) return Number(min[1]);
  return readHours(clause);
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const round5 = (v: number) => Math.round(v / 5) * 5;
const hm = (v: number) => {
  const m = ((v % 1440) + 1440) % 1440;
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`;
};
const hoursText = (min: number) => (min % 60 ? `${Math.floor(min / 60)}시간 ${min % 60}분` : `${min / 60}시간`);

export function readGoalText(input: string): GoalReading {
  const r: GoalReading = { focus: [], found: [], unknown: [] };
  const text = nativeNumbers(input.trim()).slice(0, 300);
  if (!text) return r;
  const add = (f: GoalFocus) => {
    if (!r.focus.includes(f)) r.focus.push(f);
  };

  for (const raw of text.split(SPLIT)) {
    const clause = (raw ?? '').trim();
    if (!clause) continue;
    let hit = false;

    // 아침 식사(기상 시각 '아침 6시'와 헷갈리지 않게 먼저 본다)
    if (BREAKFAST.test(clause)) {
      add('breakfast');
      hit = true;
    }

    // 운동
    const ex = EXERCISES.find(([re]) => re.test(clause));
    if (ex) {
      add('exercise');
      hit = true;
      if (ex[1] !== '운동' || !r.exerciseTitle) r.exerciseTitle = ex[1];
      const len = readLength(clause);
      if (len) r.exerciseMinutes = clamp(round5(len), 10, 120);
      const c = readClock(clause.replace(/\d{1,3}\s*분/g, ''));
      if (c) {
        // 운동 시각: 낮·밤 말이 없으면 1~11시는 오후로 본다(저녁 운동이 흔하다). '아침·새벽'이면 오전.
        const h = c.am ? c.h % 12 : c.pm || (c.h >= 1 && c.h <= 11) ? (c.h % 12) + 12 : c.h;
        r.exerciseStart = (h % 24) * 60 + c.m;
      }
    }

    // 기상
    if (WAKE_WORDS.test(clause)) {
      add('wake');
      hit = true;
      const c = readClock(clause);
      if (c) {
        // 기상은 낮·밤 말이 없으면 오전으로 본다.
        const h = c.pm && c.h < 12 ? c.h + 12 : c.h === 12 && !c.pm ? 12 : c.h;
        r.wake = clamp(h * 60 + c.m, 4 * 60, 12 * 60);
      }
    }

    // 수면
    if (SLEEP_WORDS.test(clause.replace(/늦잠/g, ''))) {
      add('sleep');
      hit = true;
      const hrs = readHours(clause);
      if (hrs && hrs >= 180 && hrs <= 12 * 60) r.sleepMinutes = clamp(Math.round(hrs / 30) * 30, 300, 600);
      else {
        const c = readClock(clause);
        if (c) {
          // 잠드는 시각: 7~11시는 밤, 12시는 자정, 1~4시는 새벽(다음 날).
          let h = c.h;
          if (c.am || (!c.pm && h >= 0 && h <= 4)) h = h % 12 + 24;
          else if (h === 12) h = 24;
          else if (h < 12) h += 12;
          r.bedtime = h * 60 + c.m;
        }
      }
    }

    // 할 일·공부
    if (TASK_WORDS.test(clause)) {
      add('tasks');
      hit = true;
    }

    if (!hit) {
      const rest = clause.replace(FILLER, '');
      if (/[가-힣a-zA-Z]{2,}/.test(rest)) r.unknown.push(clause.replace(/\s*(하고\s*)?싶(어요?|다|음|고)\s*$/, '').trim());
    }
  }

  // 잠드는 시각만 적었으면 기상 목표(없으면 7시)와의 차이로 수면 시간을 정한다.
  if (r.sleepMinutes == null && r.bedtime != null) {
    const wake = (r.wake ?? 7 * 60) + 24 * 60;
    const span = wake - r.bedtime;
    if (span >= 300 && span <= 600) r.sleepMinutes = Math.round(span / 30) * 30;
  }

  const order: GoalFocus[] = ['wake', 'sleep', 'breakfast', 'exercise', 'tasks'];
  r.focus.sort((a, b) => order.indexOf(a) - order.indexOf(b));
  for (const f of r.focus) {
    const text =
      f === 'wake'
        ? `일찍 일어나기${r.wake != null ? ` · ${hm(r.wake)} 기상` : ''}`
        : f === 'sleep'
          ? `충분히 자기${r.sleepMinutes != null ? ` · ${hoursText(r.sleepMinutes)}` : ''}${r.bedtime != null ? ` · ${hm(r.bedtime)} 취침` : ''}`
          : f === 'breakfast'
            ? '아침 챙겨 먹기'
            : f === 'exercise'
              ? `운동 습관 · ${r.exerciseTitle ?? '운동'}${r.exerciseMinutes ? ` ${r.exerciseMinutes}분` : ''}${r.exerciseStart != null ? ` · ${hm(r.exerciseStart)}` : ''}`
              : '할 일 미루지 않기';
    r.found.push({ focus: f, text });
  }
  return r;
}

/** 입력 예시(칩으로 보여 준다). */
export const GOAL_EXAMPLES = ['6시 반에 일어나고 저녁 8시에 30분 달리기', '11시 전에 자고 7시간 반 자기', '아침 꼭 챙겨 먹고 토익 공부 미루지 않기'];
