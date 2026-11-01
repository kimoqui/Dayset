import { describe, expect, it } from 'vitest';
import { CHAT_EXAMPLES, interpretChat } from '../chatCommand';
import { applyEdit, describeEdit, previewEdits } from '../edits';
import { planFor } from '../derive';
import { demoState } from '../seed';
import { dateKey, addDays, formatHm } from '../../engine/models';

const now = new Date(2026, 10, 2, 9, 0); // 월요일 오전 9시
const s = demoState(now);
const today = dateKey(now);
const tomorrow = dateKey(addDays(now, 1));

describe('채팅으로 일정 바꾸기(규칙)', () => {
  it('내일 운동 시각 옮기기', () => {
    const r = interpretChat('내일 운동 7시로 옮겨줘', s, now);
    expect(r.edits).toEqual([{ kind: 'habit', day: tomorrow, title: '운동', patch: { start: 19 * 60 }, scope: 'day' }]);
  });

  it('오늘 점심 30분 늦추기(지금 값 기준)', () => {
    const r = interpretChat('오늘 점심 30분 늦춰', s, now);
    expect(r.edits).toEqual([{ kind: 'habit', day: today, title: '점심 식사', patch: { start: 12 * 60 + 30 }, scope: 'day' }]);
  });

  it('빼기·매일·길이', () => {
    expect(interpretChat('오늘 운동 빼줘', s, now).edits[0]).toMatchObject({ kind: 'habit', title: '운동', patch: { skip: true }, scope: 'day' });
    expect(interpretChat('매일 저녁 식사 7시로 바꿔', s, now).edits[0]).toMatchObject({ title: '저녁 식사', patch: { start: 19 * 60 }, scope: 'every' });
    expect(interpretChat('오늘 운동 20분으로 줄여', s, now).edits[0]).toMatchObject({ patch: { minutes: 20 } });
  });

  it('지난 습관은 날짜 말이 없으면 내일로 본다', () => {
    const r = interpretChat('아침 식사 8시로', s, now); // 아침 식사(7:30~8:00)는 이미 지남
    expect(r.edits[0]).toMatchObject({ day: tomorrow, title: '아침 식사', patch: { start: 8 * 60 } });
  });

  it('기상 알람', () => {
    expect(interpretChat('내일 6시 반에 깨워줘', s, now).edits[0]).toEqual({ kind: 'wake', day: tomorrow, minutes: 390, scope: 'day' });
    expect(interpretChat('앞으로 매일 6시에 일어날래', s, now).edits[0]).toMatchObject({ kind: 'wake', minutes: 360, scope: 'every' });
  });

  it('새 캘린더 일정·옮기기·지우기', () => {
    const add = interpretChat('금요일 3시 치과 1시간 추가', s, now).edits[0];
    expect(add).toMatchObject({ kind: 'event-add', title: '치과' });
    if (add.kind === 'event-add') {
      expect(formatHm(add.start)).toBe('15:00');
      expect(formatHm(add.end)).toBe('16:00');
    }
    // 예시 데이터: 내일 9시 팀 회의
    const mv = interpretChat('팀 회의 11시로 옮겨줘', s, now).edits[0];
    expect(mv).toMatchObject({ kind: 'event-move', id: 'ev-2' });
    if (mv.kind === 'event-move') expect(formatHm(mv.start)).toBe('11:00');
    expect(interpretChat('팀 회의 취소', s, now).edits[0]).toEqual({ kind: 'event-delete', id: 'ev-2' });
  });

  it('할 일 넣기', () => {
    expect(interpretChat('할 일 보고서 2시간 추가', s, now).edits[0]).toMatchObject({ kind: 'task-add', title: '보고서', minutes: 120, type: 'work' });
  });

  it('여러 개를 한 번에, 읽지 못한 건 알려 준다', () => {
    const r = interpretChat('내일 6시에 깨워줘, 내일 운동 빼줘, 물 많이 마시기', s, now);
    expect(r.edits.map((e) => e.kind)).toEqual(['wake', 'habit']);
    expect(r.unknown).toEqual(['물 많이 마시기']);
    expect(interpretChat('안녕', s, now).reply).toContain('이렇게 말해 주세요');
  });

  it('예시는 모두 무언가를 바꾼다', () => {
    for (const e of CHAT_EXAMPLES) expect(interpretChat(e, s, now).edits.length, e).toBeGreaterThan(0);
  });
});

describe('일정 바꾸기 적용·미리보기', () => {
  it('그날만 바꾼 습관은 그날 일정에만, 매일은 목표에', () => {
    // 저녁 식사(18:30~19:30)와 겹치지 않는 21:00으로 옮긴다.
    const day = applyEdit(s, { kind: 'habit', day: tomorrow, title: '운동', patch: { start: 21 * 60, minutes: 45 }, scope: 'day' }, now);
    const ex = planFor(day, tomorrow, now).blocks.find((b) => b.activity === 'exercise')!;
    expect(formatHm(ex.start)).toBe('21:00');
    expect((ex.end.getTime() - ex.start.getTime()) / 60000).toBe(45);
    expect(day.goals.exercise?.start).toBe(s.goals.exercise?.start);
    const every = applyEdit(s, { kind: 'habit', day: tomorrow, title: '운동', patch: { start: 19 * 60 }, scope: 'every' }, now);
    expect(every.goals.exercise?.start).toBe(19 * 60);
  });

  it('빼기·기상·되돌리기', () => {
    const skip = applyEdit(s, { kind: 'habit', day: tomorrow, title: '운동', patch: { skip: true }, scope: 'day' }, now);
    expect(planFor(skip, tomorrow, now).blocks.some((b) => b.activity === 'exercise')).toBe(false);
    const wake = applyEdit(s, { kind: 'wake', day: tomorrow, minutes: 390, scope: 'day' }, now);
    expect(formatHm(planFor(wake, tomorrow, now).wake)).toBe('06:30');
    const back = applyEdit(wake, { kind: 'reset', day: tomorrow }, now);
    expect(planFor(back, tomorrow, now).wake.getTime()).toBe(planFor(s, tomorrow, now).wake.getTime());
  });

  it('미리보기는 바뀌는 것만 문장으로', () => {
    const p = previewEdits(s, [{ kind: 'habit', day: tomorrow, title: '운동', patch: { start: 21 * 60 }, scope: 'day' }], now);
    expect(p).toHaveLength(1);
    expect(p[0].label).toBe('내일');
    expect(p[0].diffs.some((d) => d.startsWith('운동') && d.includes('21:00'))).toBe(true);
    expect(describeEdit(s, { kind: 'wake', day: tomorrow, minutes: 390, scope: 'day' }, now)).toBe('내일 기상 알람: 06:30');
  });
});
