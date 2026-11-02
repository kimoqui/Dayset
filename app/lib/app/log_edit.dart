// 기록 시각 고치기: 제때 누르지 못한 기록의 시작·끝 시각을 바꾼다.
// 겹치는 앞뒤 기록은 맞닿게 줄이고, 통째로 덮이는 기록이 있으면 바꾸지 않고 이유를 돌려준다.
// 순수 함수다. Store.retimeLog·tapAt가 쓴다. 웹 버전 src/app/logEdit.ts와 같은 규칙·같은 문구.

import '../core/engine/coaching.dart';
import '../core/model/models.dart';

/// 고친 기록 목록, 또는 고치지 못한 이유.
typedef RetimeResult = ({List<ActivityLog>? logs, String? error});

/// id 기록을 start~end로 바꾼다. end가 null이면 지금 진행 중인 기록(마지막 기록만 가능).
RetimeResult retimeLogs(List<ActivityLog> logs, String id, DateTime start, DateTime? end, DateTime now) {
  RetimeResult fail(String e) => (logs: null, error: e);
  final target = logs.where((l) => l.id == id).firstOrNull;
  if (target == null) return fail('기록을 찾지 못했어요');
  if (end == null && target.end != null) return fail('끝난 기록은 끝 시각이 필요해요');
  if (start.isAfter(now)) return fail('시작 시각이 지금보다 늦어요');
  if (end != null && end.isAfter(now)) return fail('끝 시각이 지금보다 늦어요');
  if (end != null && diffMin(end, start) < 1) return fail('끝 시각은 시작보다 1분 이상 뒤여야 해요');

  final s = start;
  final e = end ?? now;
  final out = <ActivityLog>[];
  for (final l in logs) {
    if (l.id == id) {
      out.add(end == null ? l.copyWith(start: start, clearEnd: true, confirmed: true) : l.copyWith(start: start, end: end, confirmed: true));
      continue;
    }
    final le = l.end ?? now;
    if (!le.isAfter(s) || !l.start.isBefore(e)) {
      out.add(l);
      continue;
    }
    final label = l.activity.label;
    if (l.end == null) return fail('지금 기록 중인 $label${objectParticle(label)} 덮어요. 끝 시각을 더 이르게 해 주세요');
    // 겹친다: 앞쪽만 남거나 뒤쪽만 남게 줄인다. 둘 다 1분이 안 되면 덮는 것으로 본다.
    final keepHead = diffMin(s, l.start) >= 1;
    final keepTail = diffMin(l.end!, e) >= 1;
    if (keepHead && !keepTail) {
      out.add(l.copyWith(end: s));
    } else if (keepTail && !keepHead) {
      out.add(l.copyWith(start: e));
    } else if (keepHead && keepTail) {
      return fail('$label 기록(${formatHm(l.start)}–${formatHm(l.end!)}) 한가운데예요. 그 기록을 먼저 고쳐 주세요');
    } else {
      return fail('$label 기록(${formatHm(l.start)}–${formatHm(l.end!)})을 통째로 덮어요. 그 기록을 먼저 지워 주세요');
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return (logs: out, error: null);
}
