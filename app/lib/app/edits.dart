// 일정 바꾸기: 일정 탭에서 직접 고치거나, 채팅으로 말한 것을 같은 '바꾸기' 목록으로 만들어 적용한다.
// 모두 순수 함수다(상태를 받아 새 상태를 돌려준다). Store는 이걸 적용하고 남은 일정을 다시 짠다.
// 웹 버전 src/app/edits.ts와 같은 규칙·같은 문구.
//
// 바꿀 수 있는 것
//  - 습관(식사·운동): 그날만(시작·길이·빼기) 또는 매일(목표 자체)
//  - 기상 시각: 그날만 또는 매일
//  - 캘린더 일정: 넣기·옮기기·지우기
//  - 할 일: 넣기
//  - 그날 바꾼 것 되돌리기
// 잠금·캘린더에서 가져온 일정·수면 블록은 직접 움직이지 않는다(기상·습관 목표를 바꾸면 엔진이 다시 짠다).

import '../core/engine/schedule_builder.dart';
import '../core/model/models.dart';
import 'derive.dart';
import 'state.dart';

enum EditScope { day, every }

/// 바꾸기 하나. 웹 ScheduleEdit과 같은 종류.
sealed class ScheduleEdit {
  const ScheduleEdit();

  /// 웹과 같은 종류 이름(지표에 남긴다).
  String get kind;
}

class HabitChange extends ScheduleEdit {
  const HabitChange({required this.day, required this.title, required this.patch, required this.scope});
  final String day;
  final String title;
  final HabitEdit patch;
  final EditScope scope;
  @override
  String get kind => 'habit';
}

class WakeChange extends ScheduleEdit {
  const WakeChange({required this.day, required this.minutes, required this.scope});
  final String day;
  final int minutes;
  final EditScope scope;
  @override
  String get kind => 'wake';
}

class EventAdd extends ScheduleEdit {
  const EventAdd({required this.title, required this.start, required this.end});
  final String title;
  final DateTime start;
  final DateTime end;
  @override
  String get kind => 'event-add';
}

class EventMove extends ScheduleEdit {
  const EventMove({required this.id, required this.start, required this.end});
  final String id;
  final DateTime start;
  final DateTime end;
  @override
  String get kind => 'event-move';
}

class EventDelete extends ScheduleEdit {
  const EventDelete({required this.id});
  final String id;
  @override
  String get kind => 'event-delete';
}

class TaskAdd extends ScheduleEdit {
  const TaskAdd({required this.title, required this.minutes, required this.type, this.dueAt});
  final String title;
  final int minutes;
  final TaskType type;
  final DateTime? dueAt;
  @override
  String get kind => 'task-add';
}

class ResetDay extends ScheduleEdit {
  const ResetDay({required this.day});
  final String day;
  @override
  String get kind => 'reset';
}

int _seq = 0;
String _id(String p) => '$p-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${(_seq++).toRadixString(36)}';

/// 오늘·내일·모레·M월 D일 요일
String dayLabel(String day, DateTime now) {
  if (day == dateKey(now)) return '오늘';
  if (day == dateKey(addDays(now, 1))) return '내일';
  if (day == dateKey(addDays(now, 2))) return '모레';
  return koreanDate(fromKey(day));
}

/// 이 날 이 습관의 지금 값(바꾼 값 반영). 없으면 null.
HabitSlot? habitOn(AppState s, String day, String title) {
  final g = effectiveGoals(s, day);
  return [...g.meals, if (g.exercise != null) g.exercise!].where((h) => h.title == title).firstOrNull;
}

/// 목표에 있는 습관 이름(식사·운동).
List<String> habitTitles(AppState s) => [for (final m in s.goals.meals) m.title, if (s.goals.exercise != null) s.goals.exercise!.title];

FixedEvent? _event(AppState s, String id) => s.events.where((x) => x.id == id).firstOrNull;

