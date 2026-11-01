import '../model/models.dart';

/// 연결 코칭(엔진 명세 5번·7번).
///
/// 규칙의 수치는 [RuleConfig]로 원격 설정에서 내려받아 앱 업데이트 없이 바꾼다.
/// 조건 판단은 규칙마다 Dart 코드로 두고, 문턱값만 설정으로 뺀다(안전한 구조).

// ---------------------------------------------------------------------------
// 규칙 설정
// ---------------------------------------------------------------------------

class RuleConfig {
  const RuleConfig({required this.id, this.enabled = true, this.params = const {}});

  factory RuleConfig.fromJson(Map<String, Object?> json) => RuleConfig(
        id: json['id']! as String,
        enabled: (json['enabled'] as bool?) ?? true,
        params: {
          for (final e in ((json['params'] as Map?) ?? const {}).entries)
            e.key as String: e.value as num,
        },
      );

  final String id;
  final bool enabled;
  final Map<String, num> params;

  num p(String key, num fallback) => params[key] ?? fallback;
}

/// 기본 규칙값. 원격 설정이 없을 때 쓴다.
const List<Map<String, Object?>> defaultRuleJson = [
  {'id': 'R1', 'params': {'min_sleep_minutes': 360, 'max_focus_blocks': 2, 'exercise_minutes': 15}},
  {'id': 'R2', 'params': {'min_gap_before_bed_minutes': 180, 'dinner_shift_minutes': 30}},
  {'id': 'R3', 'params': {'late_minutes': 60, 'exercise_minutes': 15}},
  {'id': 'R4', 'params': {'min_snooze': 3, 'days': 3, 'bedtime_shift_minutes': 15}},
  {'id': 'R5', 'params': {'missed_meals': 2}},
  {'id': 'R6', 'params': {'repeat': 2, 'remind_before_minutes': 5}},
  {'id': 'R7', 'params': {'repeat': 2}},
  {'id': 'R8', 'params': {'repeat': 2}},
  {'id': 'R9', 'params': {'repeat': 2, 'shrink_to_minutes': 10}},
];

List<RuleConfig> parseRules(List<Map<String, Object?>> json) =>
    [for (final j in json) RuleConfig.fromJson(j)];

// ---------------------------------------------------------------------------
// 이벤트(트리거)
// ---------------------------------------------------------------------------

sealed class CoachEvent {
  const CoachEvent();
}

/// 기상 기록(R1, R4).
class WakeLogged extends CoachEvent {
  const WakeLogged({required this.sleepMinutes, this.recentSnoozes = const []});

  final int sleepMinutes;

  /// 최근 며칠의 스누즈 횟수. 마지막이 오늘이다.
  final List<int> recentSnoozes;
}

/// 저녁 식사 기록(R2).
class DinnerLogged extends CoachEvent {
  const DinnerLogged({required this.end, required this.bedtime});

  final DateTime end;
  final DateTime bedtime;
}

/// 업무 종료 기록(R3).
class WorkEnded extends CoachEvent {
  const WorkEnded({required this.planned, required this.actual});

  final DateTime planned;
  final DateTime actual;
}

/// 저녁 확인(R5).
class EveningCheck extends CoachEvent {
  const EveningCheck({required this.missedMeals});

  final int missedMeals;
}

/// 실패 이유 입력(R6~R9). [weekCount]는 같은 주, 같은 습관에서 그 이유를 고른 횟수.
class MissReasonAdded extends CoachEvent {
  const MissReasonAdded({
    required this.habit,
    required this.reason,
    required this.weekCount,
    this.habitMinutes,
  });

  final Activity habit;
  final MissReason reason;
  final int weekCount;
  final int? habitMinutes;
}

// ---------------------------------------------------------------------------
// 제안
// ---------------------------------------------------------------------------

class BlockChange {
  const BlockChange.shrink(this.blockId, this.newMinutes, this.newTitle)
      : deferToTomorrow = false;
  const BlockChange.defer(this.blockId)
      : newMinutes = null,
        newTitle = null,
        deferToTomorrow = true;

  final String blockId;
  final int? newMinutes;
  final String? newTitle;
  final bool deferToTomorrow;
}

class CoachingSuggestion {
  const CoachingSuggestion({
    required this.ruleId,
    required this.message,
    this.changes = const [],
    this.patch = const {},
  });

  final String ruleId;

  /// 'UX 문구 가이드'를 따른다: 사실 + 다음 행동, 판단하지 않는다.
  final String message;

  /// 오늘 일정 블록 변경.
  final List<BlockChange> changes;

  /// 블록이 아닌 변경(내일 일정·알람·알림 설정). 키는 설정 저장소가 해석한다.
  final Map<String, Object> patch;
}

enum CoachDecision { accepted, rejected, expired }

class CoachRecord {
  const CoachRecord({required this.ruleId, required this.at, required this.decision});

  final String ruleId;
  final DateTime at;
  final CoachDecision decision;

  Map<String, Object?> toJson() => {'ruleId': ruleId, 'at': encodeDate(at), 'decision': decision.name};

