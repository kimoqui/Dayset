import 'package:dayset/core/model/models.dart';
import 'package:dayset/platform/widget_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS(UTC)·안드로이드(오프셋) 시각 형식을 모두 읽는다', () {
    final events = parsePendingEvents(
      '[{"activity":"work","at":"2026-10-14T00:40:00Z"},'
      '{"activity":"meal","at":"2026-10-14T12:05:00.000+09:00"}]',
    );
    expect(events, hasLength(2));
    expect(events[0].activity, Activity.work);
    expect(events[0].at.toUtc(), DateTime.utc(2026, 10, 14, 0, 40));
    expect(events[1].at.toUtc(), DateTime.utc(2026, 10, 14, 3, 5));
  });

  test('깨진 데이터와 모르는 상태는 건너뛴다', () {
    expect(parsePendingEvents(null), isEmpty);
    expect(parsePendingEvents('not json'), isEmpty);
    expect(parsePendingEvents('{"a":1}'), isEmpty);
    final events = parsePendingEvents(
      '[{"activity":"dance","at":"2026-10-14T00:40:00Z"},'
      '{"activity":"rest"},'
      '{"activity":"rest","at":"2026-10-14T01:00:00Z"}]',
    );
    expect(events.single.activity, Activity.rest);
  });
}
