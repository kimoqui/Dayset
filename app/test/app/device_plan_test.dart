// 휴대폰에 맡길 알림·알람 목록(앱 전용). 앱이 꺼져 있어도 울리게 기기에 예약할 것을 상태에서 계산한다.

import 'package:dayset/app/derive.dart';
import 'package:dayset/app/device_plan.dart';
import 'package:dayset/app/now_check.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

void main() {
  late Store store;
  setUp(() {
    store = Store(storage: StateStorage(MemoryStore()));
    store.setFixedClock(at(19, 6, 0));
    store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(), usualWake: 7 * 60);
  });

  group('기상·취침 알람', () {
    test('오늘 기상 전이면 오늘·내일 기상과 오늘 밤 취침을 맡긴다', () {
      final s = store.state;
      final list = deviceAlarms(s, store.now());
      final today = planFor(s, '2026-10-19', store.now()).plan;
      final tomorrow = planFor(s, '2026-10-20', store.now()).plan;
      expect(list.map((a) => a.key).toList(), ['2026-10-19|wake', '2026-10-20|wake', '2026-10-20|bed']);
      expect(list[0].at, today.wake);
      expect(list[2].at, tomorrow.bedTonight);
      expect(list.map((a) => a.id).toSet().length, 3); // 번호가 겹치지 않는다
      expect(list[0].kind, RingKind.wake);
    });

    test('기상을 기록하면 오늘 기상 알람은 거두고, 다시 울림은 그 시각을 따른다', () {
      store.setFixedClock(at(19, 7, 1));
      final ring = store.dueAlarms().ring!;
      store.snooze(ring, 5);
      final snoozed = deviceAlarms(store.state, store.now()).firstWhere((a) => a.key == '2026-10-19|wake');
      expect(snoozed.at, at(19, 7, 6));
      store.setFixedClock(at(19, 7, 6));
      store.dismissWake(store.dueAlarms().ring!);
      expect(deviceAlarms(store.state, store.now()).map((a) => a.key), isNot(contains('2026-10-19|wake')));
    });

    test('처음 설정 전에는 알람을 맡기지 않는다', () {
      expect(deviceAlarms(store.state.copyWith(onboarded: false), store.now()), isEmpty);
    });
  });

  group('일정 시작 알림', () {
    test('알림을 켜야 예약하고, 앞으로 24시간 안의 기록할 일정만', () {
      expect(scheduledNotices(store.state, store.now()), isEmpty);
      store.setNotify((n) => n.copyWith(enabled: true));
      final list = scheduledNotices(store.state, store.now());
      expect(list, isNotEmpty);
      for (final n in list) {
        expect(n.at.isAfter(store.now()), isTrue);
        expect(n.at.isBefore(store.now().add(const Duration(hours: 24))), isTrue);
        expect(n.notice.activity, isNotNull);
        expect(n.notice.blockStart, n.at);
      }
      expect(list.map((n) => n.id).toSet().length, list.length);
      // '일정 시작하면 알리기'를 끄면 예약하지 않는다
      store.setNotify((n) => n.copyWith(remind: false));
      expect(scheduledNotices(store.state, store.now()), isEmpty);
    });

    test("'지금은 안 해요'로 넘긴 조각은 예약하지 않는다", () {
      store.setNotify((n) => n.copyWith(enabled: true));
      final first = scheduledNotices(store.state, store.now()).first;
      store.skipCheck(first.notice.skipId!);
      expect(scheduledNotices(store.state, store.now()).map((n) => n.notice.skipId), isNot(contains(first.notice.skipId)));
    });
  });

  test('지금 일정 알림 문구는 웹과 같다', () {
    final b = ScheduleBlock(id: 'b1', kind: BlockKind.habit, title: '점심 식사', start: at(19, 12), end: at(19, 13), activity: Activity.meal);
    final due = nowNotice(NowCheck(kind: CheckKind.due, block: b, expected: Activity.meal, current: Activity.work, minutes: 20))!;
    expect(due.title, '12:00 점심 식사 시간이에요');
    expect(due.body, "지금 기록은 업무예요. 식사를 시작했으면 '기록하기'를 눌러 주세요");
    expect(due.activity, Activity.meal);
    expect(due.blockStart, at(19, 12));
    final ok = nowNotice(NowCheck(kind: CheckKind.ok, block: b, current: Activity.meal))!;
    expect(ok.title, '지금 점심 식사 · 12:00–13:00');
    expect(ok.activity, isNull);
    expect(nowNotice(const NowCheck(kind: CheckKind.none)), isNull);
  });
}