  factory CoachRecord.fromJson(Map<String, Object?> j) => CoachRecord(
        ruleId: j['ruleId'] as String,
        at: decodeDate(j['at'])!,
        decision: CoachDecision.values.firstWhere((d) => d.name == j['decision'], orElse: () => CoachDecision.expired),
      );
}

/// 하루 3건 이하, 같은 규칙을 2번 연속 거절하면 7일간 쉰다.
class CoachingPolicy {
  const CoachingPolicy({this.maxPerDay = 3, this.rejectStreak = 2, this.cooldownDays = 7});

  final int maxPerDay;
  final int rejectStreak;
  final int cooldownDays;

  bool allows(String ruleId, DateTime now, List<CoachRecord> history, {int shownToday = 0}) {
    final today = history.where((r) => _sameDay(r.at, now)).length + shownToday;
    if (today >= maxPerDay) return false;
    final mine = history.where((r) => r.ruleId == ruleId).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (mine.length < rejectStreak) return true;
    final last = mine.sublist(mine.length - rejectStreak);
    final streak = last.every((r) => r.decision == CoachDecision.rejected);
    if (!streak) return true;
    return now.difference(last.last.at).inDays >= cooldownDays;
  }
}

// ---------------------------------------------------------------------------
// 엔진
// ---------------------------------------------------------------------------

class CoachingEngine {
  CoachingEngine({List<RuleConfig>? rules, this.policy = const CoachingPolicy()})
      : rules = {for (final r in (rules ?? parseRules(defaultRuleJson))) r.id: r};

  final Map<String, RuleConfig> rules;
  final CoachingPolicy policy;

  List<CoachingSuggestion> evaluate(
    CoachEvent event, {
    required List<ScheduleBlock> today,
    required DateTime now,
    List<CoachRecord> history = const [],
    int shownToday = 0,
  }) {
    final raw = <CoachingSuggestion?>[
      switch (event) {
        final WakeLogged e => _r1(e, today, now),
        final DinnerLogged e => _r2(e),
        final WorkEnded e => _r3(e, today, now),
        final EveningCheck e => _r5(e),
        final MissReasonAdded e => _missReason(e),
      },
      if (event is WakeLogged) _r4(event),
    ];
    final out = <CoachingSuggestion>[];
    for (final s in raw) {
      if (s == null) continue;
      if (policy.allows(s.ruleId, now, history, shownToday: shownToday + out.length)) out.add(s);
    }
    return out;
  }

  RuleConfig? _on(String id) {
    final r = rules[id];
    return (r != null && r.enabled) ? r : null;
  }

  CoachingSuggestion? _r1(WakeLogged e, List<ScheduleBlock> today, DateTime now) {
    final r = _on('R1');
    if (r == null || e.sleepMinutes >= r.p('min_sleep_minutes', 360)) return null;
    final exMin = r.p('exercise_minutes', 15).toInt();
    final maxFocus = r.p('max_focus_blocks', 2).toInt();
    final changes = <BlockChange>[];
    final upcoming = today.where((b) => b.end.isAfter(now)).toList();
    for (final b in upcoming) {
      if (b.activity == Activity.exercise && b.minutes > exMin) {
        changes.add(BlockChange.shrink(b.id, exMin, '운동 · $exMin분 가벼운 루틴'));
      }
    }
    final focus = upcoming.where((b) => b.kind == BlockKind.task && b.focus).toList();
    for (final b in focus.skip(maxFocus)) {
      changes.add(BlockChange.defer(b.id));
    }
    if (changes.isEmpty) return null;
    final hasExercise = changes.any((c) => !c.deferToTomorrow);
    final action = hasExercise
        ? '오늘 운동을 $exMin분 가벼운 루틴으로 바꿀까요?'
        : '오늘 집중 작업을 $maxFocus개로 줄일까요?';
    return CoachingSuggestion(
      ruleId: 'R1',
      message: '어젯밤 ${formatDuration(e.sleepMinutes)} 잤어요. $action',
      changes: changes,
    );
  }

  CoachingSuggestion? _r2(DinnerLogged e) {
    final r = _on('R2');
    if (r == null) return null;
    final gap = e.bedtime.difference(e.end).inMinutes;
    if (gap >= r.p('min_gap_before_bed_minutes', 180)) return null;
    final shift = r.p('dinner_shift_minutes', 30).toInt();
    return CoachingSuggestion(
      ruleId: 'R2',
      message: '저녁을 취침 ${formatDuration(gap < 0 ? 0 : gap)} 전에 마쳤어요. '
          '내일 저녁 식사를 $shift분 앞당기고, 아침은 가벼운 메뉴로 추천할까요?',
      patch: {'tomorrow_dinner_shift_minutes': -shift, 'breakfast_light': true},
    );
  }

  CoachingSuggestion? _r3(WorkEnded e, List<ScheduleBlock> today, DateTime now) {
    final r = _on('R3');
    if (r == null) return null;
    final late = e.actual.difference(e.planned).inMinutes;
    if (late < r.p('late_minutes', 60)) return null;
    final exMin = r.p('exercise_minutes', 15).toInt();
    final changes = [
      for (final b in today)
        if (b.activity == Activity.exercise && b.end.isAfter(now) && b.minutes > exMin)
          BlockChange.shrink(b.id, exMin, '운동 · $exMin분 가벼운 루틴'),
    ];
    if (changes.isEmpty) return null;
    return CoachingSuggestion(
      ruleId: 'R3',
      message: '업무가 예정보다 ${formatDuration(late)} 늦게 끝났어요. 오늘 운동을 $exMin분으로 줄일까요?',
      changes: changes,
    );
  }

