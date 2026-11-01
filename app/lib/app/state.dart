// 기기에 저장하는 앱 상태. 웹 버전(dayset-web/src/app/state.ts)과 같은 구조·같은 JSON이다.
// 웹에서 내보낸 백업(JSON)을 그대로 불러올 수 있고, 앱에서 내보낸 백업도 웹에서 열린다.
//
// 규칙
//  - 모든 값은 바꾸지 않는다(immutable). 바꿀 때는 copyWith로 새 값을 만든다.
//  - 날짜는 UTC ISO 문자열(밀리초까지), 자정 기준 시각(ClockTime)은 분 정수로 저장한다.
//  - 새 필드가 생겨도 예전 데이터가 열리도록 fromJson은 빠진 값을 기본값으로 채운다.

import 'dart:convert';
import 'dart:math';

import '../core/engine/coaching.dart';
import '../core/engine/correction.dart';
import '../core/engine/schedule_builder.dart';
import '../core/model/models.dart';

// ---------------------------------------------------------------------------
// JSON 도구
// ---------------------------------------------------------------------------

typedef Json = Map<String, Object?>;

Json _m(Object? v) => v is Map ? v.cast<String, Object?>() : const {};
int _i(Object? v, [int fallback = 0]) => v is num ? v.round() : fallback;
int? _in(Object? v) => v is num ? v.round() : null;
double _f(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
double? _fn(Object? v) => v is num ? v.toDouble() : null;
String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _sn(Object? v) => v is String ? v : null;
bool _b(Object? v, [bool fallback = false]) => v is bool ? v : fallback;
DateTime _d(Object? v, [DateTime? fallback]) => decodeDate(v) ?? fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
DateTime? _dn(Object? v) => decodeDate(v);
List<T> _l<T>(Object? v, T Function(Json) f) => [for (final x in (v is List ? v : const [])) if (x is Map) f(_m(x))];
List<String> _ls(Object? v) => [for (final x in (v is List ? v : const [])) if (x is String) x];

/// copyWith에서 null로 바꾸는 것과 그대로 두는 것을 나누는 표시.
const Object keep = _Keep();

class _Keep {
  const _Keep();
}

T? _pick<T>(Object? v, T? old) => identical(v, keep) ? old : v as T?;

// ---------------------------------------------------------------------------
// 코칭 제안 JSON (엔진 타입은 JSON을 모르므로 여기서 맞춘다)
// ---------------------------------------------------------------------------

Json suggestionToJson(CoachingSuggestion s) => {
      'ruleId': s.ruleId,
      'message': s.message,
      'changes': [
        for (final c in s.changes)
          {
            'blockId': c.blockId,
            if (c.newMinutes != null) 'newMinutes': c.newMinutes,
            if (c.newTitle != null) 'newTitle': c.newTitle,
            'deferToTomorrow': c.deferToTomorrow,
          }
      ],
      'patch': s.patch,
    };

CoachingSuggestion suggestionFromJson(Json j) => CoachingSuggestion(
      ruleId: _s(j['ruleId']),
      message: _s(j['message']),
      changes: _l(j['changes'], (c) => _b(c['deferToTomorrow']) ? BlockChange.defer(_s(c['blockId'])) : BlockChange.shrink(_s(c['blockId']), _i(c['newMinutes']), _sn(c['newTitle']) ?? '')),
      patch: {
        for (final e in _m(j['patch']).entries)
          if (e.value is String || e.value is num || e.value is bool) e.key: e.value!,
      },
    );

// ---------------------------------------------------------------------------
// 기록·표시
// ---------------------------------------------------------------------------

enum WakeSource { alarm, button }

class WakeRecord {
  const WakeRecord({required this.day, required this.at, required this.snoozes, required this.source});
  final String day;
  final DateTime at;
  final int snoozes;
  final WakeSource source;

  Json toJson() => {'day': day, 'at': encodeDate(at), 'snoozes': snoozes, 'source': source.name};
  factory WakeRecord.fromJson(Json j) =>
      WakeRecord(day: _s(j['day']), at: _d(j['at']), snoozes: _i(j['snoozes']), source: j['source'] == 'alarm' ? WakeSource.alarm : WakeSource.button);
}

class MissMark {
  const MissMark({required this.day, required this.blockId, required this.activity, required this.reason, required this.at});
  final String day;
  final String blockId;
  final Activity activity;
  final MissReason reason;
  final DateTime at;

  Json toJson() => {'day': day, 'blockId': blockId, 'activity': activity.name, 'reason': reason.name, 'at': encodeDate(at)};
  factory MissMark.fromJson(Json j) => MissMark(
        day: _s(j['day']),
        blockId: _s(j['blockId']),
        activity: Activity.fromName(_s(j['activity'], 'work')),
        reason: MissReason.fromName(_sn(j['reason'])),
        at: _d(j['at']),
      );
}

class SkipMark {
  const SkipMark({required this.day, required this.blockId});
  final String day;
  final String blockId;

  Json toJson() => {'day': day, 'blockId': blockId};
  factory SkipMark.fromJson(Json j) => SkipMark(day: _s(j['day']), blockId: _s(j['blockId']));
}

class TaskCredit {
  const TaskCredit({required this.day, required this.blockId, required this.taskId, required this.minutes});
  final String day;
  final String blockId;
  final String taskId;
  final int minutes;

  Json toJson() => {'day': day, 'blockId': blockId, 'taskId': taskId, 'minutes': minutes};
  factory TaskCredit.fromJson(Json j) => TaskCredit(day: _s(j['day']), blockId: _s(j['blockId']), taskId: _s(j['taskId']), minutes: _i(j['minutes']));
}

class DayOverride {
  const DayOverride({this.dinnerShift, this.notes = const []});
  final int? dinnerShift;
  final List<String> notes;

  DayOverride copyWith({int? dinnerShift, List<String>? notes}) => DayOverride(dinnerShift: dinnerShift ?? this.dinnerShift, notes: notes ?? this.notes);

  Json toJson() => {if (dinnerShift != null) 'dinnerShift': dinnerShift, if (notes.isNotEmpty) 'notes': notes};
  factory DayOverride.fromJson(Json j) => DayOverride(dinnerShift: _in(j['dinnerShift']), notes: _ls(j['notes']));
}

/// 저장한 하루 일정. 그 날이 시작되면(또는 전날 밤 확정하면) 고정한다.
class StoredPlan {
  const StoredPlan(this.plan, {required this.inputsVersion, this.regen = 0});
  final DayPlan plan;
  final int inputsVersion;
  final int regen;

  List<ScheduleBlock> get blocks => plan.blocks;

  StoredPlan withPlan(DayPlan p) => StoredPlan(p, inputsVersion: inputsVersion, regen: regen);

  Json toJson() => {...plan.toJson(), 'inputsVersion': inputsVersion, 'regen': regen};
  factory StoredPlan.fromJson(Json j) => StoredPlan(DayPlan.fromJson(j), inputsVersion: _i(j['inputsVersion'], 1), regen: _i(j['regen']));
}

enum InboxKind { coach, info }

enum InboxStatus { pending, accepted, kept, seen }

class InboxItem {
  const InboxItem({
    required this.id,
    required this.day,
    required this.createdAt,
    required this.kind,
    required this.message,
    this.status = InboxStatus.pending,
    this.suggestion,
    this.resultText,
    this.action,
  });
  final String id;
  final String day;
  final DateTime createdAt;
  final InboxKind kind;
  final CoachingSuggestion? suggestion;
  final String message;
  final InboxStatus status;
  final String? resultText;

  /// 승인 뒤 열 화면(예: 'settings').
  final String? action;

  InboxItem copyWith({InboxStatus? status, String? resultText, Object? action = keep}) => InboxItem(
        id: id,
        day: day,
        createdAt: createdAt,
        kind: kind,
        message: message,
        suggestion: suggestion,
        status: status ?? this.status,
        resultText: resultText ?? this.resultText,
        action: _pick(action, this.action),
      );

  Json toJson() => {
        'id': id,
        'day': day,
        'createdAt': encodeDate(createdAt),
        'kind': kind.name,
        if (suggestion != null) 'suggestion': suggestionToJson(suggestion!),
        'message': message,
        'status': status.name,
        if (resultText != null) 'resultText': resultText,
        if (action != null) 'action': action,
      };
  factory InboxItem.fromJson(Json j) => InboxItem(
        id: _s(j['id']),
        day: _s(j['day']),
        createdAt: _d(j['createdAt']),
        kind: j['kind'] == 'info' ? InboxKind.info : InboxKind.coach,
        suggestion: j['suggestion'] is Map ? suggestionFromJson(_m(j['suggestion'])) : null,
        message: _s(j['message']),
        status: InboxStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => InboxStatus.pending),
        resultText: _sn(j['resultText']),
        action: _sn(j['action']),
      );
}

