// 웹 버전과 같은 데이터·같은 결과인지 확인한다.
// fixtures/web_demo_state.json: 웹 버전 demoState(2026-10-21 14:00, 한국 시간)를 serialize한 백업.
// fixtures/web_demo_expected.json: 같은 상태로 웹 버전이 계산한 값(연속 기록·통계·내일 일정·지표).
// 날짜 키가 기기 시간대에 따라 달라지므로 한국 시간(+9)이 아닌 기기에서는 건너뛴다.

import 'dart:convert';
import 'dart:io';

import 'package:dayset/app/derive.dart';
import 'package:dayset/app/duration.dart';
import 'package:dayset/app/metrics.dart';
import 'package:dayset/app/now_check.dart';
import 'package:dayset/app/priority_model.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/app/streak.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

String _fixture(String name) => File('test/app/fixtures/$name').readAsStringSync();

/// 두 JSON 값의 다른 곳을 경로로 모은다.
List<String> jsonDiff(Object? a, Object? b, [String path = r'$']) {
  if (a is Map && b is Map) {
    return [
      for (final k in {...a.keys, ...b.keys})
        if (!a.containsKey(k))
          '$path.$k: 앱에 없음 (웹 ${jsonEncode(b[k])})'
        else if (!b.containsKey(k))
          '$path.$k: 웹에 없음 (앱 ${jsonEncode(a[k])})'
        else
          ...jsonDiff(a[k], b[k], '$path.$k'),
    ];
  }
  if (a is List && b is List) {
    if (a.length != b.length) return ['$path: 길이 ${a.length} ≠ ${b.length}'];
    return [for (var i = 0; i < a.length; i++) ...jsonDiff(a[i], b[i], '$path[$i]')];
  }
  if (a is num && b is num) return a == b ? const [] : ['$path: $a ≠ $b'];
  return a == b ? const [] : ['$path: ${jsonEncode(a)} ≠ ${jsonEncode(b)}'];
}

/// 웹의 JSON.stringify는 값이 undefined인 키를 빼고, 앱은 기본값(false·빈 목록)을 빼기도 한다.
/// 의미가 같은 차이(없음 = null = false = 빈 값)는 맞춘 뒤 비교한다.
Object? normalize(Object? v) {
  if (v is Map) {
    final out = <String, Object?>{};
    for (final e in v.entries) {
      final x = normalize(e.value);
      if (x == null || x == false || (x is List && x.isEmpty) || (x is Map && x.isEmpty)) continue;
      out[e.key as String] = x;
    }
    return out;
  }
  if (v is List) return [for (final x in v) normalize(x)];
  return v;
}

