// 우선순위 학습(기기 안에서 동작). 웹 버전 src/app/priorityModel.ts와 같은 규칙.
// 사용자가 할 일 순서를 끌어서 바꾼 기록과 먼저 끝낸 할 일을 모아, 며칠 뒤부터 추천 순서를 제안한다.
//
// 배우는 것(사람이 읽을 수 있는 이유로 설명할 수 있는 것만):
//  - 종류 선호: 업무·과제·숙제·개인 중 무엇을 위에 두는지
//  - 길이 선호: 짧은 일을 먼저 하는지, 긴 일을 먼저 하는지
//  - 오래된 일: 오래 묵은 일을 위로 올리는지

import 'dart:math' as math;

import '../core/model/models.dart';
import 'state.dart';

const learnDays = 3;

class OrderSample {
  const OrderSample({required this.type, required this.est, required this.age, required this.pos});
  final TaskType type;
  final int est;
  final double age;

  /// 0 = 맨 위, 1 = 맨 아래.
  final double pos;
}

class Prefs {
  const Prefs({required this.days, required this.samples, required this.typePref, required this.lenSlope, required this.ageSlope});
  final int days;
  final int samples;
  final Map<TaskType, double> typePref;

  /// +면 짧은 일을 먼저, −면 긴 일을 먼저.
  final double lenSlope;

  /// +면 오래된 일을 먼저.
  final double ageSlope;
}

const _typeFirst = {TaskType.work: '업무를', TaskType.assignment: '과제를', TaskType.homework: '숙제를', TaskType.personal: '개인 일을'};

double _corr(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 3) return 0;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  return sxx == 0 || syy == 0 ? 0 : sxy / math.sqrt(sxx * syy);
}

List<OrderSample> samplesOf(LearningLog log) {
  final out = <OrderSample>[];
  for (final r in log.reorders) {
    final n = r.items.length;
    if (n < 2) continue;
    for (var i = 0; i < n; i++) {
      final it = r.items[i];
      out.add(OrderSample(type: it.type, est: it.est, age: it.age, pos: i / (n - 1)));
    }
  }
  for (final c in log.completions) {
    out.add(OrderSample(type: c.type, est: c.est, age: c.age, pos: c.pos * 0.5));
  }
  return out;
}

/// 배운 선호. 며칠치가 모이기 전에는 null.
Prefs? learnPrefs(LearningLog log) {
  final days = {...log.reorders.map((r) => dateKey(r.at)), ...log.completions.map((c) => dateKey(c.at))}.length;
  final samples = samplesOf(log);
  if (days < learnDays || samples.length < 6) return null;
  final typePref = <TaskType, double>{};
  for (final t in TaskType.values) {
    final xs = samples.where((s) => s.type == t).map((s) => s.pos).toList();
    // 자료가 적은 종류는 가운데(0.5) 쪽으로 당긴다.
    typePref[t] = (xs.fold<double>(0, (a, b) => a + b) + 0.5 * 2) / (xs.length + 2);
  }
  final pos = [for (final s in samples) s.pos];
  final lenSlope = _corr([for (final s in samples) math.log(s.est + 1)], pos);
  final ageSlope = -_corr([for (final s in samples) s.age], pos);
  return Prefs(days: days, samples: samples.length, typePref: typePref, lenSlope: lenSlope, ageSlope: ageSlope);
}

class OrderSuggestion {
  const OrderSuggestion({required this.order, required this.reasons, required this.moved});
  final List<String> order;
  final List<String> reasons;

  /// 지금 순서에서 자리가 바뀌는 할 일 수.
  final int moved;
}

double _ageDays(TaskItem t, DateTime now) {
  final c = t.createdAt;
  if (c == null) return 0;
  final d = now.difference(c).inMilliseconds / 86400000;
  return d < 0 ? 0 : d;
}

/// 추천 순서. 지금 순서와 같으면 null.
OrderSuggestion? suggestOrder(List<TaskItem> tasks, Prefs prefs, DateTime now) {
  if (tasks.length < 2) return null;
  final ests = [for (final t in tasks) math.log(t.estMinutes + 1)];
  final lo = ests.reduce(math.min);
  final hi = ests.reduce(math.max);
  final ages = [for (final t in tasks) _ageDays(t, now)];
  final maxAge = math.max(1.0, ages.reduce(math.max));
  double score(TaskItem t, int i) {
    final len = hi > lo ? (ests[i] - lo) / (hi - lo) : 0.5;
    return prefs.typePref[t.type]! + 0.35 * prefs.lenSlope * (len - 0.5) - 0.25 * prefs.ageSlope * (ages[i] / maxAge) + i * 0.001;
  }

  final scored = [for (var i = 0; i < tasks.length; i++) (id: tasks[i].id, s: score(tasks[i], i))]..sort((a, b) => a.s.compareTo(b.s));
  final order = [for (final x in scored) x.id];
  var moved = 0;
  for (var i = 0; i < order.length; i++) {
    if (tasks[i].id != order[i]) moved++;
  }
  if (moved == 0) return null;

  final reasons = <String>[];
  final ranked = [...TaskType.values]..sort((a, b) => prefs.typePref[a]!.compareTo(prefs.typePref[b]!));
  final present = ranked.where((t) => tasks.any((x) => x.type == t)).toList();
  if (present.length >= 2 && prefs.typePref[present.last]! - prefs.typePref[present.first]! > 0.15) {
    reasons.add('${_typeFirst[present.first]} 먼저 두는 편이에요');
  }
  if (prefs.lenSlope > 0.2) {
    reasons.add('짧은 일을 먼저 끝내는 편이에요');
  } else if (prefs.lenSlope < -0.2) {
    reasons.add('긴 일을 먼저 시작하는 편이에요');
  }
  if (prefs.ageSlope > 0.2) reasons.add('오래된 일을 먼저 처리하는 편이에요');
  if (reasons.isEmpty) reasons.add('최근 순서를 바꾼 방식과 비슷하게 맞췄어요');
  return OrderSuggestion(order: order, reasons: reasons, moved: moved);
}

/// 순서를 바꿀 때 남길 기록.
Reorder snapshot(List<TaskItem> tasks, DateTime now) =>
    Reorder(at: now, items: [for (final t in tasks) OrderItem(type: t.type, est: t.estMinutes, age: (_ageDays(t, now) * 10).round() / 10)]);
