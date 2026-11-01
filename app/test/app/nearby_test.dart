// 근처 익명 겨루기. 웹 __tests__/nearby.test.ts를 옮겼다.

import 'package:dayset/app/nearby.dart';
import 'package:dayset/app/social.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/streak.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 21, 12, 0);
const info = StreakInfo(current: 5, best: 9, todayDone: false, week: [], weekSetDays: 3, monthSetDays: 0, nextMilestone: null);

void main() {
  group('근처 익명 겨루기', () {
    test('익명 별명은 기기마다 고정되고 실명과 무관하다', () {
      expect(anonName('u-abc'), anonName('u-abc'));
      expect(RegExp(r'^\S+ \S+ #\d{3}$').hasMatch(anonName('u-abc')), isTrue);
    });

    test('위치는 약 2km 칸으로만 남는다', () {
      expect(cellOf(37.3851, 126.9512), '37.38,126.94');
      expect(cellOf(37.3899, 126.9599), '37.38,126.94');
      expect(distanceBand('37.38,126.94', '37.38,126.94'), '2km 안');
      expect(distanceBand('37.38,126.94', '37.38,126.96'), '4km 안');
      expect(distanceBand('37.38,126.94', '37.50,126.94'), '멀리');
      expect(distanceBand(null, '37.38,126.94'), isNull);
    });

    test('익명 코드는 이름 대신 별명과 칸만 담는다', () {
      final code = makeFriendCode(id: 'u-me', name: anonName('u-me'), info: info, now: now, anon: true, cell: '37.38,126.94');
      final f = readFriendCode(code)!;
      expect(f.anon, isTrue);
      expect(f.cell, '37.38,126.94');
      expect(f.name, anonName('u-me'));
    });

    test('이번 주 셋 데이 → 연속 일수 순으로 줄 세우고, 지난주 기록은 0으로 본다', () {
      final n = NearbyState(on: true, cell: '37.38,126.94', people: [
        Friend(id: 'a', name: 'A', weekSetDays: 5, streak: 2, best: 2, week: '2026-10-19', updatedAt: now),
        Friend(id: 'b', name: 'B', weekSetDays: 6, streak: 9, best: 9, week: '2026-10-12', updatedAt: now),
        Friend(id: 'c', name: 'C', weekSetDays: 3, streak: 1, best: 1, week: '2026-10-19', updatedAt: now),
      ]);
      final b = nearbyBoard('u-me', info, n, now);
      expect(b.rows.map((r) => r.id).toList(), ['a', 'u-me', 'c', 'b']);
      expect(b.myRank, 2);
      expect(b.topPercent, 50);
    });
  });
}