class AlarmState {
  const AlarmState({this.snoozes = 0, this.snoozeUntil, this.done = false});
  final int snoozes;
  final DateTime? snoozeUntil;
  final bool done;

  AlarmState copyWith({int? snoozes, Object? snoozeUntil = keep, bool? done}) =>
      AlarmState(snoozes: snoozes ?? this.snoozes, snoozeUntil: _pick(snoozeUntil, this.snoozeUntil), done: done ?? this.done);

  Json toJson() => {'snoozes': snoozes, if (snoozeUntil != null) 'snoozeUntil': encodeDate(snoozeUntil!), if (done) 'done': true};
  factory AlarmState.fromJson(Json j) => AlarmState(snoozes: _i(j['snoozes']), snoozeUntil: _dn(j['snoozeUntil']), done: _b(j['done']));
}

class CorrectionHistory {
  const CorrectionHistory({required this.week, required this.decision, required this.rate, required this.target});
  final String week;
  final WeeklyDecision decision;
  final double? rate;
  final int target;

  Json toJson() => {'week': week, 'decision': decision.name, 'rate': rate, 'target': target};
  factory CorrectionHistory.fromJson(Json j) =>
      CorrectionHistory(week: _s(j['week']), decision: WeeklyDecision.fromName(_sn(j['decision'])), rate: _fn(j['rate']), target: _i(j['target']));
}

class CorrectionState {
  const CorrectionState({required this.plan, required this.lastUpdateWeek, this.holdNext = false, this.history = const []});
  final CorrectionPlan plan;
  final String lastUpdateWeek;
  final bool holdNext;
  final List<CorrectionHistory> history;

  CorrectionState copyWith({CorrectionPlan? plan, String? lastUpdateWeek, bool? holdNext, List<CorrectionHistory>? history}) => CorrectionState(
        plan: plan ?? this.plan,
        lastUpdateWeek: lastUpdateWeek ?? this.lastUpdateWeek,
        holdNext: holdNext ?? this.holdNext,
        history: history ?? this.history,
      );

  Json toJson() => {'plan': plan.toJson(), 'lastUpdateWeek': lastUpdateWeek, 'holdNext': holdNext, 'history': [for (final h in history) h.toJson()]};
  factory CorrectionState.fromJson(Json j) => CorrectionState(
        plan: CorrectionPlan.fromJson(_m(j['plan'])),
        lastUpdateWeek: _s(j['lastUpdateWeek']),
        holdNext: _b(j['holdNext']),
        history: _l(j['history'], CorrectionHistory.fromJson),
      );
}

/// 2일 관찰: 1일차는 기록만(recording), 2일차에 첫 일정을 써 보고(trial), 2일차 저녁에 끝낸다(done).
enum ObservationPhase { recording, trial, done }

class Observation {
  const Observation({required this.phase, required this.day1, this.day2, required this.startedAt});
  final ObservationPhase phase;

