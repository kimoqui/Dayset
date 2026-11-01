// DaySet 도메인 모델.
//
// Flutter에 의존하지 않는 순수 Dart 코드다. 위젯·화면·저장소 어디서든 같은
// 모델을 쓰고, 엔진 테스트는 Flutter 없이도 돌릴 수 있다.
//
// 웹 버전(dayset-web/src/engine/models.ts)과 같은 구조·같은 JSON 형식을 쓴다.
// 그래서 웹에서 내보낸 백업 파일을 앱에서 그대로 불러올 수 있다.

/// '지금' 버튼과 기록에 쓰는 다섯 가지 상태.
enum Activity {
  sleep('수면'),
  meal('식사'),
  work('업무'),
  exercise('운동'),
  rest('휴식');

  const Activity(this.label);
  final String label;

  static Activity fromName(String name) => Activity.values.firstWhere((a) => a.name == name);
}

/// 기록이 어디서 왔는지. 추정 기록은 달성률 계산에서 뺀다.
enum LogSource {
  alarm('알람'),
  button('버튼'),
  widget('위젯'),
  shortcut('단축어'),
  health('건강'),
  evening('확인'),
  estimate('추정');

  const LogSource(this.label);
  final String label;

  static LogSource fromName(String? name) => LogSource.values.firstWhere((a) => a.name == name, orElse: () => LogSource.button);
}

/// 하루 일정 블록의 종류.
enum BlockKind {
  habit,
  fixed,
  task,
  buffer;

  static BlockKind fromName(String? name) => BlockKind.values.firstWhere((a) => a.name == name, orElse: () => BlockKind.habit);
}

enum BlockStatus {
  planned,
  active,
  done,
  skipped;

  static BlockStatus fromName(String? name) => BlockStatus.values.firstWhere((a) => a.name == name, orElse: () => BlockStatus.planned);
}

enum TaskPriority {
  high('높음'),
  normal('보통'),
  low('낮음');

  const TaskPriority(this.label);
  final String label;

  static TaskPriority fromName(String? name) => TaskPriority.values.firstWhere((a) => a.name == name, orElse: () => TaskPriority.normal);
}

enum TaskType {
  work('업무', 60),
  assignment('과제', 90),
  homework('숙제', 45),
  personal('개인', 30);

  const TaskType(this.label, this.defaultMinutes);
  final String label;

  /// 소요시간을 모를 때 쓰는 기본값(엔진·규칙 명세 6번).
  final int defaultMinutes;

  static TaskType fromName(String? name) => TaskType.values.firstWhere((a) => a.name == name, orElse: () => TaskType.work);
}

/// 종류만으로 집중이 필요한 일인지 정한다(업무·과제는 집중 시간대에 먼저).
bool focusByType(TaskType type) => type == TaskType.work || type == TaskType.assignment;

/// 실패 이유(9. 경험 보완 · 엔진 명세 7번).
enum MissReason {
  tired('피곤함'),
  forgot('깜빡함'),
  conflict('일·약속 겹침'),
  unwilling('하기 싫었음'),
  other('기타');

  const MissReason(this.label);
  final String label;

  static MissReason fromName(String? name) => MissReason.values.firstWhere((a) => a.name == name, orElse: () => MissReason.other);
}

/// 자정 기준 분. 25:00처럼 24시를 넘는 값도 허용해 자정을 넘는 취침을 다룬다.
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.minutes);
  const ClockTime.hm(int hour, int minute) : minutes = hour * 60 + minute;

  final int minutes;

  int get hour => (minutes ~/ 60) % 24;
  int get minute => minutes % 60;

  DateTime on(DateTime day) => DateTime(day.year, day.month, day.day, 0, minutes);

  ClockTime operator +(int m) => ClockTime(minutes + m);
  ClockTime operator -(int m) => ClockTime(minutes - m);

  @override
  int compareTo(ClockTime other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) => other is ClockTime && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => formatClock(minutes);
}

/// 식사·운동처럼 매일 반복되는 습관 자리.
class HabitSlot {
  const HabitSlot({required this.title, required this.activity, required this.start, required this.minutes});

