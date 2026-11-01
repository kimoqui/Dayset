// 프리뷰 준비: 처음 목표, 동의, 일정 체크, 베타 지표, 설문.
// 웹 버전 src/app/__tests__/preview.test.ts를 옮겼다.

import 'dart:convert';

import 'package:dayset/app/metrics.dart';
import 'package:dayset/app/now_check.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

void main() {
  late Store store;
  void goTo(DateTime d) => store.setFixedClock(d);

  setUp(() {
    store = Store(storage: StateStorage(MemoryStore()));
  });

  group('처음 목표 · 동의', () {
    test('고른 목표·동의·익명 번호는 기록을 시작해도 그대로 남는다', () {
      goTo(at(19, 9));
      final id = store.state.profile.id;
      store.setIntent(focus: [GoalFocus.wake, GoalFocus.exercise], wake: 6 * 60 + 30, sleepMinutes: 450, exerciseMinutes: 45);
      store.setConsent(health: true, metrics: false);
      store.startObservation();
      final s = store.state;
      expect(s.onboarded, isTrue);
      expect(s.intent?.focus, [GoalFocus.wake, GoalFocus.exercise]);
      expect(s.consent?.health, isTrue);
      expect(s.consent?.metrics, isFalse);
      expect(s.profile.id, id);
      expect(s.metrics.events.map((e) => e.k).toList(), ['goal_set', 'consent']);
    });

    test('기록 없이 바로 설정해도 목표가 기본값에 들어간다', () {
      goTo(at(19, 9));
      store.setIntent(focus: [GoalFocus.sleep], wake: 7 * 60, sleepMinutes: 480, exerciseMinutes: 30);
      expect(store.state.goals.sleepMinutes, 480);
      store.setConsent(health: true, metrics: true);
      store.completeOnboarding(goals: store.state.goals, settings: const PersonalSettings());
      expect(store.state.consent?.metrics, isTrue);
      expect(store.state.intent?.focus, [GoalFocus.sleep]);
    });
  });

  group('일정 체크', () {
    void setup() {
      goTo(at(19, 6, 0));
      store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(travelMinutes: 0), usualWake: 7 * 60);
    }

    test('일정이 시작됐는데 기록이 없으면 due, 기록하면 ok', () {
      setup();
      goTo(at(19, 12, 10)); // 점심 12:00–13:00
      store.tap(Activity.work);
      var c = nowCheck(store.state, store.now());
      expect(c.kind, CheckKind.due);
      expect(c.expected, Activity.meal);
      expect(c.block?.title, '점심 식사');
      expect(c.current, Activity.work);
      store.tap(Activity.meal);
      c = nowCheck(store.state, store.now());
      expect(c.kind, CheckKind.ok);
    });

    test('지금은 안 해요로 넘기면 skipped, 열쇠는 조각마다 다르다', () {
      setup();
      goTo(at(19, 12, 10));
      final c1 = nowCheck(store.state, store.now());
      store.skipCheck(c1.block!.id);
      final c2 = nowCheck(store.state, store.now());
      expect(c2.skipped, isTrue);
      goTo(at(19, 18, 40)); // 저녁
      final c3 = nowCheck(store.state, store.now());
      expect(c3.key, isNot(c1.key));
      expect(c3.skipped, isFalse);
    });

    test('일정이 끝났는데 그 기록이 이어지면 over로 끝났는지 묻는다', () {
      setup();
      goTo(at(19, 12, 5));
      store.tap(Activity.meal);
      goTo(at(19, 13, 20)); // 점심 13:00에 끝남, 다음 일정 전
      final c = nowCheck(store.state, store.now());
      expect([CheckKind.over, CheckKind.due], contains(c.kind));
      if (c.kind == CheckKind.over) expect(c.block?.title, '점심 식사');
    });

    test('첫날 기록 중에는 체크하지 않는다', () {
      goTo(at(19, 9));
      store.startObservation();
      expect(nowCheck(store.state, store.now()).kind, CheckKind.none);
    });
  });

  group('베타 지표 · 설문', () {
    test('예시 데이터로 활성화·유지·주별 셋 데이를 계산하고, 이름·제목은 넣지 않는다', () {
      final now = at(19, 21);
      goTo(now);
      final s = demoState(now);
      final m = computeMetrics(s, now);
      expect(m['anonId'], startsWith('b-'));
      final retention = m['retention'] as Map;
      expect(retention['d7'], isTrue);
      expect(retention['activeDays'], greaterThan(10));
      expect(((m['habit'] as Map)['weeks'] as List).length, greaterThanOrEqualTo(3));
      expect((m['activation'] as Map)['activated'], isTrue);
      final text = jsonEncode(m);
      expect(text.contains('분기 보고서'), isFalse);
      expect(text.contains(s.profile.id), isFalse);
      expect(text.contains('"나"'), isFalse);
    });

    test('설문은 7일째부터, 답하면 다시 묻지 않고, 나중에를 누르면 그날은 묻지 않는다', () {
      goTo(at(1, 9));
      store.setConsent(health: true, metrics: true);
      store.startObservation();
      expect(surveyDue(store.state, at(5, 9)), isNull);
      goTo(at(8, 9));
      expect(surveyDue(store.state, store.now()), 'd7');
      store.surveyLater();
      expect(surveyDue(store.state, store.now()), isNull);
      goTo(at(9, 9));
      store.answerSurvey(key: 'd7', answer: 'very');
      expect(surveyDue(store.state, store.now()), isNull);
      expect(surveyDue(store.state, at(29, 9)), 'd28');
      final first = (computeMetrics(store.state, store.now())['surveys'] as List).first as Map;
      expect(first['key'], 'd7');
      expect(first['answer'], 'very');
      expect(first['day'], 8);
    });
  });
}
