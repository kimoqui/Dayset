import 'package:dayset/app/goal_text.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('목표 글 읽기(기타) — 웹과 같은 결과', () {
    test('기상 시각과 저녁 운동을 읽는다', () {
      final r = readGoalText('6시 반에 일어나고 저녁 8시에 30분 달리기');
      expect(r.focus, [GoalFocus.wake, GoalFocus.exercise]);
      expect(r.wake, 6 * 60 + 30);
      expect(r.exerciseTitle, '달리기');
      expect(r.exerciseMinutes, 30);
      expect(r.exerciseStart, 20 * 60);
      expect(r.unknown, isEmpty);
    });

    test('잠드는 시각과 수면 시간을 읽는다', () {
      final r = readGoalText('11시 전에 자고 7시간 반 자기');
      expect(r.focus, [GoalFocus.sleep]);
      expect(r.sleepMinutes, 450);
      expect(r.bedtime, 23 * 60);
    });

    test('잠드는 시각만 있으면 기상과의 차이로 수면 시간을 정한다', () {
      final r = readGoalText('밤 12시 전에 잠들고 아침 7시에 기상');
      expect(r.wake, 7 * 60);
      expect(r.bedtime, 24 * 60);
      expect(r.sleepMinutes, 420);
    });

    test('아침 식사·할 일을 읽고, 아침 시각과 헷갈리지 않는다', () {
      expect(readGoalText('아침 꼭 챙겨 먹고 토익 공부 미루지 않기').focus, [GoalFocus.breakfast, GoalFocus.tasks]);
      final w = readGoalText('아침 6시에 일어나기');
      expect(w.focus, [GoalFocus.wake]);
      expect(w.wake, 360);
    });

    test('우리말 숫자와 늦잠을 읽는다', () {
      final r = readGoalText('늦잠 자지 말고 여섯 시에 일어나기, 여덟 시간 자기');
      expect(r.focus, [GoalFocus.wake, GoalFocus.sleep]);
      expect(r.wake, 360);
      expect(r.sleepMinutes, 480);
    });

    test('운동 이름·길이: 헬스 1시간, 요가', () {
      expect(readGoalText('헬스 1시간').exerciseMinutes, 60);
      expect(readGoalText('헬스 1시간').exerciseStart, isNull);
      expect(readGoalText('아침 7시에 요가 20분').exerciseStart, 7 * 60);
      expect(readGoalText('살 빼기').focus, [GoalFocus.exercise]);
    });

    test('읽지 못한 부분은 숨기지 않는다', () {
      final r = readGoalText('물 2리터 마시기, 명상하고 싶어');
      expect(r.focus, isEmpty);
      expect(r.unknown, ['물 2리터 마시기', '명상']);
      expect(readGoalText('운동하고 싶어').unknown, isEmpty);
    });

    test('빈 글은 아무것도 고르지 않고, 예시는 모두 무언가를 읽는다', () {
      expect(readGoalText('   ').focus, isEmpty);
      for (final e in goalExamples) {
        expect(readGoalText(e).focus, isNotEmpty);
      }
    });

    test('알아들은 것을 칩 글로 만든다', () {
      final r = readGoalText('6시 반에 일어나고 저녁 8시에 30분 달리기');
      expect([for (final f in r.found) f.text], ['일찍 일어나기 · 6:30 기상', '운동 습관 · 달리기 30분 · 20:00']);
    });

    test('읽은 운동 이름·시각을 목표에 넣고, 백업 JSON에도 남긴다', () {
      final store = Store(storage: StateStorage(MemoryStore()));
      store.setFixedClock(DateTime(2026, 11, 1, 21));
      final r = readGoalText('6시 반에 일어나고 저녁 8시에 30분 달리기');
      store.setIntent(
        focus: r.focus,
        wake: r.wake!,
        sleepMinutes: 420,
        exerciseMinutes: r.exerciseMinutes!,
        exerciseTitle: r.exerciseTitle,
        exerciseStart: r.exerciseStart,
        note: '6시 반에 일어나고 저녁 8시에 30분 달리기',
      );
      final ex = store.state.goals.exercise!;
      expect(ex.title, '달리기');
      expect(ex.start.minutes, 20 * 60);
      expect(ex.minutes, 30);
      final back = deserialize(serialize(store.state)).intent!;
      expect(back.exerciseTitle, '달리기');
      expect(back.exerciseStart, 1200);
      expect(back.note, startsWith('6시 반'));
    });
  });
}
