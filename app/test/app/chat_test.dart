import 'package:dayset/app/chat_command.dart';
import 'package:dayset/app/derive.dart';
import 'package:dayset/app/edits.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 웹 src/app/__tests__/chat.test.ts를 옮긴 것.
void main() {
  final now = DateTime(2026, 11, 2, 9, 0); // 월요일 오전 9시
  final s = demoState(now);
  final today = dateKey(now);
  final tomorrow = dateKey(addDays(now, 1));

  HabitChange habit(ScheduleEdit e) => e as HabitChange;

  group('채팅으로 일정 바꾸기(규칙)', () {
    test('내일 운동 시각 옮기기', () {
      final r = interpretChat('내일 운동 7시로 옮겨줘', s, now);
      expect(r.edits, hasLength(1));
      final e = habit(r.edits.single);
      expect((e.day, e.title, e.patch, e.scope), (tomorrow, '운동', const HabitEdit(start: 19 * 60), EditScope.day));
    });

    test('오늘 점심 30분 늦추기(지금 값 기준)', () {
      final r = interpretChat('오늘 점심 30분 늦춰', s, now);
      expect(r.edits, hasLength(1));
      final e = habit(r.edits.single);
      expect((e.day, e.title, e.patch, e.scope), (today, '점심 식사', const HabitEdit(start: 12 * 60 + 30), EditScope.day));
    });

    test('빼기·매일·길이', () {
      final a = habit(interpretChat('오늘 운동 빼줘', s, now).edits.first);
      expect((a.title, a.patch.skip, a.scope), ('운동', true, EditScope.day));
      final b = habit(interpretChat('매일 저녁 식사 7시로 바꿔', s, now).edits.first);
      expect((b.title, b.patch.start, b.scope), ('저녁 식사', 19 * 60, EditScope.every));
      final c = habit(interpretChat('오늘 운동 20분으로 줄여', s, now).edits.first);
      expect(c.patch.minutes, 20);
    });

    test('지난 습관은 날짜 말이 없으면 내일로 본다', () {
      final e = habit(interpretChat('아침 식사 8시로', s, now).edits.first); // 아침 식사(7:30~8:00)는 이미 지남
      expect((e.day, e.title, e.patch.start), (tomorrow, '아침 식사', 8 * 60));
    });

    test('기상 알람', () {
      final a = interpretChat('내일 6시 반에 깨워줘', s, now).edits.first as WakeChange;
      expect((a.day, a.minutes, a.scope), (tomorrow, 390, EditScope.day));
      final b = interpretChat('앞으로 매일 6시에 일어날래', s, now).edits.first as WakeChange;
      expect((b.minutes, b.scope), (360, EditScope.every));
    });

    test('새 캘린더 일정·옮기기·지우기', () {
      final add = interpretChat('금요일 3시 치과 1시간 추가', s, now).edits.first as EventAdd;
      expect(add.title, '치과');
      expect(formatHm(add.start), '15:00');
      expect(formatHm(add.end), '16:00');
      // 예시 데이터: 내일 9시 팀 회의
      final mv = interpretChat('팀 회의 11시로 옮겨줘', s, now).edits.first as EventMove;
      expect(mv.id, 'ev-2');
      expect(formatHm(mv.start), '11:00');
      final del = interpretChat('팀 회의 취소', s, now).edits.first as EventDelete;
      expect(del.id, 'ev-2');
    });

    test('할 일 넣기', () {
      final e = interpretChat('할 일 보고서 2시간 추가', s, now).edits.first as TaskAdd;
      expect((e.title, e.minutes, e.type), ('보고서', 120, TaskType.work));
    });

    test('여러 개를 한 번에, 읽지 못한 건 알려 준다', () {
      final r = interpretChat('내일 6시에 깨워줘, 내일 운동 빼줘, 물 많이 마시기', s, now);
      expect(r.edits.map((e) => e.kind).toList(), ['wake', 'habit']);
      expect(r.unknown, ['물 많이 마시기']);
      expect(interpretChat('안녕', s, now).reply, contains('이렇게 말해 주세요'));
    });

    test('예시는 모두 무언가를 바꾼다', () {
      for (final e in chatExamples) {
        expect(interpretChat(e, s, now).edits, isNotEmpty, reason: e);
      }
    });
  });

  group('일정 바꾸기 적용·미리보기', () {
    test('그날만 바꾼 습관은 그날 일정에만, 매일은 목표에', () {
      // 저녁 식사(18:30~19:30)와 겹치지 않는 21:00으로 옮긴다.
      final day = applyEdit(s, HabitChange(day: tomorrow, title: '운동', patch: const HabitEdit(start: 21 * 60, minutes: 45), scope: EditScope.day), now);
      final ex = planFor(day, tomorrow, now).blocks.firstWhere((b) => b.activity == Activity.exercise);
      expect(formatHm(ex.start), '21:00');
      expect(diffMin(ex.end, ex.start), 45);
      expect(day.goals.exercise?.start, s.goals.exercise?.start);
      final every = applyEdit(s, HabitChange(day: tomorrow, title: '운동', patch: const HabitEdit(start: 19 * 60), scope: EditScope.every), now);
      expect(every.goals.exercise?.start.minutes, 19 * 60);
    });

    test('빼기·기상·되돌리기', () {
      final skip = applyEdit(s, HabitChange(day: tomorrow, title: '운동', patch: const HabitEdit(skip: true), scope: EditScope.day), now);
      expect(planFor(skip, tomorrow, now).blocks.any((b) => b.activity == Activity.exercise), false);
      final wake = applyEdit(s, WakeChange(day: tomorrow, minutes: 390, scope: EditScope.day), now);
      expect(formatHm(planFor(wake, tomorrow, now).plan.wake), '06:30');
      final back = applyEdit(wake, ResetDay(day: tomorrow), now);
      expect(planFor(back, tomorrow, now).plan.wake, planFor(s, tomorrow, now).plan.wake);
    });

    test('미리보기는 바뀌는 것만 문장으로', () {
      final p = previewEdits(s, [HabitChange(day: tomorrow, title: '운동', patch: const HabitEdit(start: 21 * 60), scope: EditScope.day)], now);
      expect(p, hasLength(1));
      expect(p.first.label, '내일');
      expect(p.first.diffs.any((d) => d.startsWith('운동') && d.contains('21:00')), true);
      expect(describeEdit(s, WakeChange(day: tomorrow, minutes: 390, scope: EditScope.day), now), '내일 기상 알람: 06:30');
    });
  });

  group('그날만 바꾼 값 저장', () {
    test('DayOverride JSON은 웹과 같은 모양으로 오간다', () {
      const o = DayOverride(dinnerShift: 30, wake: 390, habits: {'운동': HabitEdit(start: 1260, minutes: 45), '점심 식사': HabitEdit(skip: true)});
      final j = o.toJson();
      expect(j, {
        'dinnerShift': 30,
        'wake': 390,
        'habits': {
          '운동': {'start': 1260, 'minutes': 45},
          '점심 식사': {'skip': true},
        },
      });
      final back = DayOverride.fromJson(j);
      expect((back.dinnerShift, back.wake), (30, 390));
      expect(back.habits, o.habits);
      expect(const DayOverride().toJson(), isEmpty);
    });

    test('Store.applyEdits는 적용하고 남은 일정을 다시 짜며 되돌릴 수 있다', () {
      final store = Store(storage: StateStorage(MemoryStore()))
        ..setFixedClock(now)
        ..replaceState(s);
      store.applyEdits([WakeChange(day: tomorrow, minutes: 390, scope: EditScope.day)]);
      expect(store.state.overrides[tomorrow]?.wake, 390);
      expect(store.state.metrics.events.last.k, 'schedule_edit');
      expect(store.canUndoPlan(), true);
      store.undoPlanChange();
      expect(store.state.overrides[tomorrow]?.wake, isNull);
    });
  });
}
