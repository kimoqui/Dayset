// 기록 시각 고치기(제때 누르지 못한 기록). Flutter test/app/log_edit_test.dart와 같은 기대값.

import { makeLog, type ActivityLog } from '../../engine/models';
import { retimeLogs } from '../logEdit';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';

const at = (h: number, m = 0) => new Date(2026, 10, 2, h, m);
const now = at(12, 0);
const logs = (): ActivityLog[] => [
  makeLog({ id: 'a', activity: 'meal', start: at(7, 30), end: at(8, 0), source: 'button' }),
  makeLog({ id: 'b', activity: 'work', start: at(8, 0), end: at(10, 0), source: 'button' }),
  makeLog({ id: 'c', activity: 'rest', start: at(10, 0), end: null, source: 'button' }),
];
const span = (l: ActivityLog) => `${l.id} ${l.start.getHours()}:${l.start.getMinutes()}-${l.end ? `${l.end.getHours()}:${l.end.getMinutes()}` : 'now'}`;

describe('기록 시각 고치기', () => {
  it('시작을 앞당기면 앞 기록이 그 시각에 끝난다', () => {
    const r = retimeLogs(logs(), 'b', at(7, 45), at(10, 0), now);
    expect(r.ok && r.logs.map(span)).toEqual(['a 7:30-7:45', 'b 7:45-10:0', 'c 10:0-now']);
    expect(r.ok && r.logs[1].confirmed).toBe(true);
  });

  it('진행 중인 기록의 시작을 앞당기면 앞 기록 끝도 맞춘다', () => {
    const r = retimeLogs(logs(), 'c', at(9, 30), null, now);
    expect(r.ok && r.logs.map(span)).toEqual(['a 7:30-8:0', 'b 8:0-9:30', 'c 9:30-now']);
  });

  it('끝을 늦추면 뒤 기록이 그 시각부터 시작한다', () => {
    const r = retimeLogs(logs(), 'a', at(7, 30), at(8, 20), now);
    expect(r.ok && r.logs.map(span)).toEqual(['a 7:30-8:20', 'b 8:20-10:0', 'c 10:0-now']);
  });

  it('다른 기록을 통째로 덮거나 한가운데로 들어가면 바꾸지 않는다', () => {
    const cover = retimeLogs(logs(), 'b', at(7, 0), at(10, 0), now);
    expect(cover).toEqual({ ok: false, error: '식사 기록(07:30–08:00)을 통째로 덮어요. 그 기록을 먼저 지워 주세요' });
    const inside = retimeLogs(logs(), 'a', at(8, 30), at(9, 0), now);
    expect(inside).toEqual({ ok: false, error: '업무 기록(08:00–10:00) 한가운데예요. 그 기록을 먼저 고쳐 주세요' });
    const open = retimeLogs(logs(), 'b', at(8, 0), at(10, 30), now);
    expect(open).toEqual({ ok: false, error: '지금 기록 중인 휴식을 덮어요. 끝 시각을 더 이르게 해 주세요' });
  });

  it('지금보다 늦거나 거꾸로 된 시각은 받지 않는다', () => {
    expect(retimeLogs(logs(), 'b', at(8, 0), at(12, 30), now)).toEqual({ ok: false, error: '끝 시각이 지금보다 늦어요' });
    expect(retimeLogs(logs(), 'b', at(9, 0), at(9, 0), now)).toEqual({ ok: false, error: '끝 시각은 시작보다 1분 이상 뒤여야 해요' });
    expect(retimeLogs(logs(), 'c', at(12, 10), null, now)).toEqual({ ok: false, error: '시작 시각이 지금보다 늦어요' });
    expect(retimeLogs(logs(), 'b', at(8, 0), null, now)).toEqual({ ok: false, error: '끝난 기록은 끝 시각이 필요해요' });
  });
});

describe('늦게 누른 기록(store.tapAt)', () => {
  beforeEach(() => store.resetAll());

  it('일정 시각부터 한 것으로 기록하고 앞 기록은 그 시각에 끝난다', () => {
    store.setFixedClock(at(6, 0));
    store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
    store.setFixedClock(at(8, 0));
    store.tap('meal');
    store.setFixedClock(at(9, 40));
    const r = store.tapAt('work', at(9, 0));
    expect(r.changed).toBe(true);
    expect(r.error).toBeUndefined();
    const ls = store.getState().logs.filter((l) => l.source !== 'estimate');
    expect(ls.map((l) => `${l.activity} ${l.start.getHours()}:${l.start.getMinutes()}-${l.end ? `${l.end.getHours()}:${l.end.getMinutes()}` : 'now'}`)).toEqual(['meal 8:0-9:0', 'work 9:0-now']);
    // 다음 '지금' 버튼도 바뀐 기록을 이어 쓴다.
    store.setFixedClock(at(10, 0));
    store.tap('rest');
    expect(store.getState().logs.filter((l) => l.source !== 'estimate').map((l) => l.activity)).toEqual(['meal', 'work', 'rest']);
  });

  it('앞 기록보다 이른 시각이면 지금부터로 두고 이유를 알려 준다', () => {
    store.setFixedClock(at(6, 0));
    store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
    store.setFixedClock(at(9, 10));
    store.tap('meal');
    store.setFixedClock(at(9, 40));
    const r = store.tapAt('work', at(9, 0));
    expect(r.error).toBe('식사 기록(09:10–09:40)을 통째로 덮어요. 그 기록을 먼저 지워 주세요');
    const cur = store.getState().logs.at(-1)!;
    expect(cur.activity).toBe('work');
    expect(cur.start).toEqual(at(9, 40));
  });

  it('기록 시각을 고친다', () => {
    store.setFixedClock(at(6, 0));
    store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: {}, usualWake: 7 * 60 });
    store.setFixedClock(at(8, 0));
    store.tap('meal');
    store.setFixedClock(at(8, 30));
    store.tap('work');
    const meal = store.getState().logs.find((l) => l.activity === 'meal')!;
    expect(store.retimeLog(meal.id, at(7, 40), at(8, 10))).toBeNull();
    const ls = store.getState().logs.filter((l) => l.source !== 'estimate');
    expect(ls.map((l) => `${l.activity} ${l.start.getHours()}:${l.start.getMinutes()}`)).toEqual(['meal 7:40', 'work 8:30']);
  });
});