  final String title;
  final Activity activity;
  final ClockTime start;
  final int minutes;

  HabitSlot copyWith({String? title, ClockTime? start, int? minutes}) =>
      HabitSlot(title: title ?? this.title, activity: activity, start: start ?? this.start, minutes: minutes ?? this.minutes);

  Map<String, Object?> toJson() => {'title': title, 'activity': activity.name, 'start': start.minutes, 'minutes': minutes};

  factory HabitSlot.fromJson(Map<String, Object?> j) => HabitSlot(
        title: j['title'] as String? ?? '',
        activity: Activity.fromName(j['activity'] as String? ?? 'meal'),
        start: ClockTime(_int(j['start'])),
        minutes: _int(j['minutes']),
      );
}

/// 사용자의 습관 목표.
class HabitGoals {
  const HabitGoals({required this.wake, required this.sleepMinutes, this.meals = const [], this.exercise});

  final ClockTime wake;
  final int sleepMinutes;
  final List<HabitSlot> meals;
  final HabitSlot? exercise;

  HabitGoals copyWith({ClockTime? wake, int? sleepMinutes, List<HabitSlot>? meals, HabitSlot? exercise, bool clearExercise = false}) => HabitGoals(
        wake: wake ?? this.wake,
        sleepMinutes: sleepMinutes ?? this.sleepMinutes,
        meals: meals ?? this.meals,
        exercise: clearExercise ? null : (exercise ?? this.exercise),
      );

  Map<String, Object?> toJson() => {
        'wake': wake.minutes,
        'sleepMinutes': sleepMinutes,
        'meals': [for (final m in meals) m.toJson()],
        'exercise': exercise?.toJson(),
      };

  factory HabitGoals.fromJson(Map<String, Object?> j) => HabitGoals(
        wake: ClockTime(_int(j['wake'], 420)),
        sleepMinutes: _int(j['sleepMinutes'], 420),
        meals: [for (final m in (j['meals'] as List? ?? const [])) HabitSlot.fromJson(_map(m))],
        exercise: j['exercise'] == null ? null : HabitSlot.fromJson(_map(j['exercise'])),
      );
}

/// 개인 설정. 수치는 엔진 명세의 초기값이다.
class PersonalSettings {
  const PersonalSettings({
    this.prepMinutes = 50,
    this.travelMinutes = 40,
    this.sleepLatencyMinutes = 15,
    this.windDownMinutes = 30,
    this.focusStart = const ClockTime.hm(9, 0),
    this.focusEnd = const ClockTime.hm(12, 0),
    this.chunkMinutes = 50,
    this.restMinutes = 10,
    this.fillRatio = 0.75,
    this.bedEarlierMinutes = 0,
  });

  final int prepMinutes;
  final int travelMinutes;
  final int sleepLatencyMinutes;
  final int windDownMinutes;
  final ClockTime focusStart;
  final ClockTime focusEnd;
  final int chunkMinutes;
  final int restMinutes;

  /// 빈 시간 중 할 일로 채울 비율.
  final double fillRatio;

  /// 코칭 R4로 앞당긴 취침 시각(분).
  final int bedEarlierMinutes;

  PersonalSettings copyWith({
    int? prepMinutes,
    int? travelMinutes,
    int? sleepLatencyMinutes,
    int? windDownMinutes,
    ClockTime? focusStart,
    ClockTime? focusEnd,
    int? chunkMinutes,
    int? restMinutes,
    double? fillRatio,
    int? bedEarlierMinutes,
  }) =>
      PersonalSettings(
        prepMinutes: prepMinutes ?? this.prepMinutes,
        travelMinutes: travelMinutes ?? this.travelMinutes,
        sleepLatencyMinutes: sleepLatencyMinutes ?? this.sleepLatencyMinutes,
        windDownMinutes: windDownMinutes ?? this.windDownMinutes,
        focusStart: focusStart ?? this.focusStart,
        focusEnd: focusEnd ?? this.focusEnd,
        chunkMinutes: chunkMinutes ?? this.chunkMinutes,
        restMinutes: restMinutes ?? this.restMinutes,
        fillRatio: fillRatio ?? this.fillRatio,
        bedEarlierMinutes: bedEarlierMinutes ?? this.bedEarlierMinutes,
      );

