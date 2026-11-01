// .ics(iCalendar) 읽기. 구글·애플·아웃룩 캘린더에서 내보낸 파일을 그대로 읽는다.
//
// 읽는 것: 시각이 있는 일정(SUMMARY, DTSTART/DTEND 또는 DURATION, TZID·UTC·현지 시각),
//          반복 일정(RRULE: DAILY·WEEKLY·MONTHLY·YEARLY, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY),
//          빠진 날(EXDATE), 한 번만 바뀐 날(RECURRENCE-ID), 취소(STATUS:CANCELLED).
// 빼는 것: 하루 종일 일정(시각이 없어 일정 배치에 쓰지 않는다), '한가함'(TRANSP:TRANSPARENT), 12시간 넘는 일정.

export interface ImportedEvent {
  uid: string;
  title: string;
  start: Date;
  end: Date;
}

export interface IcsResult {
  calName: string | null;
  events: ImportedEvent[];
  skipped: { allDay: number; long: number; free: number };
}

interface Prop {
  params: Record<string, string>;
  value: string;
}
type Comp = Map<string, Prop[]>;

const WINDOWS_TZ: Record<string, string> = {
  'Korea Standard Time': 'Asia/Seoul',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'China Standard Time': 'Asia/Shanghai',
  'UTC': 'UTC',
  'GMT Standard Time': 'Europe/London',
  'Pacific Standard Time': 'America/Los_Angeles',
  'Eastern Standard Time': 'America/New_York',
};

function unescapeText(v: string): string {
  return v.replace(/\\n/gi, ' ').replace(/\\([,;\\])/g, '$1').trim();
}

function parseComponents(text: string): { cal: Comp; events: Comp[] } {
  const lines = text.replace(/\r\n?/g, '\n').replace(/\n[ \t]/g, '').split('\n');
  const cal: Comp = new Map();
  const events: Comp[] = [];
  let cur: Comp | null = null;
  let depth = 0; // VEVENT 안의 VALARM 같은 하위 블록은 건너뛴다.
  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line) continue;
    if (/^BEGIN:VEVENT$/i.test(line)) {
      cur = new Map();
      depth = 0;
      continue;
    }
    if (/^END:VEVENT$/i.test(line)) {
      if (cur) events.push(cur);
      cur = null;
      continue;
    }
    if (cur && /^BEGIN:/i.test(line)) {
      depth++;
      continue;
    }
    if (cur && /^END:/i.test(line)) {
      depth = Math.max(0, depth - 1);
      continue;
    }
    if (cur && depth > 0) continue;
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const head = line.slice(0, colon).split(';');
    const name = head[0].toUpperCase();
    const params: Record<string, string> = {};
    for (const p of head.slice(1)) {
      const eq = p.indexOf('=');
      if (eq > 0) params[p.slice(0, eq).toUpperCase()] = p.slice(eq + 1).replace(/^"|"$/g, '');
    }
    const target = cur ?? cal;
    const list = target.get(name) ?? [];
    list.push({ params, value: line.slice(colon + 1) });
    target.set(name, list);
  }
  return { cal, events };
}

const first = (c: Comp, name: string): Prop | undefined => c.get(name)?.[0];

/** 그 시간대에서 utcMs 순간의 벽시계 시각 − utcMs (분 단위 차이를 ms로). */
function tzOffsetMs(utcMs: number, tz: string): number {
  const f = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const p = Object.fromEntries(f.formatToParts(new Date(utcMs)).map((x) => [x.type, x.value]));
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second);
  return asUtc - utcMs;
}

function zoned(y: number, mo: number, d: number, h: number, mi: number, s: number, tz: string): Date {
  const guess = Date.UTC(y, mo, d, h, mi, s);
  let t = guess - tzOffsetMs(guess, tz);
  t = guess - tzOffsetMs(t, tz); // 서머타임 경계 보정
  return new Date(t);
}

function validTz(tz: string | undefined): string | null {
  if (!tz) return null;
  const name = WINDOWS_TZ[tz] ?? tz.replace(/^\/[^/]+\/[^/]+\//, ''); // '/mozilla.org/.../Asia/Seoul' 형태
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name });
    return name;
  } catch {
    return null;
  }
}

