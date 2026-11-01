// 베타 지표. 서버가 없어서 기기 안에 쌓았다가, 사용자가 동의하면 파일로 내보낸다. 웹 버전 src/app/metrics.ts와 같은 형식.
//
// 넣는 것: 익명 번호, 쓴 날 수, 활성화(2일 관찰 완료), 1·7·14일 유지, 주별 셋 데이 수, 기능 사용 횟수, 설문 응답, 불편 신고.
// 넣지 않는 것: 이름, 기록한 시각·내용, 할 일·일정 제목, 위치.
// 출시 판단 기준: 7일 유지 40% · '없어지면 매우 아쉽다' 40% · 주 3일 이상 셋 데이 30%.

import '../core/model/models.dart';
import 'derive.dart';
import 'duration.dart';
import 'nearby.dart' show fnv1a;
import 'state.dart';
import 'streak.dart';

const metricsSchema = 'dayset-metrics/1';
const appVersion = '0.9-preview-app';

/// 이름과 연결되지 않는 익명 번호. 같은 기기에서는 늘 같다(웹과 같은 계산).
String anonId(AppState s) => 'b-${fnv1a('dayset:${s.profile.id}').toRadixString(36).padLeft(7, '0')}';

MetricsLog addOpen(MetricsLog m, DateTime t) {
  final k = dateKey(t);
  if (m.opens.contains(k)) return m;
  final opens = [...m.opens, k];
  return m.copyWith(opens: opens.length > 400 ? opens.sublist(opens.length - 400) : opens);
}

MetricsLog addEvent(MetricsLog m, DateTime t, String k, [String? v]) {
  final events = [...m.events, MetricsEvent(at: t, k: k, v: (v == null || v.isEmpty) ? null : v)];
  return m.copyWith(events: events.length > 1000 ? events.sublist(events.length - 1000) : events);
}

/// 그 기기를 쓴 날(연 날 + 기록이 있는 날).
List<String> activeDays(AppState s) {
  final days = {...s.metrics.opens};
  for (final l in s.logs) {
    if (l.source != LogSource.estimate && l.source != LogSource.evening) days.add(dateKey(l.start));
  }
  return days.toList()..sort();
}

int _dayIndex(String start, String k) => (fromKey(k).difference(fromKey(start)).inHours / 24).round();

/// 내보낼 지표(JSON). 키 이름은 웹 버전과 같다.
Json computeMetrics(AppState s, DateTime now) {
  final install = dateKey(s.metrics.installAt);
  final days = activeDays(s);
  final idx = [for (final k in days) _dayIndex(install, k)];
  int ev(String k) => s.metrics.events.where((e) => e.k == k).length;

  final obs = s.observation;
  final reviewed = obs != null && obs.phase != ObservationPhase.recording;
  final activated = reviewed || (obs == null && s.plans.isNotEmpty);
  final firstPlanDay = (s.plans.keys.toList()..sort()).firstOrNull;
  final activatedKey = obs?.day2 ?? firstPlanDay;

  // 설치한 주부터 이번 주까지 주별 셋 데이
  final weeks = <Json>[];
  for (var m = mondayOf(s.metrics.installAt); !m.isAfter(now); m = addDays(m, 7)) {
    final keys = weekKeys(m).where((k) => k.compareTo(install) >= 0 && k.compareTo(dateKey(now)) <= 0).toList();
    if (keys.isEmpty) continue;
    weeks.add({'week': dateKey(m), 'setDays': periodStats(s, keys, now).setDays});
  }
  final streak = computeStreak(s, now);
  final ratios = <String, double>{};
  for (final type in TaskType.values) {
    final c = calibrationFor(s.durations, type: type, title: '');
    if (c != null) ratios[type.name] = c.ratio;
  }

  return {
    'schema': metricsSchema,
    'appVersion': appVersion,
    'anonId': anonId(s),
    'generatedAt': encodeDate(now),
    'installDate': install,
    'daysSinceInstall': _dayIndex(install, dateKey(now)),
    'consent': s.consent == null ? null : {'health': s.consent!.health, 'metrics': s.consent!.metrics},
    'goal': s.intent == null ? null : {'focus': [for (final f in s.intent!.focus) f.name]},
    'activation': {
      'observationStarted': obs != null,
      'reviewed': reviewed,
      'activated': activated,
      'activatedDay': activated && activatedKey != null ? (_dayIndex(install, activatedKey) < 0 ? 0 : _dayIndex(install, activatedKey)) : null,
    },
    'retention': {'activeDays': days.length, 'd1': idx.any((i) => i >= 1), 'd7': idx.any((i) => i >= 7), 'd14': idx.any((i) => i >= 14)},
    'habit': {
      'weeks': weeks,
      'weeksWith3SetDays': weeks.where((w) => (w['setDays'] as int) >= 3).length,
      'currentStreak': streak.current,
      'bestStreak': streak.best,
    },
    'usage': {
      'nowButtonTaps': s.logs.where((l) => l.source == LogSource.button).length,
      'checkPopupRecords': ev('check_record'),
      'notificationRecords': ev('notify_record'),
      'tasksAdded': ev('task_add'),
      'tasksDone': s.tasks.where((t) => t.done).length,
      'reorders': s.learning.reorders.length,
      'calendarsConnected': s.calendars.length,
      'shares': ev('share'),
      'friends': s.friends.length,
      'nearbyPeople': s.nearby.people.where((p) => !p.demo).length,
      'eveningChecks': s.eveningDone.length,
    },
    'calibration': {'samples': s.durations.samples.where((x) => !x.outlier).length, 'ratios': ratios},
    'notify': {'enabled': s.notify.enabled, 'sticky': s.notify.sticky, 'remind': s.notify.remind, 'token': s.notify.token != null},
    'surveys': [
      for (final x in s.feedback.surveys)
        {'key': x.key, 'answer': x.answer, if (x.best != null) 'best': x.best, if (x.worst != null) 'worst': x.worst, 'day': _dayIndex(install, dateKey(x.at))},
    ],
    'feedback': [
      for (final r in s.feedback.reports) {'kind': r.kind, 'text': r.text, 'page': r.page, 'day': _dayIndex(install, dateKey(r.at))},
    ],
  };
}

/// 설문을 보여 줄 때(7일째, 28일째). 이미 답했거나 오늘 '나중에'를 눌렀으면 null.
String? surveyDue(AppState s, DateTime now) {
  if (s.consent == null) return null;
  final since = _dayIndex(dateKey(s.metrics.installAt), dateKey(now));
  if (s.feedback.surveyLater == dateKey(now)) return null;
  final done = {for (final x in s.feedback.surveys) x.key};
  if (since >= 28 && !done.contains('d28')) return 'd28';
  if (since >= 7 && !done.contains('d7')) return 'd7';
  return null;
}