  /// 기록하는 날(1일차). 오후 3시 이후에 시작하면 다음 날이 1일차다.
  final String day1;

  /// 첫 일정을 써 보는 날(2일차).
  final String? day2;
  final DateTime startedAt;

  Observation copyWith({ObservationPhase? phase, String? day2}) => Observation(phase: phase ?? this.phase, day1: day1, day2: day2 ?? this.day2, startedAt: startedAt);

  Json toJson() => {'phase': phase.name, 'day1': day1, if (day2 != null) 'day2': day2, 'startedAt': encodeDate(startedAt)};
  factory Observation.fromJson(Json j) => Observation(
        phase: ObservationPhase.values.firstWhere((p) => p.name == j['phase'], orElse: () => ObservationPhase.done),
        day1: _s(j['day1']),
        day2: _sn(j['day2']),
        startedAt: _d(j['startedAt']),
      );
}

enum CalendarKind { ics, google }

/// 가져온 외부 캘린더. 다시 가져오면 그 캘린더의 일정을 통째로 바꾼다.
class CalendarSource {
  const CalendarSource({required this.id, required this.kind, required this.name, required this.lastSync, this.count = 0, this.error, this.needsAuth = false});
  final String id;
  final CalendarKind kind;
  final String name;
  final DateTime lastSync;
  final int count;

  /// 마지막 동기화가 실패한 이유(이전에 가져온 일정은 그대로 둔다).
  final String? error;

  /// 구글 연결이 만료돼 다시 연결해야 하는지.
  final bool needsAuth;

  CalendarSource copyWith({DateTime? lastSync, int? count, Object? error = keep, bool? needsAuth}) => CalendarSource(
        id: id,
        kind: kind,
        name: name,
        lastSync: lastSync ?? this.lastSync,
        count: count ?? this.count,
        error: _pick(error, this.error),
        needsAuth: needsAuth ?? this.needsAuth,
      );

  Json toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'lastSync': encodeDate(lastSync),
        'count': count,
        if (error != null) 'error': error,
        if (needsAuth) 'needsAuth': true,
      };
  factory CalendarSource.fromJson(Json j) => CalendarSource(
        id: _s(j['id']),
        kind: j['kind'] == 'google' ? CalendarKind.google : CalendarKind.ics,
        name: _s(j['name']),
        lastSync: _d(j['lastSync']),
        count: _i(j['count']),
        error: _sn(j['error']),
        needsAuth: _b(j['needsAuth']),
      );
}

/// 처음 접속할 때 고르는 목표.
enum GoalFocus {
  wake('제때 일어나기'),
  sleep('충분히 자기'),
  breakfast('아침 챙겨 먹기'),
  exercise('운동 습관'),
  tasks('할 일 끝내기');

  const GoalFocus(this.label);
  final String label;
}

class GoalIntent {
  const GoalIntent({required this.focus, required this.wake, required this.sleepMinutes, required this.exerciseMinutes, required this.setAt});
  final List<GoalFocus> focus;
  final int wake;
  final int sleepMinutes;
  final int exerciseMinutes;
  final DateTime setAt;

  Json toJson() => {'focus': [for (final f in focus) f.name], 'wake': wake, 'sleepMinutes': sleepMinutes, 'exerciseMinutes': exerciseMinutes, 'setAt': encodeDate(setAt)};
  factory GoalIntent.fromJson(Json j) => GoalIntent(
        focus: [for (final n in _ls(j['focus'])) ...GoalFocus.values.where((f) => f.name == n)],
        wake: _i(j['wake'], 420),
        sleepMinutes: _i(j['sleepMinutes'], 420),
        exerciseMinutes: _i(j['exerciseMinutes'], 30),
        setAt: _d(j['setAt']),
      );
}

/// 건강 기록 수집·이용 동의(필수)와 베타 지표 내보내기 동의(선택).
class Consent {
  const Consent({required this.health, required this.metrics, required this.at, this.version = 1});
  final bool health;
  final bool metrics;
  final DateTime at;
  final int version;

  Json toJson() => {'health': health, 'metrics': metrics, 'at': encodeDate(at), 'version': version};
  factory Consent.fromJson(Json j) => Consent(health: _b(j['health']), metrics: _b(j['metrics']), at: _d(j['at']), version: _i(j['version'], 1));
}

/// 알림: 권한을 받으면 지금 일정을 알림에 띄워 두고, 기록할 때를 알린다.
class NotifyPrefs {
  const NotifyPrefs({this.enabled = false, this.sticky = true, this.remind = true, this.token, this.tokenAt});
  final bool enabled;

  /// 지금 일정을 알림에 계속 띄워 두기.
  final bool sticky;

  /// 일정이 시작됐는데 기록이 없으면 알리기.
  final bool remind;

  /// 푸시 토큰. 서버에 등록할 때 쓴다.
  final String? token;
  final DateTime? tokenAt;

  NotifyPrefs copyWith({bool? enabled, bool? sticky, bool? remind, Object? token = keep, Object? tokenAt = keep}) => NotifyPrefs(
        enabled: enabled ?? this.enabled,
        sticky: sticky ?? this.sticky,
        remind: remind ?? this.remind,
        token: _pick(token, this.token),
        tokenAt: _pick(tokenAt, this.tokenAt),
      );

  Json toJson() => {'enabled': enabled, 'sticky': sticky, 'remind': remind, if (token != null) 'token': token, if (tokenAt != null) 'tokenAt': encodeDate(tokenAt!)};
  factory NotifyPrefs.fromJson(Json j) =>
      NotifyPrefs(enabled: _b(j['enabled']), sticky: _b(j['sticky'], true), remind: _b(j['remind'], true), token: _sn(j['token']), tokenAt: _dn(j['tokenAt']));
}

class SurveyAnswer {
  const SurveyAnswer({required this.key, required this.answer, this.best, this.worst, required this.at});

