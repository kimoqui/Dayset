// 걸리는 시간 자동 보정(기기 안에서 동작). 웹 버전 src/app/duration.ts와 같은 규칙.
//
// 할 일을 끝낼 때 '처음 예상한 시간'과 '실제로 쓴 시간'을 남기고,
// 같은 이름의 일(2건 이상) 또는 같은 종류의 일(3건 이상)에서 실제/예상 비율의 중앙값을 구한다.
// 일정에는 예상 × 비율만큼 잡는다. 사용자가 적은 예상 시간은 그대로 두고, 일정에만 반영한다.
// 실제 시간을 알 수 없으면(일정 밖에서 끝냄) 기록하지 않는다.

import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import 'state.dart';

const minTitleSamples = 2;
const minTypeSamples = 3;
const _maxSamples = 200;

/// 5분 안 된 기록은 실수로 체크한 것으로 보고 남기지 않는다.
const minActual = 5;

enum CalibrationBasis { title, type }

class Calibration {
  const Calibration({required this.ratio, required this.n, required this.basis});
  final double ratio;
  final int n;
  final CalibrationBasis basis;
}

final _noise = RegExp(r'[\s\d.,·_\-()\[\]#]+');

/// 이름 비교용: 공백·숫자·기호를 빼고 소문자로(예: '영어 숙제 3' = '영어숙제').
String normTitle(String title) => title.toLowerCase().replaceAll(_noise, '');

double _median(List<double> xs) {
  final a = [...xs]..sort();
  final m = a.length >> 1;
  return a.length.isOdd ? a[m] : (a[m - 1] + a[m]) / 2;
}

/// 이 할 일에 쓸 보정 비율. 자료가 적거나 차이가 10% 안쪽이면 null(보정 안 함).
Calibration? calibrationFor(DurationLearning d, {required TaskType type, required String title}) {
  if (!d.on) return null;
  final all = d.samples.where((x) => !x.outlier).toList();
  final recent = all.length > 60 ? all.sublist(all.length - 60) : all;
  final name = normTitle(title);
  final byTitle = name.isEmpty ? <DurationSample>[] : recent.where((x) => normTitle(x.title) == name).toList();
  final byType = recent.where((x) => x.type == type).toList();
  final List<DurationSample> xs;
  final CalibrationBasis basis;
  if (byTitle.length >= minTitleSamples) {
    xs = byTitle;
    basis = CalibrationBasis.title;
  } else if (byType.length >= minTypeSamples) {
    xs = byType;
    basis = CalibrationBasis.type;
  } else {
    return null;
  }
  final last = xs.length > 10 ? xs.sublist(xs.length - 10) : xs;
  final r = _median([for (final x in last) x.actual / x.est]).clamp(0.5, 2.0);
  final ratio = (r * 10).round() / 10;
  if ((ratio - 1).abs() < 0.1) return null;
  return Calibration(ratio: ratio, n: xs.length, basis: basis);
}

Calibration? calibrationForTask(DurationLearning d, TaskItem t) => calibrationFor(d, type: t.type, title: t.title);

int _round5(double m) {
  final r = (m / 5).round() * 5;
  return r < 5 ? 5 : r;
}

/// 일정에 잡을 시간 = 예상 × 보정 비율 + 사용자가 늘린 시간.
int plannedMinutes(TaskItem t, DurationLearning d) {
  final c = calibrationForTask(d, t);
  return (c != null ? _round5(t.estMinutes * c.ratio) : t.estMinutes) + t.extraMinutes;
}

DurationLearning addSample(DurationLearning d, DurationSample s) {
  if (s.est <= 0 || s.actual < minActual) return d;
  final r = s.actual / s.est;
  final next = [...d.samples, s.copyWith(outlier: r < 1 / 3 || r > 3)];
  return d.copyWith(samples: next.length > _maxSamples ? next.sublist(next.length - _maxSamples) : next);
}

String _num(double v) {
  final x = (v * 100).round() / 100;
  return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
}

/// 사람이 읽는 설명(예: '숙제는 보통 예상보다 1.3배 걸렸어요').
String calibrationText(String title, Calibration c, String typeLabel) {
  final word = c.basis == CalibrationBasis.title ? title : typeLabel;
  final who = '${c.basis == CalibrationBasis.title ? "'$word'" : word}${hasBatchim(word) ? '은' : '는'}';
  final x = _num(c.ratio);
  return c.ratio > 1 ? '$who 보통 예상보다 $x배 걸렸어요' : '$who 보통 예상보다 빨리 끝냈어요($x배)';
}