void main() {
  final kst = DateTime(2026, 10, 21).timeZoneOffset == const Duration(hours: 9);
  if (!kst) {
    // ignore: avoid_print
    print('web_compat_test: 한국 시간대가 아니라 건너뛴다 (TZ=Asia/Seoul로 실행).');
    return;
  }

  final expected = jsonDecode(_fixture('web_demo_expected.json')) as Map<String, Object?>;
  final webText = _fixture('web_demo_state.json');
  final now = DateTime.parse(expected['now'] as String).toLocal();

  group('웹 백업 불러오기', () {
    test('웹 백업을 읽고 다시 저장하면 같은 JSON이다', () {
      final s = deserialize(webText);
      final diffs = jsonDiff(normalize(jsonDecode(serialize(s))), normalize(jsonDecode(webText)));
      expect(diffs, isEmpty, reason: diffs.take(20).join('\n'));
    });

    test('같은 시각의 예시 데이터를 웹과 똑같이 만든다', () {
      final mine = demoState(now);
      final web = deserialize(webText);
      final s = mine.copyWith(profile: web.profile);
      final diffs = jsonDiff(normalize(jsonDecode(serialize(s))), normalize(jsonDecode(webText)));
      expect(diffs, isEmpty, reason: diffs.take(20).join('\n'));
    });

    test('연속 기록·통계가 웹과 같다', () {
      final s = deserialize(webText);
      final st = computeStreak(s, now);
      final e = expected['streak'] as Map;
      expect(st.current, e['current']);
      expect(st.best, e['best']);
      expect(st.weekSetDays, e['weekSetDays']);
      expect(st.monthSetDays, e['monthSetDays']);
      expect(st.todayDone, e['todayDone']);
      expect([for (final d in st.week) d.mark.name], e['week']);

      final week = periodStats(s, weekKeys(now, -1), now);
      final w = expected['lastWeek'] as Map;
      expect(week.setDays, w['setDays']);
      final rates = {
        for (final r in week.rates.entries)
          r.key.task ? 'task' : r.key.activity!.name: {'achieved': r.value.achieved, 'counted': r.value.counted, 'estimated': r.value.estimated},
      };
      expect(jsonDiff(rates, w['rates']), isEmpty);
    });

    test('날마다 셋 데이 판정이 웹과 같다', () {
      final s = deserialize(webText);
      final days = expected['days'] as Map;
      final diffs = <String>[];
      for (final e in days.entries) {
        final v = evaluate(s, e.key as String, now);
        diffs.addAll(jsonDiff({'hasData': v.hasData, 'isSetDay': v.isSetDay, 'wakeOk': v.wakeOk, 'achieved': v.achieved, 'total': v.total}, e.value, e.key as String));
      }
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    });

    test('내일 일정이 웹과 같다', () {
      final s = deserialize(webText);
      final p = planFor(s, dateKey(addDays(now, 1)), now);
      final e = expected['tomorrow'] as Map;
      expect(encodeDate(p.wake), e['wake']);
      expect(encodeDate(p.bedTonight), e['bed']);
      expect([for (final b in p.blocks) '${b.kind.name}|${b.title}|${encodeDate(b.start)}|${encodeDate(b.end)}'], e['blocks']);
    });

    test('일정 체크·보정 시간·추천 순서가 웹과 같다', () {
      final s = deserialize(webText);
      final c = nowCheck(s, now);
      final e = expected['check'] as Map;
      expect(c.kind.name, e['kind']);
      expect(c.block?.title, e['block']);
      expect(c.expected?.name, e['expected']);
      final planned = expected['planned'] as Map;
      for (final t in s.tasks) {
        expect(plannedMinutes(t, s.durations), planned[t.id]);
      }
      final prefs = learnPrefs(s.learning);
      final sug = prefs == null ? null : suggestOrder(s.tasks.where((t) => !t.done).toList(), prefs, now);
      final es = expected['suggestion'] as Map?;
      expect(sug?.order, es?['order']);
      expect(sug?.reasons, es?['reasons']);
    });

    test('베타 지표가 웹과 같다', () {
      final s = deserialize(webText);
      final m = computeMetrics(s, now);
      final e = expected['metrics'] as Map;
      expect(m['anonId'], e['anonId']);
      for (final k in ['retention', 'habit', 'usage', 'calibration', 'activation']) {
        final d = jsonDiff(normalize(jsonDecode(jsonEncode(m[k]))), normalize(e[k]), k);
        expect(d, isEmpty, reason: d.join('\n'));
      }
    });

    test('스토어로 불러오면 지금 데이터를 따로 보관한다', () {
      final kv = MemoryStore();
      final store = Store(storage: StateStorage(kv));
      store.setFixedClock(now);
      store.setProfileName('앱');
      store.importBackup(webText);
      expect(store.state.demo, isTrue);
      expect(store.state.profile.id, 'u-fixture1');
      final kept = store.storage.keptBackups();
      expect(kept.length, 1);
      expect(kept.first.reason, KeptReason.beforeImport);
      expect(deserialize(kv.read(kept.first.key)!).profile.name, '앱');
    });

    test('깨진 백업은 지금 데이터를 바꾸지 않는다', () {
      final store = Store(storage: StateStorage(MemoryStore()));
      store.setFixedClock(now);
      store.setProfileName('앱');
      expect(() => store.importBackup('{"version": 2}'), throwsA);
      expect(() => store.importBackup('not json'), throwsA);
      expect(store.state.profile.name, '앱');
    });
  });
}