type When = { allDay: true; date: Date } | { allDay: false; date: Date };

function parseWhen(value: string, params: Record<string, string>): When | null {
  const v = value.trim();
  const dOnly = /^(\d{4})(\d{2})(\d{2})$/.exec(v);
  if (dOnly || params.VALUE === 'DATE') {
    const m = dOnly ?? /^(\d{4})(\d{2})(\d{2})/.exec(v);
    if (!m) return null;
    return { allDay: true, date: new Date(+m[1], +m[2] - 1, +m[3]) };
  }
  const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$/.exec(v);
  if (!m) return null;
  const [y, mo, d, h, mi, s] = [+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] ?? 0)];
  if (m[7]) return { allDay: false, date: new Date(Date.UTC(y, mo, d, h, mi, s)) };
  const tz = validTz(params.TZID);
  return { allDay: false, date: tz ? zoned(y, mo, d, h, mi, s, tz) : new Date(y, mo, d, h, mi, s) };
}

function parseDuration(v: string): number | null {
  const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(v.trim());
  if (!m) return null;
  const min = (+(m[2] ?? 0) * 7 + +(m[3] ?? 0)) * 1440 + +(m[4] ?? 0) * 60 + +(m[5] ?? 0) + Math.round(+(m[6] ?? 0) / 60);
  return m[1] === '-' ? -min : min;
}

interface Rule {
  freq: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
  interval: number;
  count: number | null;
  until: Date | null;
  byDay: number[] | null; // 0 = 일요일
  byMonthDay: number[] | null;
}

const DAY_CODE: Record<string, number> = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };

function parseRule(v: string): Rule | null {
  const kv = Object.fromEntries(
    v.split(';').map((p) => {
      const [k, x] = p.split('=');
      return [k.toUpperCase(), x ?? ''];
    }),
  );
  const freq = kv.FREQ as Rule['freq'];
  if (!['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].includes(freq)) return null;
  let until: Date | null = null;
  if (kv.UNTIL) {
    const w = parseWhen(kv.UNTIL, {});
    // 날짜만 있으면 그날 끝까지 포함한다.
    until = w ? (w.allDay ? new Date(w.date.getTime() + 86400000 - 1) : w.date) : null;
  }
  const byDay = kv.BYDAY
    ? kv.BYDAY.split(',')
        .map((d: string) => DAY_CODE[d.slice(-2).toUpperCase()])
        .filter((d: number | undefined): d is number => d != null)
    : null;
  const byMonthDay = kv.BYMONTHDAY ? kv.BYMONTHDAY.split(',').map(Number).filter((n: number) => n > 0) : null;
  return {
    freq,
    interval: Math.max(1, +(kv.INTERVAL ?? 1) || 1),
    count: kv.COUNT ? +kv.COUNT : null,
    until,
    byDay: byDay && byDay.length ? byDay : null,
    byMonthDay: byMonthDay && byMonthDay.length ? byMonthDay : null,
  };
}

const sameClock = (day: Date, t: Date) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), t.getHours(), t.getMinutes(), t.getSeconds());

/** 반복 규칙으로 시작 시각들을 만든다(start 포함, 오름차순). to를 넘으면 멈춘다. */
function expand(start: Date, rule: Rule, to: Date): Date[] {
  const out: Date[] = [];
  const limit = rule.until && rule.until < to ? rule.until : to;
  const push = (d: Date): boolean => {
    if (d < start) return true;
    if (d > limit) return false;
    if (rule.count != null && out.length >= rule.count) return false;
    out.push(d);
    return true;
  };
  const MAX = 3000;
  if (rule.freq === 'DAILY') {
    for (let i = 0; i < MAX; i++) {
      const d = sameClock(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i * rule.interval), start);
      if (rule.byDay && !rule.byDay.includes(d.getDay())) continue;
      if (!push(d)) break;
    }
  } else if (rule.freq === 'WEEKLY') {
    const days = rule.byDay ?? [start.getDay()];
    const order = [...days].sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7)); // 월요일부터
    const monday = new Date(start.getFullYear(), start.getMonth(), start.getDate() - ((start.getDay() + 6) % 7));
    outer: for (let w = 0; w < MAX; w++) {
      for (const wd of order) {
        const d = sameClock(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + w * 7 * rule.interval + ((wd + 6) % 7)), start);
        if (!push(d)) break outer;
      }
    }
  } else if (rule.freq === 'MONTHLY') {
    const mdays = rule.byMonthDay ?? [start.getDate()];
    outer: for (let i = 0; i < MAX; i++) {
      for (const md of [...mdays].sort((a, b) => a - b)) {
        const d = sameClock(new Date(start.getFullYear(), start.getMonth() + i * rule.interval, md), start);
        if (d.getDate() !== md) continue; // 31일이 없는 달은 건너뛴다
        if (!push(d)) break outer;
      }
    }
  } else {
    for (let i = 0; i < MAX; i++) {
      const d = sameClock(new Date(start.getFullYear() + i * rule.interval, start.getMonth(), start.getDate()), start);
      if (d.getDate() !== start.getDate()) continue;
      if (!push(d)) break;
    }
  }
  return out;
}

