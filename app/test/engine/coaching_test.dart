import 'package:dayset/core/engine/coaching.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, int m, {int day = 14}) => DateTime(2026, 10, day, h, m);

ScheduleBlock b(String id, Activity a, DateTime s, int minutes,
        {BlockKind kind = BlockKind.habit, bool focus = false}) =>
    ScheduleBlock(
      id: id,
      kind: kind,
      activity: a,
      title: a.label,
      start: s,
      end: s.add(Duration(minutes: minutes)),
      focus: focus,
    );

void main() {
  final engine = CoachingEngine();
  final today = [
    b('ex', Activity.exercise, at(20, 30), 30),
    b('f1', Activity.work, at(9, 0), 50, kind: BlockKind.task, focus: true),
    b('f2', Activity.work, at(10, 0), 50, kind: BlockKind.task, focus: true),
    b('f3', Activity.work, at(14, 0), 50, kind: BlockKind.task, focus: true),
  ];

  test('R1: 6시간 미만 수면이면 운동을 줄이고 집중 작업을 2개로 제한한다', () {
    final s = engine.evaluate(const WakeLogged(sleepMinutes: 340), today: today, now: at(7, 0));
    expect(s.single.ruleId, 'R1');
    expect(s.single.message, '어젯밤 5시간 40분 잤어요. 오늘 운동을 15분 가벼운 루틴으로 바꿀까요?');
    expect(s.single.changes.where((c) => c.deferToTomorrow).single.blockId, 'f3');

    final applied = applyChanges(today, s.single.changes);
    final ex = applied.blocks.firstWhere((x) => x.id == 'ex');
    expect(ex.minutes, 15);
    expect(ex.adjusted, isTrue);
    expect(applied.deferred.single.id, 'f3');
  });

  test('R1: 잠을 충분히 잤으면 제안하지 않는다', () {
    expect(engine.evaluate(const WakeLogged(sleepMinutes: 400), today: today, now: at(7, 0)), isEmpty);
  });

  test('R3: 업무가 60분 이상 늦게 끝나면 운동을 줄인다', () {
    final s = engine.evaluate(WorkEnded(planned: at(18, 0), actual: at(19, 10)),
        today: today, now: at(19, 10));
    expect(s.single.message, startsWith('업무가 예정보다 1시간 10분 늦게 끝났어요.'));
  });

  test('R4: 3일 연속 스누즈 3회 이상이면 취침을 앞당긴다', () {
    final s = engine.evaluate(const WakeLogged(sleepMinutes: 420, recentSnoozes: [1, 3, 4, 3]),
        today: today, now: at(7, 0));
    expect(s.single.ruleId, 'R4');
    expect(s.single.patch['bedtime_shift_minutes'], -15);
  });

  test('R2: 저녁을 취침 3시간 안에 마치면 내일 저녁을 앞당긴다', () {
    final s = engine.evaluate(DinnerLogged(end: at(21, 30), bedtime: at(23, 30)),
        today: today, now: at(21, 30));
    expect(s.single.message, startsWith('저녁을 취침 2시간 전에 마쳤어요.'));
  });

  test('R6·R7: 조사(을/를, 이/가)를 받침에 맞춘다', () {
    final r6 = engine.evaluate(
        const MissReasonAdded(habit: Activity.exercise, reason: MissReason.forgot, weekCount: 2),
        today: today,
        now: at(21, 0));
    expect(r6.single.message, startsWith('이번 주 운동을 깜빡해서 2번 놓쳤어요.'));
    final r7 = engine.evaluate(
        const MissReasonAdded(habit: Activity.meal, reason: MissReason.conflict, weekCount: 2),
        today: today,
        now: at(21, 0));
    expect(r7.single.message, startsWith('이번 주 식사가 일·약속과 2번 겹쳤어요.'));
  });

  test('실패 이유가 한 번뿐이면 제안하지 않는다', () {
    expect(
      engine.evaluate(
          const MissReasonAdded(habit: Activity.sleep, reason: MissReason.tired, weekCount: 1),
          today: today,
          now: at(21, 0)),
      isEmpty,
    );
  });

  group('제안 빈도 제한', () {
    const policy = CoachingPolicy();

    test('하루 3건까지만 보여준다', () {
      final history = [
        for (var i = 0; i < 3; i++)
          CoachRecord(ruleId: 'R$i', at: at(8 + i, 0), decision: CoachDecision.accepted),
      ];
      expect(policy.allows('R5', at(21, 0), history), isFalse);
      expect(policy.allows('R5', at(9, 0, day: 15), history), isTrue);
    });

    test('같은 규칙을 2번 연속 거절하면 7일 쉰다', () {
      final history = [
        CoachRecord(ruleId: 'R1', at: at(7, 0, day: 10), decision: CoachDecision.rejected),
        CoachRecord(ruleId: 'R1', at: at(7, 0, day: 11), decision: CoachDecision.rejected),
      ];
      expect(policy.allows('R1', at(7, 0, day: 14), history), isFalse);
      expect(policy.allows('R1', at(7, 0, day: 18), history), isTrue);
    });

    test('규칙을 끄면 제안하지 않는다', () {
      final off = CoachingEngine(rules: parseRules([
        {'id': 'R1', 'enabled': false},
      ]));
      expect(off.evaluate(const WakeLogged(sleepMinutes: 300), today: today, now: at(7, 0)), isEmpty);
    });
  });
}
