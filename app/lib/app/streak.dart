// 연속 셋 데이(스트릭). 웹 버전 src/app/streak.ts와 같은 규칙.
//
// - 오늘은 아직 끝나지 않았으므로, 오늘이 셋 데이가 아니어도 어제까지의 연속은 이어진다.
// - 쉬는 날은 연속을 끊지 않지만 날짜 수에도 세지 않는다.
// - 일정이 없던 날(앱을 쓰기 전, 관찰 기간)에서 멈춘다.

import '../core/model/models.dart';
import 'derive.dart';
import 'state.dart';

const milestones = [3, 7, 14, 30, 50, 100, 200, 365];

enum DayMark { set, rest, miss, today, none, future }

class WeekMark {
  const WeekMark(this.key, this.mark);
  final String key;
  final DayMark mark;
}

class StreakInfo {
  const StreakInfo({
    required this.current,
    required this.best,
    required this.todayDone,
    required this.week,
    required this.weekSetDays,
    required this.monthSetDays,
    required this.nextMilestone,
  });
  final int current;
  final int best;

  /// 오늘 셋 데이를 이미 채웠는지.
  final bool todayDone;

  /// 이번 주 월~일 표시.
  final List<WeekMark> week;
  final int weekSetDays;
  final int monthSetDays;

  /// 다음 기념일까지 남은 날.
  final int? nextMilestone;
}

DayMark _markOf(AppState s, String key, DateTime now) {
  final todayKey = dateKey(now);
  if (key.compareTo(todayKey) > 0) return DayMark.future;
  final v = evaluate(s, key, now);
  if (!v.hasData) return DayMark.none;
  if (v.isSetDay) return DayMark.set;
  if (v.rest) return DayMark.rest;
  return key == todayKey ? DayMark.today : DayMark.miss;
}

StreakInfo computeStreak(AppState s, DateTime now) {
  final todayKey = dateKey(now);
  final cache = <String, DayMark>{};
  DayMark mark(String k) => cache.putIfAbsent(k, () => _markOf(s, k, now));

  // 현재 연속
  final todayMark = mark(todayKey);
  var current = todayMark == DayMark.set ? 1 : 0;
  for (var i = 1; i < 800; i++) {
    final m = mark(dateKey(addDays(now, -i)));
    if (m == DayMark.set) {
      current++;
    } else if (m == DayMark.rest) {
      continue;
    } else {
      break;
    }
  }

  // 최고 기록: 일정이 있는 날만 시간순으로 훑는다.
  final keys = s.plans.keys.where((k) => k.compareTo(todayKey) <= 0).toList()..sort();
  var best = 0;
  var run = 0;
  String? prev;
  for (final k in keys) {
    // 날짜가 비면(일정 없는 날) 연속이 끊긴다.
    if (prev != null && dateKey(addDays(fromKey(prev), 1)) != k) run = 0;
    final m = mark(k);
    if (m == DayMark.set) {
      run++;
    } else if (m != DayMark.rest && m != DayMark.today) {
      run = 0;
    }
    if (run > best) best = run;
    prev = k;
  }
  if (current > best) best = current;

  final week = [for (final key in weekKeys(now)) WeekMark(key, mark(key))];
  final month = monthKeys(now.year, now.month).where((k) => k.compareTo(todayKey) <= 0);
  final next = milestones.where((m) => m > current).firstOrNull;
  return StreakInfo(
    current: current,
    best: best,
    todayDone: todayMark == DayMark.set,
    week: week,
    weekSetDays: week.where((d) => d.mark == DayMark.set).length,
    monthSetDays: month.where((k) => mark(k) == DayMark.set).length,
    nextMilestone: next == null ? null : next - current,
  );
}

/// 오늘 새로 도달한 기념일. 같은 날 같은 기념일은 한 번만 축하한다(celebrated = '7@2026-10-19').
int? reachedMilestone(StreakInfo info, String todayKey, String? celebrated) {
  if (!info.todayDone || !milestones.contains(info.current)) return null;
  return celebrated == '${info.current}@$todayKey' ? null : info.current;
}
