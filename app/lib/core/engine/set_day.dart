// 핵심 지표 '셋 데이(Set Day)' 판정.
//
// 셋 데이 = 기상 알람 ±30분 안에 기상을 기록하고, 그날 습관 블록을 70% 이상 달성한 날.
// 저녁 확인에서 고른 '못 했어요'(놓침)와 '쉬는 날'(판정 제외)도 함께 반영한다.

import '../model/models.dart';
import 'achievement.dart';

class DayMarks {
  const DayMarks({this.missed = const {}, this.skipped = const {}, this.rest = false});

  /// 저녁 확인에서 '못 했어요'로 고른 블록 id.
  final Set<String> missed;

  /// 저녁 확인에서 '쉬는 날'로 고른 블록 id(판정에서 뺀다).
  final Set<String> skipped;

  /// 하루 전체를 쉬는 날로 표시했는지.
  final bool rest;
}

class DayEvaluation {
  const DayEvaluation({
    required this.outcomes,
    required this.habits,
    required this.wakeAt,
    required this.wakeOk,
    required this.achieved,
    required this.total,
    required this.rate,
    required this.rest,
    required this.isSetDay,
  });

  /// 판정 대상 블록(습관 + 할 일) 결과.
  final List<BlockOutcome> outcomes;

  /// 습관 블록(수면·식사·운동) 결과. 셋 데이 판정에 쓴다.
  final List<BlockOutcome> habits;
  final DateTime? wakeAt;
  final bool wakeOk;
  final int achieved;

  /// 분모: 습관 블록 중 추정을 뺀 수.
  final int total;
  final double? rate;
  final bool rest;
  final bool isSetDay;
}

DayEvaluation evaluateDay({
  required List<ScheduleBlock> blocks,
  required List<ActivityLog> logs,
  required DateTime wake,
  required DateTime? wakeAt,
  required DateTime now,
  required int goalSleepMinutes,
  DayMarks marks = const DayMarks(),
  double setRatio = 0.7,
  int wakeToleranceMinutes = 30,
}) {
  const calc = AchievementCalculator();
  final outcomes = calc
      .judgeAll(blocks.where((b) => !marks.skipped.contains(b.id)).toList(), logs, now, goalSleepMinutes: goalSleepMinutes)
      .map((o) => marks.missed.contains(o.block.id) && o.outcome != Outcome.achieved ? o.withOutcome(Outcome.missed) : o)
      .toList();
  final habits = outcomes.where((o) => o.block.kind == BlockKind.habit).toList();
  final total = habits.where((o) => o.outcome != Outcome.estimated).length;
  final achieved = habits.where((o) => o.outcome == Outcome.achieved).length;
  final rate = total == 0 ? null : achieved / total;
  final wakeOk = wakeAt != null && diffMin(wakeAt, wake).abs() <= wakeToleranceMinutes;
  final isSetDay = !marks.rest && wakeOk && rate != null && rate >= setRatio;
  return DayEvaluation(
    outcomes: outcomes,
    habits: habits,
    wakeAt: wakeAt,
    wakeOk: wakeOk,
    achieved: achieved,
    total: total,
    rate: rate,
    rest: marks.rest,
    isSetDay: isSetDay,
  );
}
