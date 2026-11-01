// 1순위 '자동': 순서 바로 반영, 걸리는 시간 자동 보정, 캘린더 가져오기.

import { calibrationFor, calibrationText, emptyDurations, normTitle, plannedMinutes } from '../duration';
import { parseIcs } from '../ics';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';
import type { TaskItem } from '../../engine/models';

const at = (day: number, h: number, m = 0) => new Date(2026, 9, day, h, m);
const goTo = (d: Date) => store.setFixedClock(d);

const task = (id: string, title: string, est: number, type: TaskItem['type'] = 'work'): TaskItem => ({
  id, title, estMinutes: est, dueAt: at(30, 18), type, priority: 'normal', focus: type === 'work', doneMinutes: 0, createdAt: at(19, 6),
});

beforeEach(() => {
  store.resetAll();
  goTo(at(19, 6, 0));
  store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: { travelMinutes: 0 }, usualWake: 7 * 60 });
});

const firstTaskBlock = () => store.getState().plans['2026-10-19'].blocks.find((b) => b.kind === 'task');

describe('순서 바로 반영', () => {
  test('할 일을 넣거나 순서를 바꾸면 오늘 일정을 바로 다시 짜고, 되돌릴 수 있다', () => {
    goTo(at(19, 6, 30));
    const r1 = store.saveTask(task('a', '보고서', 60));
    expect(r1.replanned).toBe(true);
    store.saveTask(task('b', '메일 정리', 30));
    expect(firstTaskBlock()?.taskId).toBe('a');
    const plan = store.getState().plans['2026-10-19'];
    expect(plan.inputsVersion).toBe(store.getState().inputsVersion); // '다시 짜기' 안내가 뜨지 않는다

    const r = store.reorderTasks(['b', 'a']);
    expect(r.replanned).toBe(true);
    expect(firstTaskBlock()?.taskId).toBe('b');

    expect(store.canUndoPlan()).toBe(true);
    expect(store.undoPlanChange()).toBe(true);
    expect(store.getState().tasks.map((t) => t.id)).toEqual(['a', 'b']);
    expect(firstTaskBlock()?.taskId).toBe('a');
  });

  test('이미 지난 조각은 그대로 두고 남은 시간만 바꾼다', () => {
    goTo(at(19, 9, 0));
    store.saveTask(task('a', '보고서', 60));
    store.saveTask(task('b', '메일 정리', 30));
    const before = store.getState().plans['2026-10-19'].blocks.filter((b) => b.kind === 'task');
    const firstEnd = before[0].end;
    goTo(new Date(firstEnd.getTime() + 60000));
    store.reorderTasks(['b', 'a']);
    const after = store.getState().plans['2026-10-19'].blocks.filter((b) => b.kind === 'task');
    expect(after[0].id).toBe(before[0].id); // 지난 조각 유지
  });

  test('지금 하고 있는 조각은 끊지 않고, 그 뒤부터 새 순서로 짠다', () => {
    goTo(at(19, 6, 30));
    store.saveTask(task('a', '보고서', 120));
    store.saveTask(task('b', '메일 정리', 30));
    const cur = firstTaskBlock()!;
    goTo(new Date(cur.start.getTime() + 20 * 60000)); // 'a' 하는 중
    const r = store.reorderTasks(['b', 'a']);
    const blocks = store.getState().plans['2026-10-19'].blocks.filter((b) => b.kind === 'task');
    expect(blocks.find((b) => b.id === cur.id)).toBeDefined(); // 진행 중인 조각 유지
    const next = blocks.filter((b) => b.start >= cur.end);
    expect(next[0].taskId).toBe('b'); // 그 뒤는 새 순서
    expect(r.replanned).toBe(true);
    // 하던 일을 끝내면 그 조각은 지금에서 끊는다
    store.toggleTaskDone('a');
    expect(store.getState().plans['2026-10-19'].blocks.some((b) => b.id === cur.id)).toBe(false);
  });

  test('빈 시간이 모자라 밀려난 할 일을 알려 준다', () => {
    goTo(at(19, 6, 30));
    const r = store.saveTask(task('big', '대형 프로젝트', 900));
    expect(r.deferred).toContain('대형 프로젝트');
  });

  test('첫날 기록 중에는 일정을 짜지 않는다', () => {
    store.resetAll();
    goTo(at(19, 6, 0));
    store.startObservation();
    const r = store.saveTask(task('a', '보고서', 60));
    expect(r.replanned).toBe(false);
  });
});

