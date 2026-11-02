// 기록 시각 고치기: 제때 누르지 못한 기록의 시작·끝 시각을 바꾼다.
// 겹치는 앞뒤 기록은 맞닿게 줄이고, 통째로 덮이는 기록이 있으면 바꾸지 않고 이유를 돌려준다.
// 순수 함수다. 저장소(store.ts)의 retimeLog·tapAt가 이걸 쓴다. Flutter는 lib/app/log_edit.dart(같은 규칙·문구).

import { objectParticle } from '../engine/coaching';
import { type ActivityLog, ACTIVITY_LABEL, diffMin, formatHm } from '../engine/models';

export type RetimeResult = { ok: true; logs: ActivityLog[] } | { ok: false; error: string };

/** id 기록을 start~end로 바꾼다. end가 null이면 지금 진행 중인 기록(마지막 기록만 가능). */
export function retimeLogs(logs: ActivityLog[], id: string, start: Date, end: Date | null, now: Date): RetimeResult {
  const target = logs.find((l) => l.id === id);
  if (!target) return { ok: false, error: '기록을 찾지 못했어요' };
  if (end == null && target.end != null) return { ok: false, error: '끝난 기록은 끝 시각이 필요해요' };
  if (start.getTime() > now.getTime()) return { ok: false, error: '시작 시각이 지금보다 늦어요' };
  if (end && end.getTime() > now.getTime()) return { ok: false, error: '끝 시각이 지금보다 늦어요' };
  if (end && diffMin(end, start) < 1) return { ok: false, error: '끝 시각은 시작보다 1분 이상 뒤여야 해요' };
  if (end == null && diffMin(now, start) < 0) return { ok: false, error: '시작 시각이 지금보다 늦어요' };

  const s = start.getTime();
  const e = (end ?? now).getTime();
  const out: ActivityLog[] = [];
  for (const l of logs) {
    if (l.id === id) {
      out.push({ ...l, start, end, confirmed: true });
      continue;
    }
    const ls = l.start.getTime();
    const le = (l.end ?? now).getTime();
    if (le <= s || ls >= e) {
      out.push(l);
      continue;
    }
    // 겹친다: 앞쪽만 남거나 뒤쪽만 남게 줄인다. 둘 다 1분이 안 되면 덮는 것으로 본다.
    const keepHead = diffMin(new Date(s), l.start) >= 1;
    const keepTail = l.end != null && diffMin(l.end, new Date(e)) >= 1;
    if (l.end == null) {
      return { ok: false, error: `지금 기록 중인 ${ACTIVITY_LABEL[l.activity]}${objectParticle(ACTIVITY_LABEL[l.activity])} 덮어요. 끝 시각을 더 이르게 해 주세요` };
    }
    if (keepHead && !keepTail) out.push({ ...l, end: new Date(s) });
    else if (keepTail && !keepHead) out.push({ ...l, start: new Date(e) });
    else if (keepHead && keepTail) {
      // 바꾼 기록이 다른 기록 한가운데로 들어가면 앞쪽만 남기고 뒤쪽은 버리지 않도록 막는다.
      return { ok: false, error: `${ACTIVITY_LABEL[l.activity]} 기록(${formatHm(l.start)}–${formatHm(l.end)}) 한가운데예요. 그 기록을 먼저 고쳐 주세요` };
    } else {
      return { ok: false, error: `${ACTIVITY_LABEL[l.activity]} 기록(${formatHm(l.start)}–${formatHm(l.end)})을 통째로 덮어요. 그 기록을 먼저 지워 주세요` };
    }
  }
  out.sort((a, b) => a.start.getTime() - b.start.getTime());
  return { ok: true, logs: out };
}
