// 기록을 이어 가게 하는 장치: 저녁 확인 '남은 건 일정대로 했어요', 오늘 진행도.
// 웹 src/app/__tests__/habitLoop.test.ts와 같은 기대값.

import 'package:dayset/app/derive.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 19, h, m);
const day = '2026-10-19';

void main() {
  late Store store;
  setUp(() {
    store = Store(storage: StateStorage(MemoryStore()));
    store.setFixedClock(at(6, 0));
    store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(), usualWake: 7 * 60);
  });

  test('저녁에 기록 없는 일정은 한 번에 일정대로 채우고, 다르게 한 것만 남긴다', () {
    store.setFixedClock(at(21, 0));
    final before = eveningAsk(store.state, day, store.now());
    expect(before.open.length, greaterThan(1));
    final first = before.open.first;
    store.markMissed(day, first, MissReason.conflict);
    final n = store.markRestAsPlanned(day);
    expect(n, before.open.length - 1);
    expect(eveningAsk(store.state, day, store.now()).open, isEmpty);
    expect(store.state.misses.any((m) => m.blockId == first.id), isTrue);
    final v = evaluate(store.state, day, store.now());
    expect(v.achieved, v.total - 1);
    expect(store.markRestAsPlanned(day), 0);
  });

  test('오늘 진행도는 저녁 확인 머리와 같은 숫자', () {
    store.setFixedClock(at(12, 5));
    store.tap(Activity.meal);
    final p = todayProgress(store.state, store.now());
    final v = evaluate(store.state, day, store.now());
    expect((p.achieved, p.total), (v.achieved, v.total));
    expect(p.achieved, greaterThanOrEqualTo(1));
  });
}
