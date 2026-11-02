// 휴대폰에 맡길 알림·알람 목록. 순수 함수다(Flutter 의존 없음).
// 앱이 꺼져 있어도 울리도록 기기(안드로이드 AlarmManager·알림)에 예약할 것을 상태에서 계산하고,
// lib/platform/device_sync.dart가 이 목록대로 기기 예약을 맞춘다(없는 것은 지우고, 바뀐 것은 다시 예약).
//
// - 지금 일정 알림(nowNotice): 웹 src/ui/notify.ts의 noticeFor와 같은 문구.
// - 일정 시작 알림(scheduledNotices): 앱이 꺼져 있어도 일정이 시작되면 '기록하기' 버튼이 있는 알림을 띄운다.
// - 기상·취침 알람(deviceAlarms): Store.dueAlarms와 같은 규칙(끈 알람·기록한 기상은 다시 울리지 않고, 다시 울림 시각을 따른다).

import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import 'derive.dart';
import 'now_check.dart';
import 'state.dart';
import 'store.dart' show RingKind;

/// 알림 하나(지금 일정 또는 예약).
class DeviceNotice {
  const DeviceNotice({required this.title, required this.body, this.activity, this.skipId, this.blockStart, this.silent = false, this.until, this.open});
  final String title;
  final String body;

  /// '기록하기'를 누르면 시작할 활동(없으면 버튼 없음).
  final Activity? activity;

  /// '지금은 안 해요'로 넘길 일정 조각 id.
  final String? skipId;

  /// 일정이 시작한 시각. 늦게 누르면 이 시각부터 기록한다.
  final DateTime? blockStart;

  /// 소리·진동 없이(조용히 바꾸기).
  final bool silent;

  /// 이 시각이 지나면 알림을 거둔다(오래된 알림이 남지 않게).
  final DateTime? until;

  /// 누르면 열 화면('evening' = 저녁 확인).
  final String? open;

  String get signature => '$title|$body|${activity?.name}|$skipId|${blockStart?.millisecondsSinceEpoch}|$silent|${until?.millisecondsSinceEpoch}|$open';
}

/// 예약 알림: 정해진 시각에 기기가 띄운다.
class ScheduledNotice {
  const ScheduledNotice({required this.id, required this.at, required this.notice});
  final int id;
  final DateTime at;
  final DeviceNotice notice;
}

/// 기기 알람(앱이 꺼져 있어도 울림).
class DeviceAlarm {
  const DeviceAlarm({required this.id, required this.key, required this.kind, required this.at, required this.title, required this.body});
  final int id;

  /// Store가 쓰는 알람 열쇠('YYYY-MM-DD|wake' 등).
  final String key;
  final RingKind kind;
  final DateTime at;
  final String title;
  final String body;
}

String _act(Activity? a) => a?.label ?? '기록 없음';

/// 지금 일정 알림 문구. 웹 noticeFor와 같다.
DeviceNotice? nowNotice(NowCheck c) {
  final next = c.next == null ? '' : ' · 다음 ${formatHm(c.next!.start)} ${c.next!.title}';
  final b = c.block;
  switch (c.kind) {
    case CheckKind.due when b != null:
      final exp = _act(c.expected);
      final cur = c.current;
      return DeviceNotice(
        title: '${formatHm(b.start)} ${b.title} 시간이에요',
        body: cur != null
            ? "지금 기록은 ${cur.label}${hasBatchim(cur.label) ? '이에요' : '예요'}. $exp${objectParticle(exp)} 시작했으면 '기록하기'를 눌러 주세요"
            : "시작했으면 '기록하기'를 눌러 주세요",
        activity: c.expected,
        skipId: b.id,
        blockStart: b.start,
        silent: c.skipped,
        until: b.end,
      );
    case CheckKind.over when b != null:
      return DeviceNotice(
        title: '${b.title} 끝났어요?',
        body: "끝났으면 '기록하기'를 눌러 휴식으로 바꿔 주세요$next",
        activity: Activity.rest,
        skipId: '${b.id}:over',
        blockStart: b.end,
        silent: c.skipped,
        until: addMin(b.end, 45),
      );
    case CheckKind.ok when b != null:
      return DeviceNotice(title: '지금 ${b.title} · ${formatHm(b.start)}–${formatHm(b.end)}', body: '${_act(c.current)} 기록 중$next', silent: true, until: b.end);
    case CheckKind.next when c.next != null:
      return DeviceNotice(title: '다음 ${formatHm(c.next!.start)} ${c.next!.title}', body: '시작하면 알려 드릴게요', silent: true, until: c.next!.start);
    default:
      return null;
  }
}

bool _recording(AppState s) => s.observation?.phase == ObservationPhase.recording;

/// 날짜 열쇠로 만든 알림·알람 번호(같은 날 같은 종류는 늘 같은 번호).
int _dayId(String day, int slot) => (int.parse(day.replaceAll('-', '')) % 1000000) * 100 + slot;