describe('걸리는 시간 자동 보정', () => {
  const d = (ratios: [string, TaskItem['type'], number, number][]) => ({
    ...emptyDurations(),
    samples: ratios.map(([title, type, est, actual], i) => ({ at: at(10 + i, 20), type, title, est, actual })),
  });

  test('같은 종류 3건부터 실제/예상 중앙값으로 보정한다', () => {
    const two = d([['영어', 'homework', 60, 80], ['수학', 'homework', 40, 52]]);
    expect(calibrationFor(two, { type: 'homework', title: '국어' })).toBeNull();
    const three = d([['영어', 'homework', 60, 80], ['수학', 'homework', 40, 52], ['과학', 'homework', 30, 40]]);
    const c = calibrationFor(three, { type: 'homework', title: '국어' })!;
    expect(c.basis).toBe('type');
    expect(c.ratio).toBeCloseTo(1.3, 2);
    expect(plannedMinutes(task('x', '국어', 60, 'homework'), three)).toBe(80);
    expect(calibrationText({ type: 'homework', title: '국어' }, c, '숙제')).toBe('숙제는 보통 예상보다 1.3배 걸렸어요');
  });

  test('같은 이름이 2건 있으면 이름 기준이 먼저다', () => {
    const s = d([['영어 숙제 1', 'homework', 60, 90], ['영어숙제2', 'homework', 60, 90], ['수학', 'homework', 60, 60], ['과학', 'homework', 60, 60], ['사회', 'homework', 60, 60]]);
    expect(normTitle('영어 숙제 3')).toBe('영어숙제');
    const c = calibrationFor(s, { type: 'homework', title: '영어 숙제' })!;
    expect(c.basis).toBe('title');
    expect(c.ratio).toBe(1.5);
    expect(calibrationFor(s, { type: 'homework', title: '국어' })).toBeNull(); // 종류 중앙값 1.0 → 보정 안 함
  });

  test('비율은 0.5~2배로 묶고, 끄면 보정하지 않는다', () => {
    const s = d([['a', 'work', 10, 100], ['b', 'work', 10, 100], ['c', 'work', 10, 100]]);
    expect(calibrationFor(s, { type: 'work', title: 'z' })!.ratio).toBe(2);
    expect(calibrationFor({ ...s, on: false }, { type: 'work', title: 'z' })).toBeNull();
  });

  test('끝낼 때 오늘 지난 조각만큼을 실제 시간으로 남기고, 일정에 반영한다', () => {
    goTo(at(19, 9, 0));
    store.saveTask(task('a', '보고서', 60));
    const b = firstTaskBlock()!;
    goTo(new Date(b.start.getTime() + 40 * 60000)); // 40분 만에 끝냄
    store.toggleTaskDone('a');
    const smp = store.getState().durations.samples;
    expect(smp).toHaveLength(1);
    expect(smp[0]).toMatchObject({ est: 60, actual: 40, taskId: 'a' });
    // 완료를 취소하면 기록도 지운다
    store.toggleTaskDone('a');
    expect(store.getState().durations.samples).toHaveLength(0);
  });

  test('일정 밖에서 끝내면 실제 시간을 모르니 남기지 않는다', () => {
    goTo(at(19, 9, 0));
    store.saveTask(task('a', '보고서', 60));
    store.toggleTaskDone('a');
    expect(store.getState().durations.samples).toHaveLength(0);
  });

  test('잡은 시간을 다 써도 자동 완료하지 않고, 늘리면 다시 배치한다', () => {
    goTo(at(19, 9, 0));
    store.saveTask(task('a', '메일', 30));
    const b = firstTaskBlock()!;
    goTo(new Date(b.end.getTime() + 60000));
    store.markDid('2026-10-19', b);
    const t = store.getState().tasks[0];
    expect(t.done).toBeFalsy();
    expect(store.taskPlanMinutes(store.getState(), t).remaining).toBe(0);
    store.extendTask('a', 30);
    const t2 = store.getState().tasks[0];
    expect(store.taskPlanMinutes(store.getState(), t2)).toEqual({ planned: 60, remaining: 30 });
    const later = store.getState().plans['2026-10-19'].blocks.filter((x) => x.kind === 'task' && x.taskId === 'a' && x.start > b.end);
    expect(later.reduce((n, x) => n + (x.end.getTime() - x.start.getTime()) / 60000, 0)).toBe(30);
    // 다 끝내면 실제 60분(30 + 30)으로 남는다
    goTo(new Date(later[0].end.getTime() + 60000));
    store.toggleTaskDone('a');
    expect(store.getState().durations.samples[0]).toMatchObject({ est: 30, actual: 60 });
  });

  test('보정이 쌓이면 새 할 일을 더 길게 잡는다', () => {
    goTo(at(19, 9, 0));
    const st = store.getState();
    store.replaceState({ ...st, durations: d([['a', 'homework', 60, 90], ['b', 'homework', 60, 90], ['c', 'homework', 60, 90]]) });
    store.saveTask(task('h', '영어', 60, 'homework'));
    const mins = store.getState().plans['2026-10-19'].blocks.filter((x) => x.taskId === 'h').reduce((n, x) => n + (x.end.getTime() - x.start.getTime()) / 60000, 0);
    expect(mins).toBe(90);
  });
});