  /// 'd7' | 'd28'
  final String key;

  /// 'very' | 'some' | 'not' | 'stopped'
  final String answer;
  final String? best;
  final String? worst;
  final DateTime at;

  Json toJson() => {'key': key, 'answer': answer, if (best != null) 'best': best, if (worst != null) 'worst': worst, 'at': encodeDate(at)};
  factory SurveyAnswer.fromJson(Json j) => SurveyAnswer(key: _s(j['key']), answer: _s(j['answer']), best: _sn(j['best']), worst: _sn(j['worst']), at: _d(j['at']));
}

class FeedbackReport {
  const FeedbackReport({required this.at, required this.kind, required this.text, required this.page});
  final DateTime at;

  /// 'bug' | 'hard' | 'idea'
  final String kind;
  final String text;
  final String page;

  Json toJson() => {'at': encodeDate(at), 'kind': kind, 'text': text, 'page': page};
  factory FeedbackReport.fromJson(Json j) => FeedbackReport(at: _d(j['at']), kind: _s(j['kind'], 'idea'), text: _s(j['text']), page: _s(j['page']));
}

class FeedbackLog {
  const FeedbackLog({this.surveys = const [], this.reports = const [], this.surveyLater});
  final List<SurveyAnswer> surveys;
  final List<FeedbackReport> reports;
  final String? surveyLater;

  FeedbackLog copyWith({List<SurveyAnswer>? surveys, List<FeedbackReport>? reports, String? surveyLater}) =>
      FeedbackLog(surveys: surveys ?? this.surveys, reports: reports ?? this.reports, surveyLater: surveyLater ?? this.surveyLater);

  Json toJson() => {'surveys': [for (final s in surveys) s.toJson()], 'reports': [for (final r in reports) r.toJson()], if (surveyLater != null) 'surveyLater': surveyLater};
  factory FeedbackLog.fromJson(Json j) =>
      FeedbackLog(surveys: _l(j['surveys'], SurveyAnswer.fromJson), reports: _l(j['reports'], FeedbackReport.fromJson), surveyLater: _sn(j['surveyLater']));
}

class MetricsEvent {
  const MetricsEvent({required this.at, required this.k, this.v});
  final DateTime at;
  final String k;
  final String? v;

  Json toJson() => {'at': encodeDate(at), 'k': k, if (v != null) 'v': v};
  factory MetricsEvent.fromJson(Json j) => MetricsEvent(at: _d(j['at']), k: _s(j['k']), v: _sn(j['v']));
}

/// 베타 지표: 연 날과 몇 가지 행동만 남긴다(기록 내용·이름은 남기지 않는다).
class MetricsLog {
  const MetricsLog({required this.installAt, this.opens = const [], this.events = const []});
  final DateTime installAt;
  final List<String> opens;
  final List<MetricsEvent> events;

  MetricsLog copyWith({DateTime? installAt, List<String>? opens, List<MetricsEvent>? events}) =>
      MetricsLog(installAt: installAt ?? this.installAt, opens: opens ?? this.opens, events: events ?? this.events);

  Json toJson() => {'installAt': encodeDate(installAt), 'opens': opens, 'events': [for (final e in events) e.toJson()]};
  factory MetricsLog.fromJson(Json j) => MetricsLog(installAt: _d(j['installAt'], DateTime.now()), opens: _ls(j['opens']), events: _l(j['events'], MetricsEvent.fromJson));
}

/// 필요한 순간에 한 번만 묻는 질문을 이미 물었는지.
class Asked {
  const Asked({this.travel = false, this.obsIntroAt, this.obsLate = false, this.celebrated});
  final bool travel;
  final DateTime? obsIntroAt;
  final bool obsLate;
  final String? celebrated;

  Asked copyWith({bool? travel, DateTime? obsIntroAt, bool? obsLate, String? celebrated}) => Asked(
        travel: travel ?? this.travel,
        obsIntroAt: obsIntroAt ?? this.obsIntroAt,
        obsLate: obsLate ?? this.obsLate,
        celebrated: celebrated ?? this.celebrated,
      );

  Json toJson() => {if (travel) 'travel': true, if (obsIntroAt != null) 'obsIntroAt': encodeDate(obsIntroAt!), if (obsLate) 'obsLate': true, if (celebrated != null) 'celebrated': celebrated};
  factory Asked.fromJson(Json j) => Asked(travel: _b(j['travel']), obsIntroAt: _dn(j['obsIntroAt']), obsLate: _b(j['obsLate']), celebrated: _sn(j['celebrated']));
}

class Profile {
  const Profile({required this.id, this.name = ''});
  final String id;
  final String name;

  Profile copyWith({String? name}) => Profile(id: id, name: name ?? this.name);

  Json toJson() => {'id': id, 'name': name};
  factory Profile.fromJson(Json j) => Profile(id: _s(j['id'], newDeviceId()), name: _s(j['name']));
}

/// 친구(또는 근처 익명 사람)의 기록. 친구 코드(DS1-)로 주고받는다.
class Friend {
  const Friend({
    required this.id,
    required this.name,
    this.streak = 0,
    this.best = 0,
    required this.week,
    this.weekSetDays = 0,
    this.monthSetDays = 0,
    required this.updatedAt,
    this.anon = false,
    this.cell,
    this.demo = false,
  });
  final String id;
  final String name;
  final int streak;
  final int best;

  /// 코드를 만든 주(월요일 날짜)와 그 주의 셋 데이 수.
  final String week;
  final int weekSetDays;
  final int monthSetDays;
  final DateTime updatedAt;

  /// 근처 익명 보드에서 온 사람.
  final bool anon;

  /// 약 2km로 뭉갠 위치 칸.
  final String? cell;
  final bool demo;

