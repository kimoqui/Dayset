// 프리뷰 준비: 처음 목표, 동의, 일정 체크, 베타 지표, 설문.

import { computeMetrics, surveyDue } from '../metrics';
import { checkKey, nowCheck } from '../nowCheck';
import { demoState } from '../seed';
import * as store from '../store';
import { DEFAULT_GOALS } from '../state';

const at = (day: number, h: number, m = 0) => new Date(2026, 9, day, h, m);
const goTo = (d: Date) => store.setFixedClock(d);

beforeEach(() => store.resetAll());

describe('처음 목표 · 동의', () => {
  test('고른 목표·동의·익명 번호는 기록을 시작해도 그대로 남는다', () => {
    goTo(at(19, 9));
    const id = store.getState().profile.id;
    store.setIntent({ focus: ['wake', 'exercise'], wake: 6 * 60 + 30, sleepMinutes: 450, exerciseMinutes: 45 });
    store.setConsent({ health: true, metrics: false });
    store.startObservation();
    const s = store.getState();
    expect(s.onboarded).toBe(true);
    expect(s.intent?.focus).toEqual(['wake', 'exercise']);
    expect(s.consent).toMatchObject({ health: true, metrics: false });
    expect(s.profile.id).toBe(id);
    expect(s.metrics.events.map((e) => e.k)).toEqual(['goal_set', 'consent']);
  });

  test('기록 없이 바로 설정해도 목표가 기본값에 들어간다', () => {
    goTo(at(19, 9));
    store.setIntent({ focus: ['sleep'], wake: 7 * 60, sleepMinutes: 480, exerciseMinutes: 30 });
    expect(store.getState().goals.sleepMinutes).toBe(480);
    store.setConsent({ health: true, metrics: true });
    store.completeOnboarding({ goals: store.getState().goals, settings: {}, usualWake: null });
    expect(store.getState().consent?.metrics).toBe(true);
    expect(store.getState().intent?.focus).toEqual(['sleep']);
  });
});

describe('일정 체크', () => {
  const setup = () => {
    goTo(at(19, 6, 0));
    store.completeOnboarding({ goals: structuredClone(DEFAULT_GOALS), settings: { travelMinutes: 0 }, usualWake: 7 * 60 });
  };

  test('일정이 시작됐는데 기록이 없으면 due, 기록하면 ok', () => {
    setup();
    goTo(at(19, 12, 10)); // 점심 12:00–13:00
    store.tap('work');
    let c = nowCheck(store.getState(), store.now());
    expect(c.kind).toBe('due');
    expect(c.expected).toBe('meal');
    expect(c.block?.title).toBe('점심 식사');
    expect(c.current).toBe('work');
    store.tap('meal');
    c = nowCheck(store.getState(), store.now());
    expect(c.kind).toBe('ok');
  });

  test('지금은 안 해요로 넘기면 skipped, 열쇠는 조각마다 다르다', () => {
    setup();
    goTo(at(19, 12, 10));
    const c1 = nowCheck(store.getState(), store.now());
    store.skipCheck(c1.block!.id);
    const c2 = nowCheck(store.getState(), store.now());
    expect(c2.skipped).toBe(true);
    goTo(at(19, 18, 40)); // 저녁
    const c3 = nowCheck(store.getState(), store.now());
    expect(checkKey(c3)).not.toBe(checkKey(c1));
    expect(c3.skipped).toBe(false);
  });

  test('일정이 끝났는데 그 기록이 이어지면 over로 끝났는지 묻는다', () => {
    setup();
    goTo(at(19, 12, 5));
    store.tap('meal');
    goTo(at(19, 13, 20)); // 점심 13:00에 끝남, 다음 일정 전
    const c = nowCheck(store.getState(), store.now());
    expect(['over', 'due']).toContain(c.kind);
    if (c.kind === 'over') expect(c.block?.title).toBe('점심 식사');
  });

  test('첫날 기록 중에는 체크하지 않는다', () => {
    goTo(at(19, 9));
    store.startObservation();
    expect(nowCheck(store.getState(), store.now()).kind).toBe('none');
  });
});

describe('베타 지표 · 설문', () => {
  test('예시 데이터로 활성화·유지·주별 셋 데이를 계산하고, 이름·제목은 넣지 않는다', () => {
    const now = at(19, 21);
    goTo(now);
    const s = demoState(now);
    const m = computeMetrics(s, now);
    expect(m.anonId).toMatch(/^b-/);
    expect(m.retention.d7).toBe(true);
    expect(m.retention.activeDays).toBeGreaterThan(10);
    expect(m.habit.weeks.length).toBeGreaterThanOrEqual(3);
    expect(m.activation.activated).toBe(true);
    const text = JSON.stringify(m);
    expect(text).not.toContain('분기 보고서');
    expect(text).not.toContain(s.profile.id);
    expect(text).not.toContain('"나"');
  });

  test('설문은 7일째부터, 답하면 다시 묻지 않고, 나중에를 누르면 그날은 묻지 않는다', () => {
    goTo(at(1, 9));
    store.setConsent({ health: true, metrics: true });
    store.startObservation();
    expect(surveyDue(store.getState(), at(5, 9))).toBeNull();
    goTo(at(8, 9));
    expect(surveyDue(store.getState(), store.now())).toBe('d7');
    store.surveyLater();
    expect(surveyDue(store.getState(), store.now())).toBeNull();
    goTo(at(9, 9));
    store.answerSurvey({ key: 'd7', answer: 'very' });
    expect(surveyDue(store.getState(), store.now())).toBeNull();
    expect(surveyDue(store.getState(), at(29, 9))).toBe('d28');
    expect(computeMetrics(store.getState(), store.now()).surveys[0]).toMatchObject({ key: 'd7', answer: 'very', day: 8 });
  });
});
