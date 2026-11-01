import '../model/models.dart';

enum Outcome { achieved, missed, estimated, pending }

class BlockOutcome {
  const BlockOutcome(this.block, this.outcome, [this.log]);

  final ScheduleBlock block;
  final Outcome outcome;
  final ActivityLog? log;

  BlockOutcome withOutcome(Outcome o) => BlockOutcome(block, o, log);
}

double? rateOf(int achieved, int counted) => counted == 0 ? null : achieved / counted;

class HabitRate {
  const HabitRate({
    required this.activity,
    required this.achieved,
    required this.counted,
    required this.estimated,
  });

  final Activity activity;
  final int achieved;

  /// 달성률 분모(예정 블록 중 추정·예정을 뺀 것).
  final int counted;
  final int estimated;

  double? get rate => counted == 0 ? null : achieved / counted;
}

class PeriodSummary {
  const PeriodSummary(this.byActivity);

  final Map<Activity, HabitRate> byActivity;

  int get achieved => byActivity.values.fold(0, (s, r) => s + r.achieved);
  int get counted => byActivity.values.fold(0, (s, r) => s + r.counted);
  double? get rate => counted == 0 ? null : achieved / counted;

  /// 달성률이 가장 높은 습관(회고 카드 '잘한 것').
  HabitRate? get best => _pick((a, b) => a > b);

  /// 달성률이 가장 낮은 습관(회고 카드 '놓친 것').
  HabitRate? get worst => _pick((a, b) => a < b);

  HabitRate? _pick(bool Function(double a, double b) better) {
    HabitRate? out;
    for (final r in byActivity.values) {
      final v = r.rate;
      if (v == null) continue;
      if (out == null || better(v, out.rate!)) out = r;
    }
    return out;
  }
}

/// 달성 판정(엔진 명세 9번).
///
/// - 확정 기록이 있고 시작이 예정 ±30분 안이면 달성
/// - 수면은 취침 ±30분 그리고 목표 수면시간의 90% 이상
/// - 추정 기록은 분모·분자에서 모두 뺀다
class AchievementCalculator {
  const AchievementCalculator({this.toleranceMinutes = 30, this.sleepRatio = 0.9});

  final int toleranceMinutes;
  final double sleepRatio;

  /// 판정 대상이 아니면 null(캘린더 고정 일정, 이동, 버퍼).
  BlockOutcome? judge(
    ScheduleBlock block,
    List<ActivityLog> logs,
    DateTime now, {
    int? goalSleepMinutes,
  }) {
    final activity = block.activity;
    if (activity == null || block.kind == BlockKind.fixed || block.kind == BlockKind.buffer) {
      return null;
    }
    // 할 일 블록은 업무를 이어서 하는 중에 시작되는 경우가 많다. 블록 시작 시각에
    // 이미 진행 중인 업무 기록도 그 블록의 기록으로 본다.
    bool covers(ActivityLog l) => block.kind == BlockKind.task && !l.start.isAfter(block.start) && (l.end ?? now).isAfter(block.start);
    final near = logs
        .where((l) => l.activity == activity && (l.start.difference(block.start).inMinutes.abs() <= toleranceMinutes || covers(l)))
        .toList();
    final confirmed = near.where((l) => !l.isEstimate).toList();

    if (confirmed.isNotEmpty) {
      final log = confirmed.first;
      if (activity == Activity.sleep) {
        final goal = goalSleepMinutes ?? block.minutes;
        if (log.isOpen) return BlockOutcome(block, Outcome.pending, log);
        final ok = log.minutesUntil(now) >= goal * sleepRatio;
        return BlockOutcome(block, ok ? Outcome.achieved : Outcome.missed, log);
      }
      return BlockOutcome(block, Outcome.achieved, log);
    }
    if (near.isNotEmpty) return BlockOutcome(block, Outcome.estimated, near.first);

    final deadline = block.start.add(Duration(minutes: toleranceMinutes));
    return BlockOutcome(block, now.isAfter(deadline) ? Outcome.missed : Outcome.pending);
  }

  List<BlockOutcome> judgeAll(
    List<ScheduleBlock> blocks,
    List<ActivityLog> logs,
    DateTime now, {
    int? goalSleepMinutes,
  }) =>
      [
        for (final b in blocks)
          if (judge(b, logs, now, goalSleepMinutes: goalSleepMinutes) case final o?) o,
      ];

  PeriodSummary summarize(List<BlockOutcome> outcomes) {
    final map = <Activity, HabitRate>{};
    for (final o in outcomes) {
      final a = o.block.activity!;
      final r = map[a] ?? HabitRate(activity: a, achieved: 0, counted: 0, estimated: 0);
      map[a] = HabitRate(
        activity: a,
        achieved: r.achieved + (o.outcome == Outcome.achieved ? 1 : 0),
        counted: r.counted +
            (o.outcome == Outcome.achieved || o.outcome == Outcome.missed ? 1 : 0),
        estimated: r.estimated + (o.outcome == Outcome.estimated ? 1 : 0),
      );
    }
    return PeriodSummary(map);
  }
}