  Map<String, Object?> toJson() => {
        'prepMinutes': prepMinutes,
        'travelMinutes': travelMinutes,
        'sleepLatencyMinutes': sleepLatencyMinutes,
        'windDownMinutes': windDownMinutes,
        'focusStart': focusStart.minutes,
        'focusEnd': focusEnd.minutes,
        'chunkMinutes': chunkMinutes,
        'restMinutes': restMinutes,
        'fillRatio': fillRatio,
        'bedEarlierMinutes': bedEarlierMinutes,
      };

  factory PersonalSettings.fromJson(Map<String, Object?> j) {
    const d = PersonalSettings();
    return PersonalSettings(
      prepMinutes: _int(j['prepMinutes'], d.prepMinutes),
      travelMinutes: _int(j['travelMinutes'], d.travelMinutes),
      sleepLatencyMinutes: _int(j['sleepLatencyMinutes'], d.sleepLatencyMinutes),
      windDownMinutes: _int(j['windDownMinutes'], d.windDownMinutes),
      focusStart: ClockTime(_int(j['focusStart'], d.focusStart.minutes)),
      focusEnd: ClockTime(_int(j['focusEnd'], d.focusEnd.minutes)),
      chunkMinutes: _int(j['chunkMinutes'], d.chunkMinutes),
      restMinutes: _int(j['restMinutes'], d.restMinutes),
      fillRatio: (j['fillRatio'] as num?)?.toDouble() ?? d.fillRatio,
      bedEarlierMinutes: _int(j['bedEarlierMinutes'], 0),
    );
  }
}

/// 캘린더에서 가져온(또는 직접 넣은) 고정 일정.
class FixedEvent {
  const FixedEvent({required this.id, required this.title, required this.start, required this.end, this.source});

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;

  /// 외부 캘린더에서 가져온 일정이면 그 캘린더 id. 다시 가져올 때 통째로 바꾼다.
  final String? source;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'start': encodeDate(start), 'end': encodeDate(end), if (source != null) 'source': source};

  factory FixedEvent.fromJson(Map<String, Object?> j) => FixedEvent(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        start: decodeDate(j['start'])!,
        end: decodeDate(j['end'])!,
        source: j['source'] as String?,
      );
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.estMinutes,
    required this.dueAt,
    this.type = TaskType.work,
    this.priority = TaskPriority.normal,
    this.focus = false,
    this.doneMinutes = 0,
    this.link,
    this.done = false,
    this.rank,
    this.createdAt,
    this.extraMinutes = 0,
  });

  final String id;
  final String title;
  final int estMinutes;
  final DateTime dueAt;
  final TaskType type;
  final TaskPriority priority;
  final bool focus;
  final int doneMinutes;
  final String? link;
  final bool done;

  /// 사용자가 끌어서 정한 순서(0이 맨 위). 있으면 마감·우선순위보다 먼저 본다.
  final int? rank;

  /// 만든 시각(오래된 할 일을 알아보는 데 쓴다).
  final DateTime? createdAt;

  /// '30분 더'처럼 잡은 시간을 다 쓴 뒤 사용자가 늘린 시간.
  final int extraMinutes;

  int get remainingMinutes => estMinutes - doneMinutes < 0 ? 0 : estMinutes - doneMinutes;

  TaskItem copyWith({
    String? id,
    String? title,
    int? estMinutes,
    DateTime? dueAt,
    TaskType? type,
    TaskPriority? priority,
    bool? focus,
    int? doneMinutes,
    bool? done,
    int? rank,
    DateTime? createdAt,
    int? extraMinutes,
  }) =>
      TaskItem(
        id: id ?? this.id,
        title: title ?? this.title,
        estMinutes: estMinutes ?? this.estMinutes,
        dueAt: dueAt ?? this.dueAt,
        type: type ?? this.type,
        priority: priority ?? this.priority,
        focus: focus ?? this.focus,
        doneMinutes: doneMinutes ?? this.doneMinutes,
        link: link,
        done: done ?? this.done,
        rank: rank ?? this.rank,
        createdAt: createdAt ?? this.createdAt,
        extraMinutes: extraMinutes ?? this.extraMinutes,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'estMinutes': estMinutes,
        'dueAt': encodeDate(dueAt),
        'type': type.name,
        'priority': priority.name,
        'focus': focus,
        'doneMinutes': doneMinutes,
        if (link != null) 'link': link,
        if (done) 'done': true,
        if (createdAt != null) 'createdAt': encodeDate(createdAt!),
        if (extraMinutes != 0) 'extraMinutes': extraMinutes,
      };

  factory TaskItem.fromJson(Map<String, Object?> j) => TaskItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        estMinutes: _int(j['estMinutes'], 30),
        dueAt: decodeDate(j['dueAt']) ?? DateTime.now().add(const Duration(days: 30)),
        type: TaskType.fromName(j['type'] as String?),
        priority: TaskPriority.fromName(j['priority'] as String?),
        focus: j['focus'] as bool? ?? false,
        doneMinutes: _int(j['doneMinutes']),
        link: j['link'] as String?,
        done: j['done'] as bool? ?? false,
        createdAt: decodeDate(j['createdAt']),
        extraMinutes: _int(j['extraMinutes']),
      );
}

