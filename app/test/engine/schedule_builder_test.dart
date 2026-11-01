import 'package:dayset/core/engine/schedule_builder.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, int m, {int day = 14}) => DateTime(2026, 10, day, h, m);

const goals = HabitGoals(
  wake: ClockTime.hm(7, 0),
  sleepMinutes: 420,
  meals: [
    HabitSlot(title: '아침 식사', activity: Activity.meal, start: ClockTime.hm(7, 30), minutes: 30),
    HabitSlot(title: '점심 식사', activity: Activity.meal, start: ClockTime.hm(12, 0), minutes: 60),
    HabitSlot(title: '저녁 식사', activity: Activity.meal, start: ClockTime.hm(18, 30), minutes: 60),
  ],
  exercise: HabitSlot(title: '운동', activity: Activity.exercise, start: ClockTime.hm(20, 30), minutes: 30),
);

void main() {
  const builder = ScheduleBuilder();

  group('기상·취침 계산', () {
    test('첫 일정이 늦으면 목표 기상을 그대로 쓴다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        fixedEvents: [FixedEvent(id: 'e1', title: '출근', start: at(9, 0), end: at(18, 0))],
      ));
      expect(plan.wake, at(7, 0));
      // 07:00 − 수면 420분 − 잠들기 15분 = 전날 23:45
      expect(plan.bedTonight, at(23, 45, day: 13));
      expect(plan.alarms.first.reason, contains('목표 기상'));
    });

    test('첫 일정이 이르면 준비·이동 시간만큼 당긴다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        fixedEvents: [FixedEvent(id: 'e1', title: '팀 회의', start: at(8, 0), end: at(9, 0))],
      ));
      // 08:00 − 준비 50분 − 이동 40분 = 06:30
      expect(plan.wake, at(6, 30));
      expect(plan.alarms.first.reason, contains('첫 일정 08:00'));
      expect(plan.blocks.any((b) => b.title == '이동' && b.end == at(8, 0)), isTrue);
    });

    test('취침 기록 뒤 기상 알람은 앞당기기만 자동으로 한다', () {
      expect(
        decideWakeChange(current: at(7, 0), proposed: at(6, 40), sleepLogged: true),
        AlarmDecision.apply,
      );
      expect(
        decideWakeChange(current: at(7, 0), proposed: at(7, 20), sleepLogged: true),
        AlarmDecision.needsConfirmation,
      );
      expect(
        decideWakeChange(current: at(7, 0), proposed: at(7, 20), sleepLogged: false),
        AlarmDecision.apply,
      );
    });
  });

  group('습관 뼈대', () {
    test('고정 일정과 겹친 습관은 뒤로 민다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        settings: const PersonalSettings(travelMinutes: 0),
        fixedEvents: [FixedEvent(id: 'e1', title: '점심 미팅', start: at(11, 30), end: at(12, 30))],
      ));
      final lunch = plan.blocks.firstWhere((b) => b.title == '점심 식사');
      expect(lunch.start, at(12, 30));
      expect(lunch.end, at(13, 30));
    });
  });

  group('할 일 배치', () {
    test('50분 조각으로 나누고 블록끼리 겹치지 않는다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [
          TaskItem(id: 't1', title: '분기 보고서', estMinutes: 180, dueAt: at(18, 0, day: 16), focus: true),
        ],
      ));
      final chunks = plan.blocks.where((b) => b.taskId == 't1').toList();
      expect(chunks.fold<int>(0, (s, b) => s + b.minutes), 180);
      expect(chunks.every((b) => b.minutes <= 50), isTrue);
      expect(plan.deferred, isEmpty);

      final dayBlocks = plan.blocks.skip(1).toList(); // 첫 블록은 전날 밤 수면
      for (var i = 0; i < dayBlocks.length; i++) {
        for (var j = i + 1; j < dayBlocks.length; j++) {
          expect(dayBlocks[i].overlaps(dayBlocks[j].start, dayBlocks[j].end), isFalse,
              reason: '${dayBlocks[i]} / ${dayBlocks[j]}');
        }
      }
    });

    test('집중 작업은 집중 시간대(09~12시)에 먼저 넣는다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [TaskItem(id: 't1', title: '기획서', estMinutes: 50, dueAt: at(23, 0), focus: true)],
      ));
      final chunk = plan.blocks.firstWhere((b) => b.taskId == 't1');
      expect(chunk.start, at(9, 0));
    });

    test('빈 시간의 75%를 넘기면 다음 날로 넘긴다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [TaskItem(id: 't1', title: '큰 과제', estMinutes: 900, dueAt: at(23, 0, day: 20))],
      ));
      expect(plan.taskMinutes, lessThanOrEqualTo((plan.freeMinutes * 0.75).floor()));
      expect(plan.deferred.single.reason, DeferReason.budget);
      expect(plan.deferred.single.minutes, 900 - plan.taskMinutes);
    });

    test('마감 전에 들어갈 자리가 없으면 다음 날로 넘긴다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [TaskItem(id: 't1', title: '아침 보고', estMinutes: 50, dueAt: at(7, 30))],
      ));
      expect(plan.deferred.single.reason, DeferReason.noSlot);
    });

    test('마감이 빠른 할 일을 먼저 넣는다', () {
      final plan = builder.buildTomorrow(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [
          TaskItem(id: 'late', title: '나중 마감', estMinutes: 50, dueAt: at(23, 0, day: 18)),
          TaskItem(id: 'soon', title: '오늘 마감', estMinutes: 50, dueAt: at(17, 0)),
        ],
      ));
      final soon = plan.blocks.firstWhere((b) => b.taskId == 'soon');
      final late = plan.blocks.firstWhere((b) => b.taskId == 'late');
      expect(soon.start.isBefore(late.start), isTrue);
    });
  });

  group('웹 버전과 맞춘 규칙', () {
    test('코칭으로 앞당긴 취침 시간을 반영한다', () {
      final plan = builder.buildDay(DayPlanInput(date: at(0, 0), goals: goals, settings: const PersonalSettings(bedEarlierMinutes: 15)));
      expect(plan.bedTonight, at(23, 30, day: 13));
    });

    test('사용자가 끌어서 정한 순서가 마감보다 먼저다', () {
      final plan = builder.buildDay(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        tasks: [
          TaskItem(id: 'soon', title: '마감 빠름', estMinutes: 50, dueAt: at(23, 0, day: 18), rank: 1),
          TaskItem(id: 'top', title: '내가 맨 위에 둔 일', estMinutes: 50, dueAt: at(23, 0, day: 25), rank: 0),
        ],
      ));
      final top = plan.blocks.firstWhere((b) => b.taskId == 'top');
      final soon = plan.blocks.firstWhere((b) => b.taskId == 'soon');
      expect(top.start.isBefore(soon.start), isTrue);
    });

    test('하루 중간에 다시 짜면 지금 이후에만 할 일을 넣는다', () {
      final plan = builder.buildDay(DayPlanInput(
        date: at(0, 0),
        goals: goals,
        notBefore: at(14, 0),
        tasks: [TaskItem(id: 't1', title: '정리', estMinutes: 50, dueAt: at(23, 0), focus: true)],
      ));
      expect(plan.blocks.firstWhere((b) => b.taskId == 't1').start.isBefore(at(14, 0)), isFalse);
    });

    test('일정은 JSON으로 저장했다가 그대로 되살린다', () {
      final plan = builder.buildDay(DayPlanInput(date: at(0, 0), goals: goals, tasks: [TaskItem(id: 't1', title: '정리', estMinutes: 120, dueAt: at(23, 0))]));
      final back = DayPlan.fromJson(plan.toJson());
      expect(back.blocks.length, plan.blocks.length);
      expect(back.wake, plan.wake);
      expect(back.blocks.last.start, plan.blocks.last.start);
      expect(back.alarms.first.reason, plan.alarms.first.reason);
    });
  });

  group('추정 기록', () {
    test('블록 시작 10분 뒤까지 기록이 없으면 추정 기록을 만든다', () {
      final plan = builder.buildTomorrow(DayPlanInput(date: at(0, 0), goals: goals));
      final est = estimateMissing(blocks: plan.blocks, logs: const [], now: at(7, 45));
      expect(est.any((l) => l.activity == Activity.meal && l.start == at(7, 30)), isTrue);
      expect(est.every((l) => l.isEstimate), isTrue);
    });
  });
}