  Json toJson() => {
        'id': id,
        'name': name,
        'streak': streak,
        'best': best,
        'week': week,
        'weekSetDays': weekSetDays,
        'monthSetDays': monthSetDays,
        'updatedAt': encodeDate(updatedAt),
        if (anon) 'anon': true,
        if (cell != null) 'cell': cell,
        if (demo) 'demo': true,
      };
  factory Friend.fromJson(Json j) => Friend(
        id: _s(j['id']),
        name: _s(j['name'], '친구'),
        streak: _i(j['streak']),
        best: _i(j['best']),
        week: _s(j['week']),
        weekSetDays: _i(j['weekSetDays']),
        monthSetDays: _i(j['monthSetDays']),
        updatedAt: _d(j['updatedAt']),
        anon: _b(j['anon']),
        cell: _sn(j['cell']),
        demo: _b(j['demo']),
      );
}

// ---------------------------------------------------------------------------
// 학습 기록(우선순위·걸리는 시간), 근처 보드
// ---------------------------------------------------------------------------

class OrderItem {
  const OrderItem({required this.type, required this.est, required this.age});
  final TaskType type;
  final int est;

  /// 만든 지 며칠 지났는지.
  final double age;

  Json toJson() => {'type': type.name, 'est': est, 'age': age};
  factory OrderItem.fromJson(Json j) => OrderItem(type: TaskType.fromName(_sn(j['type'])), est: _i(j['est']), age: _f(j['age']));
}

class Reorder {
  const Reorder({required this.at, required this.items});
  final DateTime at;
  final List<OrderItem> items;

  Json toJson() => {'at': encodeDate(at), 'items': [for (final i in items) i.toJson()]};
  factory Reorder.fromJson(Json j) => Reorder(at: _d(j['at']), items: _l(j['items'], OrderItem.fromJson));
}

class Completion {
  const Completion({required this.at, required this.type, required this.est, required this.age, required this.pos});
  final DateTime at;
  final TaskType type;
  final int est;
  final double age;

  /// 0 = 맨 위, 1 = 맨 아래.
  final double pos;

  Json toJson() => {'at': encodeDate(at), 'type': type.name, 'est': est, 'age': age, 'pos': pos};
  factory Completion.fromJson(Json j) => Completion(at: _d(j['at']), type: TaskType.fromName(_sn(j['type'])), est: _i(j['est']), age: _f(j['age']), pos: _f(j['pos']));
}

class LearningLog {
  const LearningLog({this.reorders = const [], this.completions = const [], this.dismissedDay});

  /// 순서를 바꿀 때마다 그 순서를 남긴다.
  final List<Reorder> reorders;

  /// 할 일을 끝낼 때 그때의 순서 위치를 남긴다.
  final List<Completion> completions;

  /// 추천을 '그대로 두기'로 넘긴 날.
  final String? dismissedDay;

  LearningLog copyWith({List<Reorder>? reorders, List<Completion>? completions, String? dismissedDay}) =>
      LearningLog(reorders: reorders ?? this.reorders, completions: completions ?? this.completions, dismissedDay: dismissedDay ?? this.dismissedDay);

  Json toJson() => {
        'reorders': [for (final r in reorders) r.toJson()],
        'completions': [for (final c in completions) c.toJson()],
        if (dismissedDay != null) 'dismissedDay': dismissedDay,
      };
  factory LearningLog.fromJson(Json j) =>
      LearningLog(reorders: _l(j['reorders'], Reorder.fromJson), completions: _l(j['completions'], Completion.fromJson), dismissedDay: _sn(j['dismissedDay']));
}

class DurationSample {
  const DurationSample({required this.at, this.taskId, required this.type, required this.title, required this.est, required this.actual, this.outlier = false});
  final DateTime at;
  final String? taskId;
  final TaskType type;
  final String title;
  final int est;
  final int actual;

  /// 실제/예상이 1/3배보다 작거나 3배보다 크면 보정에 쓰지 않는다.
  final bool outlier;

  DurationSample copyWith({bool? outlier}) => DurationSample(at: at, taskId: taskId, type: type, title: title, est: est, actual: actual, outlier: outlier ?? this.outlier);

  Json toJson() => {
        'at': encodeDate(at),
        if (taskId != null) 'taskId': taskId,
        'type': type.name,
        'title': title,
        'est': est,
        'actual': actual,
        if (outlier) 'outlier': true,
      };
  factory DurationSample.fromJson(Json j) => DurationSample(
        at: _d(j['at']),
        taskId: _sn(j['taskId']),
        type: TaskType.fromName(_sn(j['type'])),
        title: _s(j['title']),
        est: _i(j['est']),
        actual: _i(j['actual']),
        outlier: _b(j['outlier']),
      );
}

class DurationLearning {
  const DurationLearning({this.on = true, this.samples = const []});

  /// 걸리는 시간 자동 보정 켜기.
  final bool on;
  final List<DurationSample> samples;

  DurationLearning copyWith({bool? on, List<DurationSample>? samples}) => DurationLearning(on: on ?? this.on, samples: samples ?? this.samples);

  Json toJson() => {'on': on, 'samples': [for (final s in samples) s.toJson()]};
  factory DurationLearning.fromJson(Json j) => DurationLearning(on: _b(j['on'], true), samples: _l(j['samples'], DurationSample.fromJson));
}

class NearbyState {
  const NearbyState({this.on = false, this.cell, this.cellAt, this.people = const []});

  /// 근처에 익명으로 보이기(동의).
  final bool on;
  final String? cell;
  final DateTime? cellAt;
  final List<Friend> people;

  NearbyState copyWith({bool? on, Object? cell = keep, Object? cellAt = keep, List<Friend>? people}) => NearbyState(
        on: on ?? this.on,
        cell: _pick(cell, this.cell),
        cellAt: _pick(cellAt, this.cellAt),
        people: people ?? this.people,
      );

