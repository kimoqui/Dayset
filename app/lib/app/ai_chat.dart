// 말로 일정 바꾸기를 서버 AI(Claude)로 읽기. 서버 함수: 저장소 루트 supabase/functions/dayset-chat.
// AI는 해석만 한다: 돌려받은 목록을 여기서 검사해 ScheduleEdit으로 바꾸고, 화면이 미리보기 → '바꾸기'를 거친다.
// 로그인하지 않았거나 서버·AI가 안 되면 null → 화면은 기기 안 규칙(chat_command.dart)으로 읽는다.
// 웹 버전 src/app/aiChat.ts와 같은 규칙·같은 문구.

import '../core/model/models.dart';
import 'chat_command.dart';
import 'derive.dart';
import 'edits.dart';
import 'state.dart';

const _week = ['일', '월', '화', '수', '목', '금', '토'];
String _local(DateTime d) => '${dateKey(d)}T${formatHm(d)}';

/// AI에 넘길 일정 요약(오늘부터 사흘 습관·기상, 7일 캘린더). 기록·건강 정보는 넣지 않는다.
Map<String, Object?> aiContext(AppState s, DateTime now) {
  final titles = habitTitles(s);
  final until = addDays(now, 8);
  final from = now.subtract(const Duration(days: 1));
  return {
    'now': _local(now),
    'weekday': _week[now.weekday % 7],
    'habits': titles,
    'days': [
      for (var i = 0; i < 3; i++)
        () {
          final day = dateKey(addDays(now, i));
          return {
            'day': day,
            'wake': formatHm(planFor(s, day, now).plan.wake),
            'habits': [
              for (final t in titles)
                if (habitOn(s, day, t) case final h?) {'title': t, 'start': formatClock(h.start.minutes), 'minutes': h.minutes},
            ],
          };
        }(),
    ],
    'events': [
      for (final e in s.events.where((e) => e.end.isAfter(from) && e.start.isBefore(until)).take(40))
        {'id': e.id, 'title': e.title, 'start': _local(e.start), 'end': _local(e.end), 'imported': e.source != null},
    ],
    'tasks': [for (final t in s.tasks.where((t) => !t.done).take(20)) t.title],
  };
}

final _hmRe = RegExp(r'^(\d{1,2}):(\d{2})$');
final _dayRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _dtRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{1,2}):(\d{2})');

int? _hm(Object? v) {
  final m = v is String ? _hmRe.firstMatch(v) : null;
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final mi = int.parse(m[2]!);
  return h < 24 && mi < 60 ? h * 60 + mi : null;
}

DateTime? _dt(Object? v) {
  final m = v is String ? _dtRe.firstMatch(v) : null;
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!));
}

String _day(Object? v, String fallback) => v is String && _dayRe.hasMatch(v) ? v : fallback;
String _text(Object? v, [int max = 60]) {
  if (v is! String) return '';
  final t = v.trim();
  return t.length > max ? t.substring(0, max) : t;
}

int? _num(Object? v, int min, int max) => v is num && v >= min && v <= max ? v.round() : null;

/// AI가 돌려준 값을 검사해 바꾸기 목록으로. 이상한 항목은 버린다. 읽을 것이 없으면 null.
ChatReading? readAiReply(Object? raw, AppState s, DateTime now) {
  if (raw is! Map) return null;
  final reply = _text(raw['reply'], 300);
  final list = raw['edits'] is List ? (raw['edits'] as List).take(8) : const [];
  final today = dateKey(now);
  final titles = habitTitles(s);
  final edits = <ScheduleEdit>[];
  final dropped = <String>[];
  for (final it in list) {
    if (it is! Map) continue;
    final scope = it['scope'] == 'every' ? EditScope.every : EditScope.day;
    final d = _day(it['day'], today);
    if (d.compareTo(today) < 0) {
      dropped.add('지난 날');
      continue;
    }
    switch (it['kind']) {
      case 'habit':
        final title = _text(it['title']);
        if (!titles.contains(title)) {
          dropped.add(title.isEmpty ? '습관' : title);
          break;
        }
        final start = _hm(it['start']);
        final minutes = _num(it['minutes'], 5, 240);
        if (it['skip'] == true) {
          edits.add(HabitChange(day: d, title: title, patch: const HabitEdit(skip: true), scope: scope));
        } else if (start != null || minutes != null) {
          edits.add(HabitChange(day: d, title: title, patch: HabitEdit(start: start, minutes: minutes), scope: scope));
        }
      case 'wake':
        final m = _hm(it['start']);
        if (m != null && m >= 3 * 60 && m <= 13 * 60) {
          edits.add(WakeChange(day: d, minutes: m, scope: scope));
        } else {
          dropped.add('기상 시각');
        }
      case 'event-add':
        final title = _text(it['title']);
        final start = _dt(it['start']);
        final end = _dt(it['end']);
        if (title.isNotEmpty && start != null && end != null && end.isAfter(start) && start.isAfter(now.subtract(const Duration(hours: 1)))) {
          edits.add(EventAdd(title: title, start: start, end: end));
        } else {
          dropped.add(title.isEmpty ? '일정' : title);
        }
      case 'event-move':
        final ev = s.events.where((x) => x.id == it['id']).firstOrNull;
        final start = _dt(it['start']);
        final end = _dt(it['end']);
        if (ev != null && ev.source == null && start != null && end != null && end.isAfter(start)) {
          edits.add(EventMove(id: ev.id, start: start, end: end));
        } else {
          dropped.add(ev?.title ?? '일정');
        }
      case 'event-delete':
        final ev = s.events.where((x) => x.id == it['id']).firstOrNull;
        if (ev != null && ev.source == null) {
          edits.add(EventDelete(id: ev.id));
        } else {
          dropped.add(ev?.title ?? '일정');
        }
      case 'task-add':
        final title = _text(it['title']);
        final minutes = _num(it['minutes'], 5, 600) ?? 60;
        final type = TaskType.values.where((t) => t.name == it['taskType']).firstOrNull ?? TaskType.work;
        final due = it['due'];
        final dueAt = due is String && _dayRe.hasMatch(due) && due.compareTo(today) >= 0 ? fromKey(due).add(const Duration(hours: 23)) : null;
        if (title.isNotEmpty) edits.add(TaskAdd(title: title, minutes: minutes, type: type, dueAt: dueAt));
      case 'reset':
        edits.add(ResetDay(day: d));
      default:
        break;
    }
  }
  if (reply.isEmpty && edits.isEmpty && dropped.isEmpty) return null;
  final note = dropped.isEmpty ? '' : ' 바꿀 수 없는 것은 뺐어요: ${{...dropped}.join(', ')}.';
  return ChatReading(edits: edits, reply: (reply.isNotEmpty ? reply : (edits.isNotEmpty ? '이렇게 바꿀까요?' : '그대로 둘게요.')) + note, unknown: dropped);
}