  CoachingSuggestion? _r4(WakeLogged e) {
    final r = _on('R4');
    if (r == null) return null;
    final days = r.p('days', 3).toInt();
    final minSnooze = r.p('min_snooze', 3);
    if (e.recentSnoozes.length < days) return null;
    final lastDays = e.recentSnoozes.sublist(e.recentSnoozes.length - days);
    if (!lastDays.every((n) => n >= minSnooze)) return null;
    final shift = r.p('bedtime_shift_minutes', 15).toInt();
    return CoachingSuggestion(
      ruleId: 'R4',
      message: '$days일 연속 알람을 ${minSnooze.toInt()}번 이상 미뤘어요. 취침 알람을 $shift분 앞당길까요?',
      patch: {'bedtime_shift_minutes': -shift},
    );
  }

  CoachingSuggestion? _r5(EveningCheck e) {
    final r = _on('R5');
    if (r == null || e.missedMeals < r.p('missed_meals', 2)) return null;
    return CoachingSuggestion(
      ruleId: 'R5',
      message: '오늘 식사를 ${e.missedMeals}번 놓쳤어요. 내일 첫 끼는 단백질 위주 메뉴로 추천할까요?',
      patch: {'next_meal_focus': 'protein'},
    );
  }

  CoachingSuggestion? _missReason(MissReasonAdded e) {
    final id = switch (e.reason) {
      MissReason.forgot => 'R6',
      MissReason.conflict => 'R7',
      MissReason.tired => 'R8',
      MissReason.unwilling => 'R9',
      MissReason.other => null,
    };
    if (id == null) return null;
    final r = _on(id);
    if (r == null || e.weekCount < r.p('repeat', 2)) return null;
    final h = e.habit.label;
    final n = e.weekCount;
    switch (id) {
      case 'R6':
        final before = r.p('remind_before_minutes', 5).toInt();
        return CoachingSuggestion(
          ruleId: id,
          message: '이번 주 $h${objectParticle(h)} 깜빡해서 $n번 놓쳤어요. '
              '$before분 전에 소리 알람으로 알려드릴까요?',
          patch: {'habit': e.habit.name, 'remind_before_minutes': before, 'sound': true},
        );
      case 'R7':
        return CoachingSuggestion(
          ruleId: id,
          message: '이번 주 $h${subjectParticle(h)} 일·약속과 $n번 겹쳤어요. 다른 시간으로 옮길까요?',
          patch: {'habit': e.habit.name, 'suggest_move': true},
        );
      case 'R8':
        return CoachingSuggestion(
          ruleId: id,
          message: '이번 주 피곤해서 $h${objectParticle(h)} $n번 놓쳤어요. '
              '교정 단계를 한 주 유지하고 수면부터 지킬까요?',
          patch: {'hold_correction_week': true},
        );
      default:
        final to = r.p('shrink_to_minutes', 10).toInt();
        final from = e.habitMinutes;
        final size = from != null ? '$from분 대신 $to분으로' : '$to분으로';
        return CoachingSuggestion(
          ruleId: id,
          message: '$h${objectParticle(h)} 더 작게 시작해볼까요? $size 줄여요.',
          patch: {'habit': e.habit.name, 'shrink_to_minutes': to},
        );
    }
  }
}

/// 제안을 승인했을 때 오늘 블록에 반영한다. 미룬 블록은 목록에서 빠지고 [deferred]에 담긴다.
({List<ScheduleBlock> blocks, List<ScheduleBlock> deferred}) applyChanges(
    List<ScheduleBlock> blocks, List<BlockChange> changes) {
  final byId = {for (final c in changes) c.blockId: c};
  final kept = <ScheduleBlock>[];
  final deferred = <ScheduleBlock>[];
  for (final b in blocks) {
    final c = byId[b.id];
    if (c == null) {
      kept.add(b);
    } else if (c.deferToTomorrow) {
      deferred.add(b);
    } else {
      kept.add(b.copyWith(
        end: b.start.add(Duration(minutes: c.newMinutes!)),
        title: c.newTitle,
        adjusted: true,
      ));
    }
  }
  return (blocks: kept, deferred: deferred);
}

/// 받침이 있으면 '을', 없으면 '를'.
String objectParticle(String word) => hasBatchim(word) ? '을' : '를';

/// 받침이 있으면 '이', 없으면 '가'.
String subjectParticle(String word) => hasBatchim(word) ? '이' : '가';

/// 받침이 있으면 '은', 없으면 '는'.
String topicParticle(String word) => hasBatchim(word) ? '은' : '는';

bool hasBatchim(String word) {
  if (word.isEmpty) return false;
  final code = word.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) return false;
  return (code - 0xAC00) % 28 != 0;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