  Json toJson() => {'on': on, if (cell != null) 'cell': cell, if (cellAt != null) 'cellAt': encodeDate(cellAt!), 'people': [for (final p in people) p.toJson()]};
  factory NearbyState.fromJson(Json j) => NearbyState(on: _b(j['on']), cell: _sn(j['cell']), cellAt: _dn(j['cellAt']), people: _l(j['people'], Friend.fromJson));
}

// ---------------------------------------------------------------------------
// 앱 상태
// ---------------------------------------------------------------------------

const defaultGoals = HabitGoals(
  wake: ClockTime(7 * 60),
  sleepMinutes: 420,
  meals: [
    HabitSlot(title: '아침 식사', activity: Activity.meal, start: ClockTime(7 * 60 + 30), minutes: 30),
    HabitSlot(title: '점심 식사', activity: Activity.meal, start: ClockTime(12 * 60), minutes: 60),
    HabitSlot(title: '저녁 식사', activity: Activity.meal, start: ClockTime(18 * 60 + 30), minutes: 60),
  ],
  exercise: HabitSlot(title: '운동', activity: Activity.exercise, start: ClockTime(20 * 60 + 30), minutes: 30),
);

final _rand = Random();

/// 기기마다 하나인 번호(친구 코드·익명 별명에 쓴다).
String newDeviceId() => 'u-${List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rand.nextInt(36)]).join()}';

class AppState {
  const AppState({
    this.observation,
    this.asked = const Asked(),
    required this.profile,
    this.friends = const [],
    this.learning = const LearningLog(),
    this.nearby = const NearbyState(),
    this.durations = const DurationLearning(),
    this.calendars = const [],
    this.googleClientId = '',
    this.intent,
    this.consent,
    this.notify = const NotifyPrefs(),
    this.checkSkips = const [],
    this.feedback = const FeedbackLog(),
    required this.metrics,
    this.onboarded = false,
    this.demo = false,
    this.goals = defaultGoals,
    this.settings = const PersonalSettings(),
    this.correction,
    this.events = const [],
    this.tasks = const [],
    this.logs = const [],
    this.wakes = const [],
    this.plans = const {},
    this.overrides = const {},
    this.misses = const [],
    this.skips = const [],
    this.restDays = const [],
    this.credits = const [],
    this.coachHistory = const [],
    this.inbox = const [],
    this.alarms = const {},
    this.reminders = const {},
    this.eveningDone = const [],
    this.inputsVersion = 1,
  });

  static const version = 1;

  final Observation? observation;
  final Asked asked;

  /// 공유 카드·친구 순위에 쓰는 이름. id는 기기마다 하나.
  final Profile profile;
  final List<Friend> friends;

  /// 할 일 우선순위 학습 기록.
  final LearningLog learning;

  /// 근처 익명 보드.
  final NearbyState nearby;

  /// 걸리는 시간 자동 보정(예상 vs 실제).
  final DurationLearning durations;

  /// 가져온 캘린더(구글 연결, .ics 파일).
  final List<CalendarSource> calendars;

  /// 구글 OAuth 클라이언트 ID(웹 버전 전용, 앱은 쓰지 않지만 백업을 그대로 지킨다).
  final String googleClientId;
  final GoalIntent? intent;
  final Consent? consent;
  final NotifyPrefs notify;

  /// 일정 체크 팝업에서 '지금은 안 해요'로 넘긴 일정 조각.
  final List<String> checkSkips;
  final FeedbackLog feedback;
  final MetricsLog metrics;
  final bool onboarded;
  final bool demo;
  final HabitGoals goals;
  final PersonalSettings settings;
  final CorrectionState? correction;
  final List<FixedEvent> events;
  final List<TaskItem> tasks;
  final List<ActivityLog> logs;
  final List<WakeRecord> wakes;
  final Map<String, StoredPlan> plans;
  final Map<String, DayOverride> overrides;
  final List<MissMark> misses;
  final List<SkipMark> skips;
  final List<String> restDays;
  final List<TaskCredit> credits;
  final List<CoachRecord> coachHistory;
  final List<InboxItem> inbox;
  final Map<String, AlarmState> alarms;

  /// 코칭 R6로 켠 습관 미리 알림(몇 분 전).
  final Map<Activity, int> reminders;
  final List<String> eveningDone;

  /// 할 일·캘린더·설정이 바뀔 때마다 올린다. 저장한 일정이 오래됐는지 판단한다.
  final int inputsVersion;

  factory AppState.initial({DateTime? now}) => AppState(profile: Profile(id: newDeviceId()), metrics: MetricsLog(installAt: now ?? DateTime.now()));

  AppState copyWith({
    Object? observation = keep,
    Asked? asked,
    Profile? profile,
    List<Friend>? friends,
    LearningLog? learning,
    NearbyState? nearby,
    DurationLearning? durations,
    List<CalendarSource>? calendars,
    String? googleClientId,
    Object? intent = keep,
    Object? consent = keep,
    NotifyPrefs? notify,
    List<String>? checkSkips,
    FeedbackLog? feedback,
    MetricsLog? metrics,
    bool? onboarded,
    bool? demo,
    HabitGoals? goals,
    PersonalSettings? settings,
    Object? correction = keep,
    List<FixedEvent>? events,
    List<TaskItem>? tasks,
    List<ActivityLog>? logs,
    List<WakeRecord>? wakes,
    Map<String, StoredPlan>? plans,
    Map<String, DayOverride>? overrides,
    List<MissMark>? misses,
    List<SkipMark>? skips,
    List<String>? restDays,
    List<TaskCredit>? credits,
    List<CoachRecord>? coachHistory,
    List<InboxItem>? inbox,
    Map<String, AlarmState>? alarms,
    Map<Activity, int>? reminders,
    List<String>? eveningDone,
    int? inputsVersion,
  }) =>
      AppState(
        observation: _pick(observation, this.observation),
        asked: asked ?? this.asked,
        profile: profile ?? this.profile,
        friends: friends ?? this.friends,
        learning: learning ?? this.learning,
        nearby: nearby ?? this.nearby,
        durations: durations ?? this.durations,
        calendars: calendars ?? this.calendars,
        googleClientId: googleClientId ?? this.googleClientId,
        intent: _pick(intent, this.intent),
        consent: _pick(consent, this.consent),
        notify: notify ?? this.notify,
        checkSkips: checkSkips ?? this.checkSkips,
        feedback: feedback ?? this.feedback,
        metrics: metrics ?? this.metrics,
        onboarded: onboarded ?? this.onboarded,
        demo: demo ?? this.demo,
        goals: goals ?? this.goals,
        settings: settings ?? this.settings,
        correction: _pick(correction, this.correction),
        events: events ?? this.events,
        tasks: tasks ?? this.tasks,
        logs: logs ?? this.logs,
        wakes: wakes ?? this.wakes,
        plans: plans ?? this.plans,
        overrides: overrides ?? this.overrides,
        misses: misses ?? this.misses,
        skips: skips ?? this.skips,
        restDays: restDays ?? this.restDays,
        credits: credits ?? this.credits,
        coachHistory: coachHistory ?? this.coachHistory,
        inbox: inbox ?? this.inbox,
        alarms: alarms ?? this.alarms,
        reminders: reminders ?? this.reminders,
        eveningDone: eveningDone ?? this.eveningDone,
        inputsVersion: inputsVersion ?? this.inputsVersion,
      );