const ICS = `BEGIN:VCALENDAR\r
VERSION:2.0\r
X-WR-CALNAME:내 캘린더\r
BEGIN:VTIMEZONE\r
TZID:Asia/Seoul\r
BEGIN:STANDARD\r
TZOFFSETFROM:+0900\r
TZOFFSETTO:+0900\r
DTSTART:19700101T000000\r
END:STANDARD\r
END:VTIMEZONE\r
BEGIN:VEVENT\r
UID:once@x\r
DTSTART;TZID=Asia/Seoul:20261020T100000\r
DTEND;TZID=Asia/Seoul:20261020T113000\r
SUMMARY:팀 회의\\, 주간\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:utc@x\r
DTSTART:20261021T050000Z\r
DURATION:PT45M\r
SUMMARY:점심 약속\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:class@x\r
DTSTART;TZID=Asia/Seoul:20261005T090000\r
DTEND;TZID=Asia/Seoul:20261005T103000\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261130T000000Z\r
EXDATE;TZID=Asia/Seoul:20261021T090000\r
SUMMARY:경영학원론\r
BEGIN:VALARM\r
ACTION:DISPLAY\r
DESCRIPTION:알림\r
TRIGGER:-PT10M\r
END:VALARM\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:class@x\r
RECURRENCE-ID;TZID=Asia/Seoul:20261026T090000\r
DTSTART;TZID=Asia/Seoul:20261026T130000\r
DTEND;TZID=Asia/Seoul:20261026T143000\r
SUMMARY:경영학원론(보강)\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:allday@x\r
DTSTART;VALUE=DATE:20261022\r
DTEND;VALUE=DATE:20261023\r
SUMMARY:휴가\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:free@x\r
DTSTART:20261022T010000Z\r
DTEND:20261022T020000Z\r
TRANSP:TRANSPARENT\r
SUMMARY:참고\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:cancel@x\r
STATUS:CANCELLED\r
DTSTART:20261022T030000Z\r
DTEND:20261022T040000Z\r
SUMMARY:취소됨\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:daily@x\r
DTSTART;TZID=Asia/Seoul:20261019T070000\r
DTEND;TZID=Asia/Seoul:20261019T073000\r
RRULE:FREQ=DAILY;COUNT=3\r
SUMMARY:아침 스터디\r
END:VEVENT\r
END:VCALENDAR\r
`;

