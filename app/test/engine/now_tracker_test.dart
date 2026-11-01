import 'package:dayset/core/engine/now_tracker.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, int m, [int s = 0]) => DateTime(2026, 10, 14, h, m, s);

void main() {
  late NowTracker t;
  var n = 0;
  setUp(() => t = NowTracker(idGenerator: () => 'id${n++}'));

  test('누르면 이전 기록을 끝내고 새 기록을 시작한다', () {
    t.tap(Activity.work, at(9, 0));
    final r = t.tap(Activity.meal, at(12, 0));
    expect(r.changed, isTrue);
    expect(r.ended!.activity, Activity.work);
    expect(r.ended!.end, at(12, 0));
    expect(t.current!.activity, Activity.meal);
    expect(t.logs, hasLength(2));
  });

  test('같은 상태를 다시 누르면 아무것도 바뀌지 않는다', () {
    t.tap(Activity.work, at(9, 0));
    final r = t.tap(Activity.work, at(9, 30));
    expect(r.changed, isFalse);
    expect(t.logs, hasLength(1));
  });

  test('5초 안에는 되돌릴 수 있다', () {
    t.tap(Activity.work, at(9, 0));
    t.tap(Activity.rest, at(10, 0));
    expect(t.undo(at(10, 0, 4)), isTrue);
    expect(t.current!.activity, Activity.work);
    expect(t.current!.isOpen, isTrue);
    expect(t.logs, hasLength(1));
  });

  test('5초가 지나면 되돌릴 수 없다', () {
    t.tap(Activity.work, at(9, 0));
    t.tap(Activity.rest, at(10, 0));
    expect(t.undo(at(10, 0, 6)), isFalse);
    expect(t.current!.activity, Activity.rest);
  });

  test('10분 안에 원래 상태로 돌아오면 하나로 합친다', () {
    t.tap(Activity.work, at(9, 0));
    t.tap(Activity.rest, at(10, 0));
    final r = t.tap(Activity.work, at(10, 5));
    expect(r.merged, isTrue);
    expect(t.logs, hasLength(1));
    expect(t.current!.start, at(9, 0));
    expect(t.current!.isOpen, isTrue);
  });

  test('중간 상태가 10분 이상이면 합치지 않는다', () {
    t.tap(Activity.work, at(9, 0));
    t.tap(Activity.rest, at(10, 0));
    final r = t.tap(Activity.work, at(10, 15));
    expect(r.merged, isFalse);
    expect(t.logs, hasLength(3));
  });

  test('위젯에서 쌓인 탭을 시간순으로 반영한다', () {
    t.applyExternal([
      (activity: Activity.meal, at: at(12, 0)),
      (activity: Activity.work, at: at(9, 0)),
    ]);
    expect(t.logs.first.activity, Activity.work);
    expect(t.logs.first.end, at(12, 0));
    expect(t.current!.activity, Activity.meal);
    expect(t.current!.source, LogSource.widget);
    expect(t.canUndo(at(12, 0, 1)), isFalse);
  });

  test('stop은 현재 기록만 끝낸다', () {
    t.tap(Activity.exercise, at(20, 30));
    final ended = t.stop(at(20, 50));
    expect(ended!.minutesUntil(at(21, 0)), 20);
    expect(t.current, isNull);
  });
}