  /// 입력(할 일·캘린더·설정)이 바뀌었음을 표시한다.
  AppState bump() => copyWith(inputsVersion: inputsVersion + 1);

  /// 그 날 일정만 바꾼다.
  AppState withPlan(String key, StoredPlan plan) => copyWith(plans: {...plans, key: plan});

  Json toJson() => {
        'version': version,
        'observation': observation?.toJson(),
        'asked': asked.toJson(),
        'profile': profile.toJson(),
        'friends': [for (final f in friends) f.toJson()],
        'learning': learning.toJson(),
        'nearby': nearby.toJson(),
        'durations': durations.toJson(),
        'calendars': [for (final c in calendars) c.toJson()],
        'googleClientId': googleClientId,
        'intent': intent?.toJson(),
        'consent': consent?.toJson(),
        'notify': notify.toJson(),
        'checkSkips': checkSkips,
        'feedback': feedback.toJson(),
        'metrics': metrics.toJson(),
        'onboarded': onboarded,
        'demo': demo,
        'goals': goals.toJson(),
        'settings': settings.toJson(),
        'correction': correction?.toJson(),
        'events': [for (final e in events) e.toJson()],
        'tasks': [for (final t in tasks) t.toJson()],
        'logs': [for (final l in logs) l.toJson()],
        'wakes': [for (final w in wakes) w.toJson()],
        'plans': {for (final e in plans.entries) e.key: e.value.toJson()},
        'overrides': {for (final e in overrides.entries) e.key: e.value.toJson()},
        'misses': [for (final m in misses) m.toJson()],
        'skips': [for (final m in skips) m.toJson()],
        'restDays': restDays,
        'credits': [for (final c in credits) c.toJson()],
        'coachHistory': [for (final c in coachHistory) c.toJson()],
        'inbox': [for (final i in inbox) i.toJson()],
        'alarms': {for (final e in alarms.entries) e.key: e.value.toJson()},
        'reminders': {for (final e in reminders.entries) e.key.name: e.value},
        'eveningDone': eveningDone,
        'inputsVersion': inputsVersion,
      };

  /// 웹 백업과 같은 JSON에서 읽는다. 빠진 값은 기본값으로 채운다.
  factory AppState.fromJson(Json j) {
    if (j['version'] != 1) throw const FormatException('지원하지 않는 데이터 형식이에요');
    final base = AppState.initial();
    return AppState(
      observation: j['observation'] is Map ? Observation.fromJson(_m(j['observation'])) : null,
      asked: Asked.fromJson(_m(j['asked'])),
      profile: j['profile'] is Map ? Profile.fromJson(_m(j['profile'])) : base.profile,
      friends: _l(j['friends'], Friend.fromJson),
      learning: LearningLog.fromJson(_m(j['learning'])),
      nearby: NearbyState.fromJson(_m(j['nearby'])),
      durations: j['durations'] is Map ? DurationLearning.fromJson(_m(j['durations'])) : const DurationLearning(),
      calendars: _l(j['calendars'], CalendarSource.fromJson),
      googleClientId: _s(j['googleClientId']),
      intent: j['intent'] is Map ? GoalIntent.fromJson(_m(j['intent'])) : null,
      consent: j['consent'] is Map ? Consent.fromJson(_m(j['consent'])) : null,
      notify: j['notify'] is Map ? NotifyPrefs.fromJson(_m(j['notify'])) : const NotifyPrefs(),
      checkSkips: _ls(j['checkSkips']),
      feedback: FeedbackLog.fromJson(_m(j['feedback'])),
      metrics: j['metrics'] is Map ? MetricsLog.fromJson(_m(j['metrics'])) : base.metrics,
      onboarded: _b(j['onboarded']),
      demo: _b(j['demo']),
      goals: j['goals'] is Map ? HabitGoals.fromJson(_m(j['goals'])) : defaultGoals,
      settings: PersonalSettings.fromJson(_m(j['settings'])),
      correction: j['correction'] is Map ? CorrectionState.fromJson(_m(j['correction'])) : null,
      events: _l(j['events'], FixedEvent.fromJson),
      tasks: _l(j['tasks'], TaskItem.fromJson),
      logs: _l(j['logs'], ActivityLog.fromJson),
      wakes: _l(j['wakes'], WakeRecord.fromJson),
      // 알람(기상·취침·마무리)이 모자란 일정은 버린다. 오늘 일정이면 열 때 다시 만든다.
      plans: {
        for (final e in _m(j['plans']).entries)
          if (e.value is Map && (_m(e.value)['alarms'] is List) && (_m(e.value)['alarms'] as List).length >= 3) e.key: StoredPlan.fromJson(_m(e.value)),
      },
      overrides: {for (final e in _m(j['overrides']).entries) if (e.value is Map) e.key: DayOverride.fromJson(_m(e.value))},
      misses: _l(j['misses'], MissMark.fromJson),
      skips: _l(j['skips'], SkipMark.fromJson),
      restDays: _ls(j['restDays']),
      credits: _l(j['credits'], TaskCredit.fromJson),
      coachHistory: _l(j['coachHistory'], CoachRecord.fromJson),
      inbox: _l(j['inbox'], InboxItem.fromJson),
      alarms: {for (final e in _m(j['alarms']).entries) if (e.value is Map) e.key: AlarmState.fromJson(_m(e.value))},
      reminders: {
        for (final e in _m(j['reminders']).entries)
          if (e.value is num && Activity.values.any((a) => a.name == e.key)) Activity.fromName(e.key): _i(e.value),
      },
      eveningDone: _ls(j['eveningDone']),
      inputsVersion: _i(j['inputsVersion'], 1),
    );
  }
}