/** .ics 글을 읽어 from~to 사이에 걸치는 일정만 돌려준다. */
export function parseIcs(text: string, from: Date, to: Date): IcsResult {
  const { cal, events } = parseComponents(text);
  const calName = first(cal, 'X-WR-CALNAME')?.value ? unescapeText(first(cal, 'X-WR-CALNAME')!.value) : null;
  const skipped = { allDay: 0, long: 0, free: 0 };
  const out: ImportedEvent[] = [];
  const seen = new Set<string>();

  // 한 번만 바뀐 날: uid → 원래 시작 시각(ms)들
  const overridden = new Map<string, Set<number>>();
  for (const e of events) {
    const rid = first(e, 'RECURRENCE-ID');
    const uid = first(e, 'UID')?.value;
    if (!rid || !uid) continue;
    const w = parseWhen(rid.value, rid.params);
    if (!w) continue;
    const set = overridden.get(uid) ?? new Set<number>();
    set.add(w.date.getTime());
    overridden.set(uid, set);
  }

  events.forEach((e, idx) => {
    const ds = first(e, 'DTSTART');
    if (!ds) return;
    const start = parseWhen(ds.value, ds.params);
    if (!start) return;
    if (start.allDay) {
      skipped.allDay++;
      return;
    }
    if ((first(e, 'STATUS')?.value ?? '').toUpperCase() === 'CANCELLED') return;
    if ((first(e, 'TRANSP')?.value ?? '').toUpperCase() === 'TRANSPARENT') {
      skipped.free++;
      return;
    }
    const de = first(e, 'DTEND');
    const endW = de ? parseWhen(de.value, de.params) : null;
    const durProp = first(e, 'DURATION');
    let minutes = endW ? Math.round((endW.date.getTime() - start.date.getTime()) / 60000) : durProp ? parseDuration(durProp.value) ?? 30 : 30;
    if (minutes <= 0) minutes = 30;
    if (minutes > 12 * 60) {
      skipped.long++;
      return;
    }
    const uid = first(e, 'UID')?.value ?? `noid-${idx}`;
    const title = unescapeText(first(e, 'SUMMARY')?.value ?? '') || '일정';
    const isOverride = !!first(e, 'RECURRENCE-ID');
    const rr = !isOverride && first(e, 'RRULE') ? parseRule(first(e, 'RRULE')!.value) : null;

    const ex = new Set<number>();
    for (const p of e.get('EXDATE') ?? []) {
      for (const v of p.value.split(',')) {
        const w = parseWhen(v, p.params);
        if (w) ex.add(w.date.getTime());
      }
    }
    const skipStarts = overridden.get(uid);
    const starts = rr ? expand(start.date, rr, to) : [start.date];
    for (const s of starts) {
      if (ex.has(s.getTime())) continue;
      if (rr && skipStarts?.has(s.getTime())) continue;
      const end = new Date(s.getTime() + minutes * 60000);
      if (end <= from || s >= to) continue;
      const key = `${uid}@${s.getTime()}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ uid, title, start: s, end });
    }
  });
  out.sort((a, b) => a.start.getTime() - b.start.getTime());
  return { calName, events: out, skipped };
}
