// 채팅으로 일정 바꾸기: "내일 운동 7시로 옮겨줘", "오늘 점심 30분 늦춰", "금요일 3시 치과 추가" 같은 말을
// 일정 바꾸기 목록(edits.dart의 ScheduleEdit)으로 읽는다. 서버·AI 없이 기기 안에서 규칙으로 읽는다.
// 같은 목록을 나중에 서버 AI(Claude)가 만들어 주면 화면·적용 흐름은 그대로 쓴다.
// 바로 바꾸지 않는다: 화면이 바뀌는 내용을 보여 주고, 사용자가 '바꾸기'를 눌러야 적용한다.
// 웹 버전 src/app/chatCommand.ts와 같은 규칙·같은 문구.

import 'dart:math' as math;

import '../core/model/models.dart';
import 'edits.dart';
import 'goal_text.dart';
import 'nlp.dart';
import 'state.dart';

class ChatReading {
  const ChatReading({required this.edits, required this.reply, required this.unknown});
  final List<ScheduleEdit> edits;

  /// 읽은 것을 설명하는 답(바꿀 것이 없으면 도움말).
  final String reply;

  /// 읽지 못한 부분.
  final List<String> unknown;
}

const chatExamples = ['내일 운동 7시로 옮겨줘', '오늘 점심 30분 늦춰', '금요일 3시 치과 1시간 추가', '내일 6시 반에 깨워줘', '오늘 운동 빼줘', '할 일 보고서 2시간 추가'];

final _skip = RegExp(r'빼|취소|건너뛰|없애|안\s*해|안\s*할|쉴래|쉬어|쉴게|생략|패스|지워');
final _reset = RegExp(r'원래대로|되돌려|초기화|다시\s*원래');
final _every = RegExp(r'매일|항상|앞으로|계속|매번|평소');
final _add = RegExp(r'추가|넣어|넣기|잡아|등록|만들어|생겼|있어');
final _wake = RegExp(r'기상|알람|일어나|일어날|깨워|깨우|깨줘');
final _later = RegExp(r'늦|미뤄|미루|뒤로|나중');
final _earlier = RegExp(r'일찍|당겨|앞당|빨리|앞으로');
const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

/// 날짜 말: 오늘·내일·모레·글피·요일·M월 D일. 없으면 null.
String? _readDay(String text, DateTime now) {
  final today = dayStart(now);
  final m1 = RegExp(r'(오늘|내일|모레|글피)').firstMatch(text);
  if (m1 != null) return dateKey(addDays(today, const {'오늘': 0, '내일': 1, '모레': 2, '글피': 3}[m1[1]]!));
  final m2 = RegExp(r'(이번\s*주|다음\s*주)?\s*([월화수목금토일])요일').firstMatch(text);
  if (m2 != null) {
    final target = _weekdays.indexOf(m2[2]!);
    final mon = addDays(today, -(today.weekday - 1));
    var d = addDays(mon, ((target + 6) % 7) + ((m2[1]?.startsWith('다음') ?? false) ? 7 : 0));
    if (m2[1] == null && d.isBefore(today)) d = addDays(d, 7);
    return dateKey(d);
  }
  final m3 = RegExp(r'(\d{1,2})\s*월\s*(\d{1,2})\s*일').firstMatch(text);
  if (m3 != null) {
    var d = DateTime(now.year, int.parse(m3[1]!), int.parse(m3[2]!));
    if (d.isBefore(today)) d = DateTime(now.year + 1, int.parse(m3[1]!), int.parse(m3[2]!));
    return dateKey(d);
  }
  return null;
}

enum _AmPm { am, pm }

typedef _Clock = ({int h, int m, _AmPm? ampm});

/// 'N시(반|M분)' 또는 'H:MM'. 낮·밤 말이 있으면 반영, 없으면 null(쓰는 곳에서 가까운 쪽으로 고른다).
_Clock? _readClock(String text) {
  final m = RegExp(r'(오전|오후|아침|저녁|밤|새벽|낮)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(?:(반)|(\d{1,2})\s*분)?)(?!\s*간)').firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m[2]!);
  final min = m[3] != null ? int.parse(m[3]!) : (m[4] != null ? 30 : (m[5] != null ? int.parse(m[5]!) : 0));
  if (h > 24 || min > 59) return null;
  final w = m[1];
  return (h: h, m: min, ampm: w == null ? null : (RegExp(r'오전|아침|새벽').hasMatch(w) ? _AmPm.am : _AmPm.pm));
}

/// 낮·밤 말이 없으면 기준 시각(지금 값)에 가까운 쪽(오전·오후)으로.
int _resolveClock(_Clock c, int near) {
  if (c.ampm == _AmPm.am) return (c.h % 12) * 60 + c.m;
  if (c.ampm == _AmPm.pm) return ((c.h % 12) + 12) * 60 + c.m;
  if (c.h > 12) return c.h * 60 + c.m;
  final a = (c.h % 12) * 60 + c.m;
  final p = a + 12 * 60;
  return (a - near).abs() <= (p - near).abs() ? a : p;
}