class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    this.activity,
    this.locked = false,
    this.focus = false,
    this.taskId,
    this.status = BlockStatus.planned,
    this.adjusted = false,
  });

  final String id;
  final BlockKind kind;
  final String title;
  final DateTime start;
  final DateTime end;
  final Activity? activity;
  final bool locked;
  final bool focus;
  final String? taskId;
  final BlockStatus status;

  /// 코칭으로 바뀐 블록인지(화면에 '조정됨' 표시).
  final bool adjusted;

  int get minutes => diffMin(end, start);

  /// 엔진이 움직일 수 없는 블록인지(잠금·캘린더·수면).
  bool get immovable => locked || kind == BlockKind.fixed || activity == Activity.sleep;

  bool overlaps(DateTime s, DateTime e) => start.isBefore(e) && s.isBefore(end);

  ScheduleBlock copyWith({String? id, String? title, DateTime? start, DateTime? end, BlockStatus? status, bool? adjusted}) => ScheduleBlock(
        id: id ?? this.id,
        kind: kind,
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        activity: activity,
        locked: locked,
        focus: focus,
        taskId: taskId,
        status: status ?? this.status,
        adjusted: adjusted ?? this.adjusted,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'start': encodeDate(start),
        'end': encodeDate(end),
        if (activity != null) 'activity': activity!.name,
        if (locked) 'locked': true,
        if (focus) 'focus': true,
        if (taskId != null) 'taskId': taskId,
        if (status != BlockStatus.planned) 'status': status.name,
        if (adjusted) 'adjusted': true,
      };

  factory ScheduleBlock.fromJson(Map<String, Object?> j) => ScheduleBlock(
        id: j['id'] as String,
        kind: BlockKind.fromName(j['kind'] as String?),
        title: j['title'] as String? ?? '',
        start: decodeDate(j['start'])!,
        end: decodeDate(j['end'])!,
        activity: j['activity'] == null ? null : Activity.fromName(j['activity'] as String),
        locked: j['locked'] as bool? ?? false,
        focus: j['focus'] as bool? ?? false,
        taskId: j['taskId'] as String?,
        status: BlockStatus.fromName(j['status'] as String?),
        adjusted: j['adjusted'] as bool? ?? false,
      );

  @override
  String toString() => 'Block($title ${formatHm(start)}-${formatHm(end)})';
}

