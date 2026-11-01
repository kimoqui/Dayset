import { parseEventText } from '../nlp';
import { formatHm } from '../../engine/models';

const now = new Date(2026, 9, 19, 21, 0); // 월요일
const p = (t: string) => {
  const r = parseEventText(t, now);
  return r && { title: r.title, day: r.start.getDate(), start: formatHm(r.start), end: formatHm(r.end) };
};

test('내일 오전 9시 팀 회의 → 20일 09:00~10:00', () => {
  expect(p('내일 오전 9시 팀 회의')).toEqual({ title: '팀 회의', day: 20, start: '09:00', end: '10:00' });
});

test('시간대 말이 없는 3시는 오후, 길이 30분', () => {
  expect(p('모레 3시 치과 30분')).toEqual({ title: '치과', day: 21, start: '15:00', end: '15:30' });
});

test('요일 + 저녁 + 2시간', () => {
  expect(p('금요일 저녁 7시 친구 약속 2시간')).toEqual({ title: '친구 약속', day: 23, start: '19:00', end: '21:00' });
});

test('10:30~12:00 처럼 끝 시각', () => {
  expect(p('내일 10:30~12:00 수업')).toEqual({ title: '수업', day: 20, start: '10:30', end: '12:00' });
});

test('반, 까지, 조사 정리', () => {
  expect(p('내일 2시 반부터 4시까지 고객 미팅')).toEqual({ title: '고객 미팅', day: 20, start: '14:30', end: '16:00' });
  expect(p('다음주 화요일 오전 11시에 병원')).toEqual({ title: '병원', day: 27, start: '11:00', end: '12:00' });
  expect(p('10월 30일 13:00 발표 1시간 반')).toEqual({ title: '발표', day: 30, start: '13:00', end: '14:30' });
});

test('시각이 없으면 해석하지 않는다', () => {
  expect(p('내일 회의')).toBeNull();
});