/// 앱이 꺼져 있어도 일정이 시작하면 띄울 알림(지금부터 [horizon] 안). 웹에는 없는 앱 전용 기능.
List<ScheduledNotice> scheduledNotices(AppState s, DateTime now, {Duration horizon = const Duration(hours: 24)}) {
  if (!s.onboarded || _recording(s) || !s.notify.enabled || !s.notify.remind) return const [];
  final obs = s.observation;
  final until = now.add(horizon);
  final out = <ScheduledNotice>[];
  for (final day in [dateKey(now), dateKey(addDays(now, 1))]) {
    if (obs != null && day.compareTo(obs.day1) <= 0) continue; // 관찰 중에는 일정이 없다
    final plan = planFor(s, day, now).plan;
    var slot = 10;
    for (final b in plan.blocks) {
      final a = expectedActivity(b);
      slot++;
      if (a == null || !b.start.isAfter(now) || b.start.isAfter(until) || s.checkSkips.contains(b.id)) continue;
      out.add(ScheduledNotice(
        id: _dayId(day, slot),
        at: b.start,
        notice: DeviceNotice(
          title: '${formatHm(b.start)} ${b.title} 시간이에요',
          body: "${a.label}${objectParticle(a.label)} 시작했으면 '기록하기'를 눌러 주세요",
          activity: a,
          skipId: b.id,
          blockStart: b.start,
          until: b.end,
        ),
      ));
    }
  }
  // 저녁 확인 알림: 21시(일찍 자는 날은 취침 1시간 전). 오늘 확인을 마쳤으면 보내지 않는다.
  final today = dateKey(now);
  if (!s.eveningDone.contains(today) && (obs == null || today.compareTo(obs.day1) > 0)) {
    var at = DateTime(now.year, now.month, now.day, 21);
    final bed = addMin(planFor(s, dateKey(addDays(now, 1)), now).plan.bedTonight, -60);
    if (bed.isBefore(at)) at = bed;
    if (at.isAfter(now)) {
      out.add(ScheduledNotice(
        id: _dayId(today, 99),
        at: at,
        notice: DeviceNotice(title: '오늘 하루 확인 · 1분', body: '일정대로 했으면 한 번에 끝나요. 다르게 한 것만 고쳐요', open: 'evening', until: DateTime(now.year, now.month, now.day, 23, 59)),
      ));
    }
  }
  return out;
}

/// 기기에 맡길 기상·취침 알람. Store.dueAlarms와 같은 규칙으로, 아직 오지 않은 것만.
List<DeviceAlarm> deviceAlarms(AppState s, DateTime now) {
  if (!s.onboarded || _recording(s)) return const [];
  final obs = s.observation;
  final out = <DeviceAlarm>[];
  DateTime? when(String key, DateTime at) {
    final a = s.alarms[key];
    if (a?.done ?? false) return null;
    final t = a?.snoozeUntil != null && a!.snoozeUntil!.isAfter(at) ? a.snoozeUntil! : at;
    return t.isAfter(now) ? t : null;
  }

  // 기상: 오늘(아직 안 울렸으면)과 내일
  for (final day in [dateKey(now), dateKey(addDays(now, 1))]) {
    if (obs != null && day.compareTo(obs.day1) <= 0) continue;
    if (wakeRecord(s, day) != null) continue;
    final plan = planFor(s, day, now).plan;
    final key = '$day|wake';
    final at = when(key, plan.wake);
    if (at == null) continue;
    out.add(DeviceAlarm(id: _dayId(day, 1), key: key, kind: RingKind.wake, at: at, title: '기상 ${formatHm(plan.wake)}', body: '일어났으면 끄기를 눌러 주세요. 끄면 기상으로 기록해요'));
  }
  // 취침: 오늘 밤(내일 일정 기준)과 그다음 밤
  for (final day in [dateKey(addDays(now, 1)), dateKey(addDays(now, 2))]) {
    final plan = planFor(s, day, now).plan;
    final key = '$day|bed';
    final at = when(key, plan.bedTonight);
    if (at == null) continue;
    out.add(DeviceAlarm(id: _dayId(day, 2), key: key, kind: RingKind.bed, at: at, title: '취침 ${formatHm(plan.bedTonight)}', body: '잘 준비가 됐으면 앱에서 수면을 눌러 주세요'));
    break; // 다음 취침 하나만
  }
  return out;
}

/// 홈 화면 위젯 둘째 줄: 다음 일정과 오늘 진행도(예: '다음 12:00 점심 식사 · 오늘 습관 2/5').
String widgetLine(AppState s, DateTime now) {
  if (!s.onboarded) return '앱에서 처음 설정을 마쳐 주세요';
  if (_recording(s)) return '오늘은 하루를 그대로 기록해요';
  final plan = planFor(s, dateKey(now), now).plan;
  final next = plan.blocks.where((b) => b.start.isAfter(now) && b.activity != Activity.sleep).firstOrNull;
  final p = todayProgress(s, now);
  final parts = [
    next == null ? '오늘 남은 일정 없음' : '다음 ${formatHm(next.start)} ${next.title}',
    if (p.total > 0) '오늘 습관 ${p.achieved}/${p.total}',
  ];
  return parts.join(' · ');
}