/// 'N분' 'N시간(반)' → 분
int? _readMinutes(String text) {
  final h = RegExp(r'(\d{1,2}(?:\.\d)?)\s*시간\s*(반)?(?:\s*(\d{1,2})\s*분)?').firstMatch(text);
  if (h != null) return (double.parse(h[1]!) * 60 + (h[2] != null ? 30 : 0) + (h[3] != null ? int.parse(h[3]!) : 0)).round();
  final m = RegExp(r'(\d{1,3})\s*분').firstMatch(text);
  return m != null ? int.parse(m[1]!) : null;
}

/// 이 말에서 가리키는 습관 이름(목표에 있는 것).
String? _habitTarget(String clause, AppState s) {
  final titles = habitTitles(s);
  for (final t in titles) {
    if (clause.contains(t)) return t;
  }
  final ex = s.goals.exercise?.title;
  if (ex != null && goalExercises.any((e) => e.$1.hasMatch(clause))) return ex;
  String? meal(String word) => titles.where((t) => t.startsWith(word)).firstOrNull;
  if (clause.contains('점심')) return meal('점심');
  // '아침 7시'·'저녁 8시'처럼 시각 앞의 말은 식사가 아니다.
  if (RegExp(r'아침(?!\s*\d)').hasMatch(clause) && RegExp(r'아침\s*(식사|밥|먹)|조식|아침(?=\s|$|을|은|도)').hasMatch(clause)) return meal('아침');
  if (RegExp(r'저녁(?!\s*\d)').hasMatch(clause) && RegExp(r'저녁\s*(식사|밥|먹)|석식|저녁(?=\s|$|을|은|도)').hasMatch(clause)) return meal('저녁');
  return null;
}

