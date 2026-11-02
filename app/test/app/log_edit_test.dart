// 기록 시각 고치기(제때 누르지 못한 기록). 웹 src/app/__tests__/logEdit.test.ts와 같은 기대값.

import 'package:dayset/app/log_edit.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 2, h, m);

void main() {
  final now = at(12, 0);
  List<ActivityLog> logs() => [
        ActivityLog(id: 'a', activity: Activity.meal, start: at(7, 30), end: at(8, 0)),
        ActivityLog(id: 'b', activity: Activity.work, start: at(8, 0), end: at(10, 0)),
        ActivityLog(id: 'c', activity: Activity.rest, start: at(10, 0)),
      ];
  String span(ActivityLog l) => '${l.id} ${l.start.hour}:${l.start.minute}-${l.end == null ? 'now' : '${l.end!.hour}:${l.end!.minute}'}';

  group('기록 시각 고치기', () {
    test('시작을 앞당기면 앞 기록이 그 시각에 끝난다', () {
      final r = retimeLogs(logs(), 'b', at(7, 45), at(10, 0), now);
      expect(r.logs!.map(span).toList(), ['a 7:30-7:45', 'b 7:45-10:0', 'c 10:0-now']);
      expect(r.logs![1].confirmed, isTrue);
    });

    test('진행 중인 기록의 시작을 앞당기면 앞 기록 끝도 맞춘다', () {
      final r = retimeLogs(logs(), 'c', at(9, 30), null, now);
      expect(r.logs!.map(span).toList(), ['a 7:30-8:0', 'b 8:0-9:30', 'c 9:30-now']);
    });

    test('끝을 늦추면 뒤 기록이 그 시각부터 시작한다', () {
      final r = retimeLogs(logs(), 'a', at(7, 30), at(8, 20), now);
      expect(r.logs!.map(span).toList(), ['a 7:30-8:20', 'b 8:20-10:0', 'c 10:0-now']);
    });

    test('다른 기록을 통째로 덮거나 한가운데로 들어가면 바꾸지 않는다', () {
      expect(retimeLogs(logs(), 'b', at(7, 0), at(10, 0), now).error, '식사 기록(07:30–08:00)을 통째로 덮어요. 그 기록을 먼저 지워 주세요');
      expect(retimeLogs(logs(), 'a', at(8, 30), at(9, 0), now).error, '업무 기록(08:00–10:00) 한가운데예요. 그 기록을 먼저 고쳐 주세요');
      expect(retimeLogs(logs(), 'b', at(8, 0), at(10, 30), now).error, '지금 기록 중인 휴식을 덮어요. 끝 시각을 더 이르게 해 주세요');
    });

    test('지금보다 늦거나 거꾸로 된 시각은 받지 않는다', () {
      expect(retimeLogs(logs(), 'b', at(8, 0), at(12, 30), now).error, '끝 시각이 지금보다 늦어요');
      expect(retimeLogs(logs(), 'b', at(9, 0), at(9, 0), now).error, '끝 시각은 시작보다 1분 이상 뒤여야 해요');
      expect(retimeLogs(logs(), 'c', at(12, 10), null, now).error, '시작 시각이 지금보다 늦어요');
      expect(retimeLogs(logs(), 'b', at(8, 0), null, now).error, '끝난 기록은 끝 시각이 필요해요');
    });
  });

  group('늦게 누른 기록(Store.tapAt)', () {
    late Store store;
    setUp(() {
      store = Store(storage: StateStorage(MemoryStore()));
      store.setFixedClock(at(6, 0));
      store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(), usualWake: 7 * 60);
    });
    List<ActivityLog> real() => store.state.logs.where((l) => l.source != LogSource.estimate).toList();
    String sp(ActivityLog l) => '${l.activity.name} ${l.start.hour}:${l.start.minute}-${l.end == null ? 'now' : '${l.end!.hour}:${l.end!.minute}'}';

    test('일정 시각부터 한 것으로 기록하고 앞 기록은 그 시각에 끝난다', () {
      store.setFixedClock(at(8, 0));
      store.tap(Activity.meal);
      store.setFixedClock(at(9, 40));
      final r = store.tapAt(Activity.work, at(9, 0));
      expect(r.changed, isTrue);
      expect(r.error, isNull);
      expect(real().map(sp).toList(), ['meal 8:0-9:0', 'work 9:0-now']);
      store.setFixedClock(at(10, 0));
      store.tap(Activity.rest);
      expect(real().map((l) => l.activity.name).toList(), ['meal', 'work', 'rest']);
    });

    test('앞 기록보다 이른 시각이면 지금부터로 두고 이유를 알려 준다', () {
      store.setFixedClock(at(9, 10));
      store.tap(Activity.meal);
      store.setFixedClock(at(9, 40));
      final r = store.tapAt(Activity.work, at(9, 0));
      expect(r.error, '식사 기록(09:10–09:40)을 통째로 덮어요. 그 기록을 먼저 지워 주세요');
      expect(store.state.logs.last.activity, Activity.work);
      expect(store.state.logs.last.start, at(9, 40));
    });

    test('기록 시각을 고친다', () {
      store.setFixedClock(at(8, 0));
      store.tap(Activity.meal);
      store.setFixedClock(at(8, 30));
      store.tap(Activity.work);
      final meal = store.state.logs.firstWhere((l) => l.activity == Activity.meal);
      expect(store.retimeLog(meal.id, at(7, 40), at(8, 10)), isNull);
      expect(real().map((l) => "${l.activity.name} ${l.start.hour}:${l.start.minute}").toList(), ['meal 7:40', 'work 8:30']);
    });
  });
}