/// 사람이 읽는 설명.
String describeEdit(AppState s, ScheduleEdit e, DateTime now) {
  switch (e) {
    case HabitChange():
      final when = e.scope == EditScope.every ? '매일' : dayLabel(e.day, now);
      if (e.patch.skip) return e.scope == EditScope.every ? '${e.title}: 앞으로 일정에서 빼기' : '$when ${e.title}: 이날은 빼기';
      final parts = [
        if (e.patch.start != null) '${formatClock(e.patch.start!)} 시작',
        if (e.patch.minutes != null) formatDuration(e.patch.minutes!),
      ];
      return '$when ${e.title}: ${parts.join(' · ')}';
    case WakeChange():
      return '${e.scope == EditScope.every ? '매일' : dayLabel(e.day, now)} 기상 알람: ${formatClock(e.minutes)}';
    case EventAdd():
      return '캘린더에 넣기: ${dayLabel(dateKey(e.start), now)} ${formatHm(e.start)}–${formatHm(e.end)} ${e.title}';
    case EventMove():
      return '${_event(s, e.id)?.title ?? '일정'} 옮기기: ${dayLabel(dateKey(e.start), now)} ${formatHm(e.start)}–${formatHm(e.end)}';
    case EventDelete():
      return '${_event(s, e.id)?.title ?? '일정'} 지우기';
    case TaskAdd():
      return '할 일 넣기: ${e.title} · ${formatDuration(e.minutes)}${e.dueAt != null ? ' · ${dayLabel(dateKey(e.dueAt!), now)}까지' : ''}';
    case ResetDay():
      return '${dayLabel(e.day, now)} 바꾼 것 되돌리기';
  }
}

/// 하나 적용(순수).
AppState applyEdit(AppState s, ScheduleEdit e, DateTime now) {
  switch (e) {
    case HabitChange():
      if (e.scope == EditScope.every) {
        final g = s.goals;
        HabitSlot fix(HabitSlot h) => h.copyWith(start: e.patch.start != null ? ClockTime(e.patch.start!) : null, minutes: e.patch.minutes);
        final isEx = g.exercise?.title == e.title;
        final goals = isEx
            ? (e.patch.skip ? g.copyWith(clearExercise: true) : g.copyWith(exercise: fix(g.exercise!)))
            : g.copyWith(
                meals: e.patch.skip ? g.meals.where((m) => m.title != e.title).toList() : [for (final m in g.meals) m.title == e.title ? fix(m) : m],
              );
        // 매일로 바꾸면 그날만 바꾼 값은 지운다(헷갈리지 않게).
        final overrides = {
          for (final o in s.overrides.entries)
            o.key: o.value.habits.containsKey(e.title) ? o.value.copyWith(habits: {...o.value.habits}..remove(e.title)) : o.value,
        };
        return s.copyWith(goals: goals, overrides: overrides).bump();
      }
      final o = s.overrides[e.day] ?? const DayOverride();
      final prev = o.habits[e.title] ?? const HabitEdit();
      final next = e.patch.skip ? const HabitEdit(skip: true) : HabitEdit(start: e.patch.start ?? prev.start, minutes: e.patch.minutes ?? prev.minutes);
      return s.copyWith(overrides: {...s.overrides, e.day: o.copyWith(habits: {...o.habits, e.title: next})}).bump();
    case WakeChange():
      if (e.scope == EditScope.every) return s.copyWith(goals: s.goals.copyWith(wake: ClockTime(e.minutes)), correction: null).bump();
      final o = s.overrides[e.day] ?? const DayOverride();
      return s.copyWith(overrides: {...s.overrides, e.day: o.copyWith(wake: e.minutes)}).bump();
    case EventAdd():
      return s.copyWith(events: [...s.events, FixedEvent(id: _id('ev'), title: e.title, start: e.start, end: e.end)]).bump();
    case EventMove():
      return s.copyWith(events: [
        for (final x in s.events) x.id == e.id ? FixedEvent(id: x.id, title: x.title, start: e.start, end: e.end, source: x.source) : x,
      ]).bump();
    case EventDelete():
      return s.copyWith(events: s.events.where((x) => x.id != e.id).toList()).bump();
    case TaskAdd():
      final t = TaskItem(
        id: _id('task'),
        title: e.title,
        estMinutes: e.minutes,
        dueAt: e.dueAt ?? DateTime(now.year, now.month, now.day + 7, 23),
        type: e.type,
        priority: TaskPriority.normal,
        focus: focusByType(e.type),
        doneMinutes: 0,
        createdAt: now,
      );
      return s.copyWith(tasks: [...s.tasks, t]).bump();
    case ResetDay():
      final o = s.overrides[e.day];
      if (o == null) return s;
      return s.copyWith(overrides: {...s.overrides, e.day: DayOverride(dinnerShift: o.dinnerShift, notes: o.notes)}).bump();
  }
}

