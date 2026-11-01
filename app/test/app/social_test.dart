// 연속 셋 데이·친구 코드·순위. 웹 __tests__/social.test.ts를 옮기고, 웹과 같은 코드를 만드는지 확인한다.

import 'package:dayset/app/nearby.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/social.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/app/streak.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

const info = StreakInfo(current: 5, best: 9, todayDone: true, week: [], weekSetDays: 3, monthSetDays: 7, nextMilestone: 2);

void main() {
  group('연속 셋 데이', () {
    test('예시 데이터: 연속 기록은 최고 기록을 넘지 않고, 이번 주 7칸을 돌려준다', () {
      final now = at(19, 22, 0);
      final i = computeStreak(demoState(now), now);
      expect(i.week, hasLength(7));
      expect(i.best, greaterThanOrEqualTo(i.current));
      expect(i.best, greaterThan(0));
    });

    test('매일 셋 데이를 채우면 하루씩 늘고, 쉬는 날은 끊지 않는다', () {
      final store = Store(storage: StateStorage(MemoryStore()));
      store.setFixedClock(at(12, 6, 0));
      store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(travelMinutes: 0), usualWake: 7 * 60);
      void perfectDay(int d) {
        store.setFixedClock(at(d, 7, 2));
        store.ensureDay(store.now());
        final r = store.dueAlarms(store.now()).ring;
        if (r != null) store.dismissWake(r);
        for (final (h, m, a) in const [
          (7, 32, Activity.meal),
          (8, 10, Activity.work),
          (12, 3, Activity.meal),
          (13, 0, Activity.work),
          (18, 35, Activity.meal),
          (19, 30, Activity.rest),
          (20, 31, Activity.exercise),
          (21, 5, Activity.rest),
          (23, 46, Activity.sleep),
        ]) {
          store.setFixedClock(at(d, h, m));
          store.tap(a);
        }
      }

      perfectDay(13);
      perfectDay(14);
      store.setFixedClock(at(15, 9, 0));
      store.ensureDay(store.now());
      store.setRestDay('2026-10-15', true); // 쉬는 날
      perfectDay(16);
      store.setFixedClock(at(16, 23, 50));
      final i = computeStreak(store.state, store.now());
      expect(i.current, 3); // 13·14·16 (15일은 쉬는 날이라 끊기지 않음)
      expect(i.todayDone, isTrue);
      expect(reachedMilestone(i, '2026-10-16', null), 3);
      expect(reachedMilestone(i, '2026-10-16', '3@2026-10-16'), isNull);
    });
  });

  group('친구 코드와 순위', () {
    test('코드를 만들고 메시지 전체에서 다시 읽는다(한글 이름 포함)', () {
      final code = makeFriendCode(id: 'u-abc', name: '대희', info: info, now: at(19, 21));
      final f = readFriendCode('같이 겨뤄요!\n$code\n')!;
      expect([f.id, f.name, f.streak, f.best, f.weekSetDays, f.week], ['u-abc', '대희', 5, 9, 3, '2026-10-19']);
      expect(readFriendCode('아무 글'), isNull);
      expect(readFriendCode('DS1-망가진코드입니다아아아아'), isNull);
    });

    test('이번 주 셋 데이 → 연속 기록 순으로 정렬하고, 지난주 코드는 0일로 본다', () {
      final now = at(21, 12);
      final rows = leaderboard(id: 'me', name: '나', info: info, now: now, friends: [
        Friend(id: 'a', name: '지민', streak: 12, best: 20, week: '2026-10-19', weekSetDays: 3, monthSetDays: 10, updatedAt: now),
        Friend(id: 'b', name: '현우', streak: 2, best: 4, week: '2026-10-19', weekSetDays: 4, monthSetDays: 4, updatedAt: now),
        Friend(id: 'c', name: '서연', streak: 9, best: 9, week: '2026-10-12', weekSetDays: 7, monthSetDays: 9, updatedAt: now),
      ]);
      expect(rows.map((r) => r.name).toList(), ['현우', '지민', '나', '서연']);
      expect([rows[3].stale, rows[3].weekSetDays], [true, 0]);
    });
  });

  group('웹 버전과 같은 코드', () {
    // 웹(src/app/social.ts·nearby.ts)이 같은 입력으로 만든 값. 2026-10-19 12:00 UTC(한국 21:00).
    final now = DateTime.utc(2026, 10, 19, 12);
    const webPlain =
        'DS1-eyJpIjoidS1hYmMiLCJuIjoi64yA7Z2sIiwicyI6NSwiYiI6OSwidyI6IjIwMjYtMTAtMTkiLCJkIjozLCJtIjo3LCJ0IjoxNzkyNDExMjAwMDAwfQ';
    const webAnon =
        'DS1-eyJhIjoxLCJjIjoiMzcuMzgsMTI2Ljk0IiwiaSI6InUtbWUiLCJuIjoi6r647KSA7ZWcIOuLpOuejOylkCAjMTM1IiwicyI6NSwiYiI6OSwidyI6IjIwMjYtMTAtMTkiLCJkIjozLCJtIjo3LCJ0IjoxNzkyNDExMjAwMDAwfQ';

    test('친구 코드를 웹과 글자 하나까지 같게 만들고, 웹 코드를 읽는다', () {
      expect(makeFriendCode(id: 'u-abc', name: '대희', info: info, now: now.toLocal()), webPlain);
      expect(makeFriendCode(id: 'u-me', name: anonName('u-me'), info: info, now: now.toLocal(), anon: true, cell: '37.38,126.94'), webAnon);
      final f = readFriendCode(webPlain)!;
      expect([f.id, f.name, f.streak, f.best, f.week, f.weekSetDays, f.monthSetDays, f.anon], ['u-abc', '대희', 5, 9, '2026-10-19', 3, 7, false]);
      expect(f.updatedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
      final a = readFriendCode(webAnon)!;
      expect([a.anon, a.cell, a.name], [true, '37.38,126.94', '꾸준한 다람쥐 #135']);
    });

    test('익명 별명이 웹과 같다', () {
      expect(anonName('u-abc'), '부지런한 다람쥐 #260');
      expect(anonName('u-me'), '꾸준한 다람쥐 #135');
      expect(anonName('u-x7k2p9qa'), '용감한 고래 #564');
      expect(anonName('demo-n1'), '반짝이는 고양이 #242');
    });
  });
}