class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.activity,
    required this.start,
    this.end,
    this.source = LogSource.button,
    this.confirmed = true,
    this.snoozeCount = 0,
  });

  final String id;
  final Activity activity;
  final DateTime start;
  final DateTime? end;
  final LogSource source;
  final bool confirmed;
  final int snoozeCount;

  bool get isOpen => end == null;
  bool get isEstimate => source == LogSource.estimate || !confirmed;

  int minutesUntil(DateTime now) => diffMin(end ?? now, start);

  ActivityLog copyWith({DateTime? start, DateTime? end, bool clearEnd = false, LogSource? source, bool? confirmed}) => ActivityLog(
        id: id,
        activity: activity,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        source: source ?? this.source,
        confirmed: confirmed ?? this.confirmed,
        snoozeCount: snoozeCount,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'activity': activity.name,
        'start': encodeDate(start),
        'end': end == null ? null : encodeDate(end!),
        'source': source.name,
        'confirmed': confirmed,
        'snoozeCount': snoozeCount,
      };

  factory ActivityLog.fromJson(Map<String, Object?> j) => ActivityLog(
        id: j['id'] as String,
        activity: Activity.fromName(j['activity'] as String),
        start: decodeDate(j['start'])!,
        end: decodeDate(j['end']),
        source: LogSource.fromName(j['source'] as String?),
        confirmed: j['confirmed'] as bool? ?? true,
        snoozeCount: _int(j['snoozeCount']),
      );
}

enum AlarmKind {
  wake,
  bed,
  windDown;

  static AlarmKind fromName(String? name) => AlarmKind.values.firstWhere((a) => a.name == name, orElse: () => AlarmKind.wake);
}

class PlannedAlarm {
  const PlannedAlarm({required this.kind, required this.at, required this.reason});

  final AlarmKind kind;
  final DateTime at;

  /// 알람 시각의 근거. 비서가 "알람이 왜 6시 40분이야?"에 답할 때 쓴다.
  final String reason;

  PlannedAlarm copyWith({String? reason, DateTime? at}) => PlannedAlarm(kind: kind, at: at ?? this.at, reason: reason ?? this.reason);

  Map<String, Object?> toJson() => {'kind': kind.name, 'at': encodeDate(at), 'reason': reason};

  factory PlannedAlarm.fromJson(Map<String, Object?> j) =>
      PlannedAlarm(kind: AlarmKind.fromName(j['kind'] as String?), at: decodeDate(j['at'])!, reason: j['reason'] as String? ?? '');
}

// ---------------------------------------------------------------------------
// 시간 도구 (웹 models.ts와 같은 동작)
// ---------------------------------------------------------------------------

/// 분 차이. 0 쪽으로 버린다.
int diffMin(DateTime a, DateTime b) => a.difference(b).inMinutes;

DateTime addMin(DateTime d, int minutes) => d.add(Duration(minutes: minutes));

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

/// 날짜 더하기(시각은 0시로).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// 그 날 자정 + 분.
DateTime clockOn(int minutes, DateTime day) => DateTime(day.year, day.month, day.day, 0, minutes);

String _pad(int n) => n.toString().padLeft(2, '0');

String formatHm(DateTime t) => '${_pad(t.hour)}:${_pad(t.minute)}';

String formatClock(int minutes) {
  final m = ((minutes % 1440) + 1440) % 1440;
  return '${_pad(m ~/ 60)}:${_pad(m % 60)}';
}

String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m분';
  if (m == 0) return '$h시간';
  return '$h시간 $m분';
}

/// 'YYYY-MM-DD' 형식의 날짜 키(기기 현지 시각 기준).
String dateKey(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

DateTime fromKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// 그 주 월요일.
DateTime mondayOf(DateTime d) {
  final day = dayStart(d);
  return addDays(day, -(day.weekday - 1));
}

const _weekday = ['월', '화', '수', '목', '금', '토', '일'];

String weekdayLabel(DateTime d) => _weekday[d.weekday - 1];

String koreanDate(DateTime d) => '${d.month}월 ${d.day}일 ${weekdayLabel(d)}요일';

/// 웹과 같은 날짜 문자열(UTC ISO, 밀리초 포함).
String encodeDate(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true).toIso8601String();

DateTime? decodeDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v as String)?.toLocal();
}

int _int(Object? v, [int fallback = 0]) => v is num ? v.round() : fallback;

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();
