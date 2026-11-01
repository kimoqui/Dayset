import { NowTracker } from '../nowTracker';
import { isOpen, minutesUntil } from '../models';

const at = (h: number, m: number, s = 0) => new Date(2026, 9, 14, h, m, s);

let t: NowTracker;
let n = 0;
beforeEach(() => {
  t = new NowTracker({ idGenerator: () => `id${n++}` });
});

test('누르면 이전 기록을 끝내고 새 기록을 시작한다', () => {
  t.tap('work', at(9, 0));
  const r = t.tap('meal', at(12, 0));
  expect(r.changed).toBe(true);
  expect(r.ended!.activity).toBe('work');
  expect(r.ended!.end).toEqual(at(12, 0));
  expect(t.current!.activity).toBe('meal');
  expect(t.logs).toHaveLength(2);
});

test('같은 상태를 다시 누르면 아무것도 바뀌지 않는다', () => {
  t.tap('work', at(9, 0));
  expect(t.tap('work', at(9, 30)).changed).toBe(false);
  expect(t.logs).toHaveLength(1);
});

test('5초 안에는 되돌릴 수 있다', () => {
  t.tap('work', at(9, 0));
  t.tap('rest', at(10, 0));
  expect(t.undo(at(10, 0, 4))).toBe(true);
  expect(t.current!.activity).toBe('work');
  expect(isOpen(t.current!)).toBe(true);
  expect(t.logs).toHaveLength(1);
});

test('5초가 지나면 되돌릴 수 없다', () => {
  t.tap('work', at(9, 0));
  t.tap('rest', at(10, 0));
  expect(t.undo(at(10, 0, 6))).toBe(false);
  expect(t.current!.activity).toBe('rest');
});

test('10분 안에 원래 상태로 돌아오면 하나로 합친다', () => {
  t.tap('work', at(9, 0));
  t.tap('rest', at(10, 0));
  const r = t.tap('work', at(10, 5));
  expect(r.merged).toBe(true);
  expect(t.logs).toHaveLength(1);
  expect(t.current!.start).toEqual(at(9, 0));
  expect(isOpen(t.current!)).toBe(true);
});

test('중간 상태가 10분 이상이면 합치지 않는다', () => {
  t.tap('work', at(9, 0));
  t.tap('rest', at(10, 0));
  expect(t.tap('work', at(10, 15)).merged).toBeFalsy();
  expect(t.logs).toHaveLength(3);
});

test('위젯에서 쌓인 탭을 시간순으로 반영한다', () => {
  t.applyExternal([
    { activity: 'meal', at: at(12, 0) },
    { activity: 'work', at: at(9, 0) },
  ]);
  expect(t.logs[0].activity).toBe('work');
  expect(t.logs[0].end).toEqual(at(12, 0));
  expect(t.current!.activity).toBe('meal');
  expect(t.current!.source).toBe('widget');
  expect(t.canUndo(at(12, 0, 1))).toBe(false);
});

test('stop은 현재 기록만 끝낸다', () => {
  t.tap('exercise', at(20, 30));
  const ended = t.stop(at(20, 50));
  expect(minutesUntil(ended!, at(21, 0))).toBe(20);
  expect(t.current).toBeNull();
});
