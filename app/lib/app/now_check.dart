// 일정 체크: 지금 일정과 지금 기록을 맞춰 보고, 기록할 때를 알려 준다. 웹 버전 src/app/nowCheck.ts와 같은 규칙.
//
// - due  : 일정이 시작됐는데 그 활동이 기록되지 않음 → "점심 식사 시간이에요, 시작했으면 눌러 주세요"
// - ok   : 일정대로 기록 중
// - over : 일정은 끝났는데 그 활동 기록이 이어지는 중(끝날 때 누르기를 잊은 경우)
// - next : 지금 일정이 없음 → 다음 일정 미리 보기
// - none : 오늘 일정이 아직 없음(첫날 기록 중 등)
// 수면은 기상·취침 알람이 맡고, 이동(buffer)은 기록 대상이 아니라서 보지 않는다.

import '../core/model/models.dart';
import 'derive.dart';
import 'state.dart';

enum CheckKind { due, ok, over, next, none }

class NowCheck {
  const NowCheck({
    required this.kind,
    this.block,
    this.expected,
    this.current,
    this.currentMinutes = 0,
    this.minutes = 0,
    this.next,
    this.skipped = false,
  });
  final CheckKind kind;
  final ScheduleBlock? block;

  /// 그 일정에서 기대하는 활동.
  final Activity? expected;

  /// 지금 기록 중인 활동.
  final Activity? current;

  /// 지금 기록이 시작된 지 몇 분.
  final int currentMinutes;

  /// 일정이 시작된 지 몇 분(due), 끝난 지 몇 분(over), 시작까지 몇 분(next).
  final int minutes;
  final ScheduleBlock? next;

  /// 사용자가 '지금은 안 해요'로 넘긴 조각이면 true(팝업은 작게, 알림은 보내지 않음).
  final bool skipped;

  /// 알림·팝업을 다시 띄울지 판단하는 열쇠(같은 열쇠면 한 번만).
  String get key => '${kind.name}:${block?.id ?? next?.id ?? '-'}';
}

/// 일정 조각에서 기대하는 활동. 할 일·회의·수업은 업무로 본다.
Activity? expectedActivity(ScheduleBlock b) {
  if (b.kind == BlockKind.buffer) return null;
  if (b.kind == BlockKind.task || b.kind == BlockKind.fixed) return Activity.work;
  final a = b.activity;
  return a == Activity.sleep ? null : a;
}

/// 일정이 끝난 뒤 이 시간 안이면 '끝났으면 눌러 주세요'를 묻는다.
const _overWindow = 45;

NowCheck nowCheck(AppState s, DateTime now) {
  final log = currentLog(s);
  final current = log?.activity;
  final currentMinutes = log == null ? 0 : (diffMin(now, log.start) < 0 ? 0 : diffMin(now, log.start));
  final plan = s.plans[dateKey(now)];
  if (!s.onboarded || s.observation?.phase == ObservationPhase.recording || plan == null) {
    return NowCheck(kind: CheckKind.none, current: current, currentMinutes: currentMinutes);
  }

  final blocks = plan.blocks.where((b) => expectedActivity(b) != null).toList();
  final next = blocks.where((b) => b.start.isAfter(now)).firstOrNull;
  final block = blocks.where((b) => !b.start.isAfter(now) && now.isBefore(b.end)).firstOrNull;

  if (block != null) {
    final expected = expectedActivity(block)!;
    final minutes = diffMin(now, block.start);
    if (current == expected) {
      return NowCheck(kind: CheckKind.ok, block: block, expected: expected, current: current, currentMinutes: currentMinutes, minutes: minutes, next: next);
    }
    return NowCheck(
      kind: CheckKind.due,
      block: block,
      expected: expected,
      current: current,
      currentMinutes: currentMinutes,
      minutes: minutes,
      next: next,
      skipped: s.checkSkips.contains(block.id),
    );
  }

  // 방금 끝난 일정의 활동이 아직 이어지면 끝났는지 묻는다(휴식은 묻지 않는다).
  final prev = blocks.reversed.where((b) => !b.end.isAfter(now)).firstOrNull;
  if (prev != null && current != null && current != Activity.rest && current == expectedActivity(prev)) {
    final after = diffMin(now, prev.end);
    if (after <= _overWindow) {
      return NowCheck(
        kind: CheckKind.over,
        block: prev,
        expected: current,
        current: current,
        currentMinutes: currentMinutes,
        minutes: after,
        next: next,
        skipped: s.checkSkips.contains('${prev.id}:over'),
      );
    }
  }
  return NowCheck(kind: CheckKind.next, next: next, current: current, currentMinutes: currentMinutes, minutes: next == null ? 0 : diffMin(next.start, now));
}