// ---------------------------------------------------------------------------
// 저장·불러오기
// ---------------------------------------------------------------------------

String serialize(AppState s) => jsonEncode(s.toJson());

/// 웹 백업 파일·앱 저장 데이터를 읽는다. 형식이 다르면 FormatException.
AppState deserialize(String text) {
  final Object? raw;
  try {
    raw = jsonDecode(text);
  } on FormatException {
    throw const FormatException('백업 파일을 읽지 못했어요');
  }
  if (raw is! Map) throw const FormatException('백업 파일을 읽지 못했어요');
  return AppState.fromJson(raw.cast<String, Object?>());
}

enum SaveResult { ok, quota, blocked }

/// 저장소 추상화. 앱은 기기 파일(또는 shared_preferences), 테스트는 메모리를 쓴다.
abstract class KeyValueStore {
  String? read(String key);

  /// 바로 반영한다. 기기에 쓰지 못하면 quota(공간 없음) 또는 blocked.
  SaveResult write(String key, String value);
  void remove(String key);
  Iterable<String> get keys;
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? data]) : data = data ?? {};
  final Map<String, String> data;

  /// 테스트용: 이 크기를 넘으면 공간이 없다고 답한다.
  int? quota;

  @override
  String? read(String key) => data[key];

  @override
  SaveResult write(String key, String value) {
    final q = quota;
    if (q != null && data.entries.where((e) => e.key != key).fold<int>(value.length, (n, e) => n + e.value.length) > q) return SaveResult.quota;
    data[key] = value;
    return SaveResult.ok;
  }

  @override
  void remove(String key) => data.remove(key);

  @override
  Iterable<String> get keys => data.keys;
}

const storageKey = 'dayset:v1';
const keptPrefix = 'dayset:kept:';

/// 보관 이유: 깨진 데이터(broken), 백업을 불러오기 직전 데이터(before-import).
enum KeptReason {
  broken('broken'),
  beforeImport('before-import');

  const KeptReason(this.code);
  final String code;
  static KeptReason fromCode(String? c) => KeptReason.values.firstWhere((r) => r.code == c, orElse: () => KeptReason.broken);
}

class KeptBackup {
  const KeptBackup({required this.key, required this.at, required this.reason, required this.size});
  final String key;
  final DateTime at;
  final KeptReason reason;
  final int size;
}

/// 저장·불러오기. 깨진 데이터는 지우지 않고 따로 보관한다(웹 버전과 같은 규칙).
class StateStorage {
  StateStorage(this.kv);
  final KeyValueStore kv;

  /// 시작할 때 생긴 문제. 'broken'이면 깨진 데이터를 따로 보관했다.
  KeptReason? loadIssue;

  /// 깨진 데이터를 보관하지 못했을 때 원래 키를 덮어쓰지 않는다.
  bool _keepBroken = false;

  AppState load({DateTime? now}) {
    String? text;
    try {
      text = kv.read(storageKey);
    } catch (_) {
      return AppState.initial(now: now);
    }
    if (text == null || text.isEmpty) return AppState.initial(now: now);
    try {
      return deserialize(text);
    } catch (_) {
      if (keepCopy(text, KeptReason.broken)) {
        try {
          kv.remove(storageKey);
        } catch (_) {
          _keepBroken = true;
        }
      } else {
        _keepBroken = true;
      }
      loadIssue = KeptReason.broken;
      return AppState.initial(now: now);
    }
  }

  SaveResult save(AppState s) {
    if (_keepBroken) return SaveResult.blocked;
    try {
      return kv.write(storageKey, serialize(s));
    } catch (_) {
      return SaveResult.blocked;
    }
  }

  /// 지금 데이터를 지우지 않고 따로 보관한다. 최근 3개만 남긴다.
  bool keepCopy(String text, KeptReason reason, {int? at}) {
    try {
      final r = kv.write('$keptPrefix${at ?? DateTime.now().millisecondsSinceEpoch}:${reason.code}', text);
      if (r != SaveResult.ok) return false;
      for (final k in keptBackups().skip(3)) {
        kv.remove(k.key);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 보관해 둔 이전 데이터 목록(최신 순).
  List<KeptBackup> keptBackups() {
    try {
      final out = <KeptBackup>[];
      for (final k in kv.keys.where((k) => k.startsWith(keptPrefix)).toList()) {
        final parts = k.substring(keptPrefix.length).split(':');
        out.add(KeptBackup(
          key: k,
          at: DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[0]) ?? 0),
          reason: KeptReason.fromCode(parts.length > 1 ? parts[1] : null),
          size: kv.read(k)?.length ?? 0,
        ));
      }
      out.sort((a, b) => b.at.compareTo(a.at));
      return out;
    } catch (_) {
      return [];
    }
  }
}
