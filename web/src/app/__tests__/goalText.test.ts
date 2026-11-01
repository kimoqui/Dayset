import { describe, expect, it } from 'vitest';
import { GOAL_EXAMPLES, readGoalText } from '../goalText';

describe('목표 글 읽기(기타)', () => {
  it('기상 시각과 저녁 운동을 읽는다', () => {
    const r = readGoalText('6시 반에 일어나고 저녁 8시에 30분 달리기');
    expect(r.focus).toEqual(['wake', 'exercise']);
    expect(r.wake).toBe(6 * 60 + 30);
    expect(r.exerciseTitle).toBe('달리기');
    expect(r.exerciseMinutes).toBe(30);
    expect(r.exerciseStart).toBe(20 * 60);
    expect(r.unknown).toEqual([]);
  });

  it('잠드는 시각과 수면 시간을 읽는다', () => {
    const r = readGoalText('11시 전에 자고 7시간 반 자기');
    expect(r.focus).toEqual(['sleep']);
    expect(r.sleepMinutes).toBe(450);
    expect(r.bedtime).toBe(23 * 60);
  });

  it('잠드는 시각만 있으면 기상과의 차이로 수면 시간을 정한다', () => {
    const r = readGoalText('밤 12시 전에 잠들고 아침 7시에 기상');
    expect(r.wake).toBe(7 * 60);
    expect(r.bedtime).toBe(24 * 60);
    expect(r.sleepMinutes).toBe(420);
  });

  it('아침 식사·할 일을 읽고, 아침 시각과 헷갈리지 않는다', () => {
    const r = readGoalText('아침 꼭 챙겨 먹고 토익 공부 미루지 않기');
    expect(r.focus).toEqual(['breakfast', 'tasks']);
    const w = readGoalText('아침 6시에 일어나기');
    expect(w.focus).toEqual(['wake']);
    expect(w.wake).toBe(360);
  });

  it('우리말 숫자와 늦잠을 읽는다', () => {
    const r = readGoalText('늦잠 자지 말고 여섯 시에 일어나기, 여덟 시간 자기');
    expect(r.focus).toEqual(['wake', 'sleep']);
    expect(r.wake).toBe(360);
    expect(r.sleepMinutes).toBe(480);
  });

  it('운동 이름·길이: 헬스 1시간, 요가', () => {
    expect(readGoalText('헬스 1시간').exerciseMinutes).toBe(60);
    expect(readGoalText('헬스 1시간').exerciseStart).toBeUndefined();
    expect(readGoalText('아침 7시에 요가 20분').exerciseStart).toBe(7 * 60);
    expect(readGoalText('살 빼기').focus).toEqual(['exercise']);
  });

  it('읽지 못한 부분은 숨기지 않는다', () => {
    const r = readGoalText('물 2리터 마시기, 명상하고 싶어');
    expect(r.focus).toEqual([]);
    expect(r.unknown).toEqual(['물 2리터 마시기', '명상']);
    expect(readGoalText('운동하고 싶어').unknown).toEqual([]);
  });

  it('빈 글은 아무것도 고르지 않고, 예시는 모두 무언가를 읽는다', () => {
    expect(readGoalText('   ').focus).toEqual([]);
    for (const e of GOAL_EXAMPLES) expect(readGoalText(e).focus.length).toBeGreaterThan(0);
  });

  it('알아들은 것을 칩 글로 만든다', () => {
    const r = readGoalText('6시 반에 일어나고 저녁 8시에 30분 달리기');
    expect(r.found.map((f) => f.text)).toEqual(['일찍 일어나기 · 6:30 기상', '운동 습관 · 달리기 30분 · 20:00']);
  });
});