String _cleanTitle(String t) => t
    .replaceAll(RegExp(r'(을|를)?\s*(추가|넣어|넣기|잡아|등록|만들어|생겼|있어)\S*'), ' ')
    .replaceAll(RegExp(r'(해\s*)?(줘|주세요|줄래|요)$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _eventKey(String t) => t.replaceAll(RegExp(r'\s+'), '');

final _split = RegExp(r'[,，\n]|그리고|(?<=[가-힣])(?:고|하고)\s+(?=\S*\s*(?:오늘|내일|모레|[월화수목금토일]요일|\d))');
final _durationRe = RegExp(r'\d{1,3}\s*분');

ChatReading interpretChat(String input, AppState s, DateTime now) {
  var text = nativeNumbers(input.trim());
  if (text.length > 300) text = text.substring(0, 300);
  final edits = <ScheduleEdit>[];
  final unknown = <String>[];
  if (text.isEmpty) return ChatReading(edits: edits, unknown: unknown, reply: _help());
  final today = dateKey(now);
  final allDay = _readDay(text, now);

  for (final raw in text.split(_split)) {
    final clause = raw.trim();
    if (clause.isEmpty) continue;
    final day = _readDay(clause, now) ?? allDay;
    final scope = _every.hasMatch(clause) ? EditScope.every : EditScope.day;
    final before = edits.length;

    // 1) 되돌리기
    if (_reset.hasMatch(clause) && _habitTarget(clause, s) == null) {
      edits.add(ResetDay(day: day ?? today));
      continue;
    }

    // 2) 기상
    if (_wake.hasMatch(clause)) {
      final d = day ?? (now.hour >= 12 ? dateKey(addDays(now, 1)) : today);
      final cur = _habitWake(s, d);
      final c = _readClock(clause);
      final shift = _readMinutes(clause);
      int? minutes;
      if (c != null) {
        minutes = c.ampm == _AmPm.pm && c.h < 12 ? (c.h + 12) * 60 + c.m : (c.h % 24) * 60 + c.m;
      } else if (shift != null && shift != 0 && _later.hasMatch(clause)) {
        minutes = cur + shift;
      } else if (shift != null && shift != 0 && _earlier.hasMatch(clause)) {
        minutes = cur - shift;
      }
      if (minutes != null) {
        edits.add(WakeChange(day: d, minutes: math.max(4 * 60, math.min(12 * 60, minutes)), scope: scope));
        continue;
      }
    }

    // 3) 습관(식사·운동)
    final title = _habitTarget(clause, s);
    if (title != null) {
      var d = day ?? today;
      final cur = habitOn(s, d, title) ?? habitOn(s, dateKey(addDays(now, 1)), title);
      // 날짜 말이 없고 오늘 그 습관이 이미 지났으면 내일로 본다.
      if (day == null && scope == EditScope.day && cur != null) {
        final startToday = addMin(dayStart(now), cur.start.minutes);
        if (diffMin(now, startToday) > cur.minutes) d = dateKey(addDays(now, 1));
      }
      if (_reset.hasMatch(clause)) {
        edits.add(ResetDay(day: d));
        continue;
      }
      if (_skip.hasMatch(clause)) {
        edits.add(HabitChange(day: d, title: title, patch: const HabitEdit(skip: true), scope: scope));
        continue;
      }
      int? start;
      int? length;
      final c = _readClock(clause.replaceAll(_durationRe, ''));
      final mins = _readMinutes(clause);
      if (c != null) start = _resolveClock(c, cur?.start.minutes ?? 12 * 60);
      final shifting = _later.hasMatch(clause) || _earlier.hasMatch(clause);
      if (mins != null && cur != null && shifting && c == null) {
        start = cur.start.minutes + (_later.hasMatch(clause) ? mins : -mins);
      } else if (mins != null && (RegExp(r'줄|늘|동안|만\b|으로|로\s*(바꿔|해)|길게|짧게').hasMatch(clause) || c != null)) {
        length = math.max(5, math.min(240, mins));
      }
      if (start != null) start = math.max(0, math.min(23 * 60 + 55, start));
      if (start != null || length != null) {
        edits.add(HabitChange(day: d, title: title, patch: HabitEdit(start: start, minutes: length), scope: scope));
        continue;
      }
    }

    // 4) 할 일 넣기
    if (RegExp(r'할\s*일|과제|숙제|공부|보고서|레포트|리포트').hasMatch(clause) && _add.hasMatch(clause)) {
      final mins = _readMinutes(clause) ?? 60;
      final type = RegExp(r'숙제|공부').hasMatch(clause)
          ? TaskType.homework
          : RegExp(r'과제|레포트|리포트').hasMatch(clause)
              ? TaskType.assignment
              : RegExp(r'개인|집안|장보기').hasMatch(clause)
                  ? TaskType.personal
                  : TaskType.work;
      final name = _cleanTitle(clause
          .replaceAll(RegExp(r'(오늘|내일|모레|[월화수목금토일]요일)(까지)?'), ' ')
          .replaceAll(RegExp(r'할\s*일(에|로|으로)?'), ' ')
          .replaceAll(RegExp(r'\d{1,2}(?:\.\d)?\s*시간\s*(반)?|\d{1,3}\s*분'), ' '));
      edits.add(TaskAdd(
        title: name.isEmpty ? '할 일' : name,
        minutes: math.max(10, math.min(600, mins)),
        type: type,
        dueAt: day != null ? addMin(fromKey(day), 23 * 60) : null,
      ));
      continue;
    }

    // 5) 이미 있는 캘린더 일정 옮기기·지우기
    final ck = _eventKey(clause);
    final ev = s.events.where((e) => e.source == null && e.end.isAfter(now)).where((e) {
      final k = _eventKey(e.title);
      return ck.contains(k) || (k.length >= 2 && ck.contains(k.substring(0, 2)));
    }).firstOrNull;
    if (ev != null && !_add.hasMatch(clause)) {
      if (_skip.hasMatch(clause)) {
        edits.add(EventDelete(id: ev.id));
        continue;
      }
      final len = diffMin(ev.end, ev.start);
      final c = _readClock(clause.replaceAll(_durationRe, ''));
      final mins = _readMinutes(clause);
      final evClock = ev.start.hour * 60 + ev.start.minute;
      DateTime? start;
      if (c != null) {
        final base = day != null ? fromKey(day) : dayStart(ev.start);
        start = addMin(base, _resolveClock(c, evClock));
      } else if (mins != null && mins != 0 && _later.hasMatch(clause)) {
        start = addMin(ev.start, mins);
      } else if (mins != null && mins != 0 && _earlier.hasMatch(clause)) {
        start = addMin(ev.start, -mins);
      } else if (day != null && day != dateKey(ev.start)) {
        start = addMin(fromKey(day), evClock);
      }
      if (start != null) {
        edits.add(EventMove(id: ev.id, start: start, end: addMin(start, len)));
        continue;
      }
    }

    // 6) 새 캘린더 일정
    final p = parseEventText(_cleanTitle(clause), now);
    if (p != null && (_add.hasMatch(clause) || title == null)) {
      edits.add(EventAdd(title: p.title, start: p.start, end: p.end));
      continue;
    }

    if (edits.length == before) unknown.add(clause);
  }

  final reply = edits.isNotEmpty
      ? (unknown.isNotEmpty ? '이렇게 바꿀게요. ‘${unknown.join('’, ‘')}’는 읽지 못했어요.' : '이렇게 바꿀게요. 맞으면 바꾸기를 눌러 주세요.')
      : _help(unknown);
  return ChatReading(edits: edits, unknown: unknown, reply: reply);
}

int _habitWake(AppState s, String day) => s.overrides[day]?.wake ?? s.goals.wake.minutes;

String _help([List<String> unknown = const []]) =>
    '${unknown.isNotEmpty ? '어떻게 바꿀지 읽지 못했어요. ' : ''}이렇게 말해 주세요: ‘내일 운동 7시로 옮겨줘’, ‘오늘 점심 30분 늦춰’, ‘금요일 3시 치과 추가’, ‘내일 6시 반에 깨워줘’, ‘오늘 운동 빼줘’.';
