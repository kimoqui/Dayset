// 단계적 교정 계획(엔진 명세 8번). MVP는 수면(취침·기상)에만 쓴다.

enum CorrectionStatus { active, done }

/// 주간 판정 결과(회고 카드와 '내 목표' 화면 문구에 쓴다).
enum WeeklyDecision {
  stepUp('한 단계 올림'),
  stepBack('한 단계 내림'),
  hold('한 주 유지(피곤함)'),
  keep('그대로 유지'),
  done('목표 도달');

  const WeeklyDecision(this.label);
  final String label;

  static WeeklyDecision fromName(String? n) => WeeklyDecision.values.firstWhere((d) => d.name == n, orElse: () => WeeklyDecision.keep);
}

class CorrectionPlan {
  const CorrectionPlan({
    required this.baseline,
    required this.target,
    required this.stepSize,
    required this.totalWeeks,
    this.currentStep = 0,
    this.status = CorrectionStatus.active,
  });

  /// 최근 14일 평균으로 계획을 만든다.
  ///
  /// 시각은 자정 기준 분이다. 새벽 1시 취침처럼 자정을 넘는 값은 25:00 = 1500으로
  /// 넣는다. 예: baseline 1500(01:00), target 1380(23:00), step 30 → 4주.
  factory CorrectionPlan.create({
    required int baseline,
    required int target,
    required int stepSize,
  }) {
    assert(stepSize > 0);
    final gap = (target - baseline).abs();
    final weeks = (gap / stepSize).ceil();
    return CorrectionPlan(
      baseline: baseline,
      target: target,
      stepSize: stepSize,
      totalWeeks: weeks,
      status: weeks == 0 ? CorrectionStatus.done : CorrectionStatus.active,
    );
  }

  final int baseline;
  final int target;
  final int stepSize;
  final int totalWeeks;
  final int currentStep;
  final CorrectionStatus status;

  Map<String, Object?> toJson() => {
        'baseline': baseline,
        'target': target,
        'stepSize': stepSize,
        'totalWeeks': totalWeeks,
        'currentStep': currentStep,
        'status': status.name,
      };

  factory CorrectionPlan.fromJson(Map<String, Object?> j) => CorrectionPlan(
        baseline: (j['baseline'] as num).round(),
        target: (j['target'] as num).round(),
        stepSize: (j['stepSize'] as num).round(),
        totalWeeks: (j['totalWeeks'] as num).round(),
        currentStep: (j['currentStep'] as num? ?? 0).round(),
        status: j['status'] == 'done' ? CorrectionStatus.done : CorrectionStatus.active,
      );

  int get _direction => target < baseline ? -1 : 1;

  /// 이번 주 목표값. 일정 엔진은 교정 중인 습관에 이 값을 쓴다.
  int get weekTarget {
    final v = baseline + _direction * stepSize * currentStep;
    return _direction < 0 ? (v < target ? target : v) : (v > target ? target : v);
  }

  /// 다음 주 목표값(단계를 올렸을 때).
  int get nextTarget {
    final v = baseline + _direction * stepSize * (currentStep + 1);
    return _direction < 0 ? (v < target ? target : v) : (v > target ? target : v);
  }

  /// 매주 월요일 판정.
  ///
  /// - 피곤함이 같은 주 2번 이상이면 한 주 유지(R8)
  /// - 달성률 80% 이상이면 한 단계 올림
  /// - 50% 미만이면 한 단계 내림
  ({CorrectionPlan plan, WeeklyDecision decision}) weeklyUpdate({
    required double achievementRate,
    int tiredCount = 0,
  }) {
    if (status == CorrectionStatus.done) {
      return (plan: this, decision: WeeklyDecision.done);
    }
    var step = currentStep;
    WeeklyDecision decision;
    if (tiredCount >= 2) {
      decision = WeeklyDecision.hold;
    } else if (achievementRate >= 0.8) {
      step += 1;
      decision = WeeklyDecision.stepUp;
    } else if (achievementRate < 0.5) {
      step = step > 0 ? step - 1 : 0;
      decision = WeeklyDecision.stepBack;
    } else {
      decision = WeeklyDecision.keep;
    }
    final done = step >= totalWeeks;
    return (
      plan: CorrectionPlan(
        baseline: baseline,
        target: target,
        stepSize: stepSize,
        totalWeeks: totalWeeks,
        currentStep: done ? totalWeeks : step,
        status: done ? CorrectionStatus.done : CorrectionStatus.active,
      ),
      decision: done ? WeeklyDecision.done : decision,
    );
  }
}

/// 자정 기준 분을 'HH:MM'으로. 24시를 넘으면 다음 날 시각으로 보여준다.
String formatClockMinutes(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}