describe('.ics 가져오기', () => {
  const from = new Date(2026, 9, 19);
  const to = new Date(2026, 10, 2);
  const r = parseIcs(ICS, from, to);
  const fmt = (d: Date) => `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  const list = r.events.map((e) => `${fmt(e.start)}-${fmt(e.end).slice(-5)} ${e.title}`);

  test('시간대·UTC·기간·이스케이프를 읽는다', () => {
    expect(r.calName).toBe('내 캘린더');
    expect(list).toContain('10/20 10:00-11:30 팀 회의, 주간');
    expect(list).toContain('10/21 14:00-14:45 점심 약속');
  });

  test('반복 일정을 펼치고, 빠진 날과 바뀐 날을 반영한다', () => {
    const cls = list.filter((x) => x.includes('경영학원론'));
    expect(cls).toEqual(['10/19 09:00-10:30 경영학원론', '10/26 13:00-14:30 경영학원론(보강)', '10/28 09:00-10:30 경영학원론']);
    expect(list.filter((x) => x.includes('아침 스터디'))).toHaveLength(3);
  });

  test('하루 종일·한가함·취소 일정은 빼고 센다', () => {
    expect(list.some((x) => /휴가|참고|취소됨/.test(x))).toBe(false);
    expect(r.skipped).toMatchObject({ allDay: 1, free: 1 });
  });

  test('가져오면 그 캘린더 일정을 통째로 바꾸고, 일정을 다시 짠다', () => {
    goTo(at(19, 6, 30));
    const one = parseIcs(ICS, from, to).events;
    const res = store.importCalendar({ id: 'ics-file', kind: 'ics', name: '내 캘린더' }, one);
    expect(res.count).toBe(one.length);
    expect(store.getState().events.filter((e) => e.source === 'ics-file')).toHaveLength(one.length);
    store.saveEvent({ id: 'mine', title: '직접 넣은 일정', start: at(23, 15), end: at(23, 16) });
    // 다시 가져오면 직접 넣은 일정은 남기고 가져온 것만 바꾼다
    store.importCalendar({ id: 'ics-file', kind: 'ics', name: '내 캘린더' }, one.slice(0, 2));
    const ev = store.getState().events;
    expect(ev.filter((e) => e.source === 'ics-file')).toHaveLength(2);
    expect(ev.some((e) => e.id === 'mine')).toBe(true);
    expect(store.getState().calendars[0]).toMatchObject({ id: 'ics-file', count: 2 });
    // 오늘 9시 수업이 일정에 들어간다
    expect(store.getState().plans['2026-10-19'].blocks.some((b) => b.title === '경영학원론')).toBe(true);
    store.removeCalendar('ics-file');
    expect(store.getState().events.map((e) => e.id)).toEqual(['mine']);
    expect(store.getState().calendars).toHaveLength(0);
  });
});

describe('비정상 상황', () => {
  test('5분 안 된 기록은 남기지 않고, 1/3~3배를 벗어나면 보정에서 뺀다', async () => {
    const { addSample } = await import('../duration');
    let d = emptyDurations();
    d = addSample(d, { at: at(19, 9), type: 'work', title: 'a', est: 60, actual: 3 });
    expect(d.samples).toHaveLength(0);
    d = addSample(d, { at: at(19, 9), type: 'work', title: 'a', est: 30, actual: 600 }); // 며칠 묵힘
    expect(d.samples[0].outlier).toBe(true);
    d = addSample(d, { at: at(19, 9), type: 'work', title: 'b', est: 60, actual: 90 });
    d = addSample(d, { at: at(19, 9), type: 'work', title: 'c', est: 60, actual: 90 });
    expect(calibrationFor(d, { type: 'work', title: 'z' })).toBeNull(); // 정상 2건뿐
    d = addSample(d, { at: at(19, 9), type: 'work', title: 'd', est: 60, actual: 90 });
    expect(calibrationFor(d, { type: 'work', title: 'z' })!.ratio).toBe(1.5);
  });

  test('직접 넣은 일정과 같은 일정은 가져오지 않는다(중복)', () => {
    goTo(at(19, 6, 30));
    store.saveEvent({ id: 'm', title: '팀 회의', start: at(20, 10), end: at(20, 11) });
    const r = store.importCalendar({ id: 'g', kind: 'ics', name: 'x' }, [
      { uid: '1', title: '팀  회의', start: at(20, 10), end: at(20, 11) },
      { uid: '2', title: '수업', start: at(20, 13), end: at(20, 14) },
    ]);
    expect(r).toMatchObject({ count: 1, dupes: 1 });
  });

  test('너무 많은 일정은 잘라서 저장 공간을 지킨다', () => {
    goTo(at(19, 6, 30));
    const many = Array.from({ length: store.MAX_IMPORT + 50 }, (_, i) => ({ uid: `u${i}`, title: `e${i}`, start: new Date(at(20, 0).getTime() + i * 60000), end: new Date(at(20, 0).getTime() + i * 60000 + 30000) }));
    const r = store.importCalendar({ id: 'g', kind: 'ics', name: 'x' }, many);
    expect(r).toMatchObject({ count: store.MAX_IMPORT, capped: 50 });
  });

  test('.ics가 아니거나, 비었거나, 0개로 기존 일정을 지우게 되면 먼저 막거나 묻는다', async () => {
    const { checkIcs } = await import('../calendarSync');
    goTo(at(19, 6, 30));
    expect(checkIcs('hello', 'a.txt', 5).kind).toBe('error');
    expect(checkIcs('BEGIN:VCALENDAR', 'big.ics', 6 * 1024 * 1024).kind).toBe('error');
    const empty = 'BEGIN:VCALENDAR\nX-WR-CALNAME:시간표\nEND:VCALENDAR';
    expect(checkIcs(empty, 'x.ics', 40).kind).toBe('error'); // 처음이면 그냥 알림
    const ok = checkIcs(ICS.replace('X-WR-CALNAME:내 캘린더', 'X-WR-CALNAME:시간표'), 'x.ics', 1000);
    expect(ok.kind).toBe('ready');
    if (ok.kind === 'ready') expect(ok.run().ok).toBe(true);
    const again = checkIcs(empty, 'x.ics', 40);
    expect(again.kind).toBe('empty-replace'); // 이미 가져온 게 있으면 지울지 묻는다
    expect(store.getState().events.some((e) => e.source === 'ics:시간표')).toBe(true); // 묻기 전에는 그대로
  });

  test('구글 연결이 만료되면 이전 일정은 그대로 두고 다시 연결을 표시한다', async () => {
    const { syncGoogle } = await import('../calendarSync');
    goTo(at(19, 6, 30));
    store.setGoogleClientId('abc.apps.googleusercontent.com');
    store.importCalendar({ id: 'google', kind: 'google', name: '구글' }, [{ uid: '1', title: '회의', start: at(20, 10), end: at(20, 11) }]);
    const r = await syncGoogle(false);
    expect(r.ok).toBe(false);
    const g = store.getState().calendars.find((c) => c.id === 'google')!;
    expect(g.needsAuth).toBe(true);
    expect(store.getState().events.filter((e) => e.source === 'google')).toHaveLength(1);
  });
});