/// 바꾸기 목록이 닿는 날(일정을 다시 짤 날·미리 볼 날).
List<String> editDays(AppState s, List<ScheduleEdit> edits, DateTime now) {
  final today = dateKey(now);
  final tomorrow = dateKey(addDays(now, 1));
  final days = <String>{};
  for (final e in edits) {
    switch (e) {
      case HabitChange(:final scope, :final day) || WakeChange(:final scope, :final day):
        if (scope == EditScope.every) {
          days.addAll([today, tomorrow]);
        } else {
          days.add(day);
        }
      case ResetDay():
        days.add(e.day);
      case EventAdd():
        days.add(dateKey(e.start));
      case EventMove():
        days.add(dateKey(e.start));
        final old = _event(s, e.id);
        if (old != null) days.add(dateKey(old.start));
      case EventDelete():
        final old = _event(s, e.id);
        days.add(old != null ? dateKey(old.start) : today);
      case TaskAdd():
        days.addAll([today, tomorrow]);
    }
  }
  return days.where((d) => d.compareTo(today) >= 0).toList()..sort();
}

/// 저장해 둔 그날 일정을 다시 짠다(지난 조각은 그대로). 저장하지 않은 날은 볼 때 새로 짜인다.
AppState replanDays(AppState s, List<String> days, DateTime now) {
  var next = s;
  for (final k in days) {
    if (next.plans.containsKey(k)) next = next.withPlan(k, regeneratePlan(next, k, now));
  }
  return next;
}

/// 두 일정의 차이(바꾸기 미리보기용 문장).
List<String> diffPlans(DayPlan before, DayPlan after) {
  final out = <String>[];
  if (!before.wake.isAtSameMomentAs(after.wake)) out.add('기상 알람 ${formatHm(before.wake)} → ${formatHm(after.wake)}');
  List<ScheduleBlock> habits(DayPlan p) => p.blocks.where((b) => b.kind == BlockKind.habit && b.activity != Activity.sleep).toList();
  final hb = habits(before), ha = habits(after);
  for (final b in hb) {
    final a = ha.where((x) => x.title == b.title).firstOrNull;
    if (a == null) {
      out.add('${b.title} 빠짐');
    } else if (!a.start.isAtSameMomentAs(b.start) || !a.end.isAtSameMomentAs(b.end)) {
      out.add('${b.title} ${formatHm(b.start)}–${formatHm(b.end)} → ${formatHm(a.start)}–${formatHm(a.end)}');
    }
  }
  for (final a in ha) {
    if (!hb.any((b) => b.title == a.title)) out.add('${a.title} ${formatHm(a.start)} 추가');
  }
  List<ScheduleBlock> fixed(DayPlan p) => p.blocks.where((b) => b.kind == BlockKind.fixed && !b.locked).toList();
  final fb = fixed(before), fa = fixed(after);
  for (final a in fa) {
    final b = fb.where((x) => x.title == a.title).firstOrNull;
    if (b == null) {
      out.add('${a.title} ${formatHm(a.start)}–${formatHm(a.end)} 들어감');
    } else if (!b.start.isAtSameMomentAs(a.start)) {
      out.add('${a.title} ${formatHm(b.start)} → ${formatHm(a.start)}');
    }
  }
  for (final b in fb) {
    if (!fa.any((x) => x.title == b.title)) out.add('${b.title} 빠짐');
  }
  if (before.taskMinutes != after.taskMinutes) out.add('할 일 ${formatDuration(before.taskMinutes)} → ${formatDuration(after.taskMinutes)}');
  return out;
}

/// 미리보기 한 날.
class EditPreview {
  const EditPreview({required this.day, required this.label, required this.diffs});
  final String day;
  final String label;
  final List<String> diffs;
}

/// 적용하면 그날 일정이 어떻게 바뀌는지(미리보기).
List<EditPreview> previewEdits(AppState s, List<ScheduleEdit> edits, DateTime now) {
  var after = s;
  for (final e in edits) {
    after = applyEdit(after, e, now);
  }
  final days = editDays(s, edits, now);
  after = replanDays(after, days, now);
  return [
    for (final day in days) EditPreview(day: day, label: dayLabel(day, now), diffs: diffPlans(planFor(s, day, now).plan, planFor(after, day, now).plan)),
  ];
}
