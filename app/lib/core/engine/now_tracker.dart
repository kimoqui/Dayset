import '../model/models.dart';

/// '지금' 버튼 한 번의 결과.
class TapResult {
  const TapResult({
    required this.changed,
    this.started,
    this.ended,
    this.merged = false,
  });

  /// 상태가 바뀌었는지. 이미 같은 상태면 false.
  final bool changed;

  /// 새로 시작한 상태. 알림 서비스는 이 상태의 예정 알림을 취소한다.
  final Activity? started;

  /// 이번 탭으로 끝난 기록.
  final ActivityLog? ended;

  /// 10분 안에 같은 상태로 돌아와 앞 기록에 합쳤는지.
  final bool merged;
}

/// '지금' 버튼 상태 전환. 화면 정의서 S-02와 기획서의 버튼 규칙을 구현한다.
///
/// - 누르면 이전 상태 기록을 끝내고 새 상태 기록을 시작한다.
/// - 5초 안에는 되돌릴 수 있다.
/// - 다른 상태로 10분 미만 바꿨다가 원래 상태로 돌아오면, 중간 기록을 지우고
///   앞 기록을 이어간다(잠깐 잘못 누른 경우와 짧은 중단을 하나로 합친다).
class NowTracker {
  NowTracker({
    List<ActivityLog> logs = const [],
    this.mergeMinutes = 10,
    this.undoSeconds = 5,
    String Function()? idGenerator,
  })  : _logs = [...logs],
        _newId = idGenerator ?? _defaultId;

  final int mergeMinutes;
  final int undoSeconds;
  final String Function() _newId;

  List<ActivityLog> _logs;
  List<ActivityLog>? _undoSnapshot;
  DateTime? _lastTapAt;

  static int _counter = 0;
  static String _defaultId() =>
      'log-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  List<ActivityLog> get logs => List.unmodifiable(_logs);

  ActivityLog? get current {
    for (var i = _logs.length - 1; i >= 0; i--) {
      if (_logs[i].isOpen) return _logs[i];
    }
    return null;
  }

  bool canUndo(DateTime now) =>
      _undoSnapshot != null &&
      _lastTapAt != null &&
      now.difference(_lastTapAt!).inMilliseconds <= undoSeconds * 1000;

  TapResult tap(Activity activity, DateTime now,
      {LogSource source = LogSource.button, bool allowUndo = true}) {
    final cur = current;
    if (cur != null && cur.activity == activity) {
      return const TapResult(changed: false);
    }
    final snapshot = [..._logs];

    // 짧은 중단 뒤 원래 상태로 복귀 → 합치기
    if (cur != null && now.difference(cur.start).inMinutes < mergeMinutes) {
      final prevIndex = _indexOfLastClosedBefore(cur);
      if (prevIndex != null) {
        final prev = _logs[prevIndex];
        final gap = now.difference(prev.end!).inMinutes;
        if (prev.activity == activity && gap < mergeMinutes) {
          _logs = [..._logs]
            ..remove(cur)
            ..[prevIndex] = prev.copyWith(clearEnd: true);
          _remember(snapshot, now, allowUndo);
          return TapResult(changed: true, started: activity, merged: true);
        }
      }
    }

    ActivityLog? ended;
    if (cur != null) {
      final closed = cur.copyWith(end: now);
      ended = closed;
      _logs = [
        for (final l in _logs) identical(l, cur) ? closed : l,
      ];
    }
    _logs = [
      ..._logs,
      ActivityLog(id: _newId(), activity: activity, start: now, source: source),
    ];
    _remember(snapshot, now, allowUndo);
    return TapResult(changed: true, started: activity, ended: ended);
  }

  /// 현재 상태를 끝내기만 한다(예: 저녁 확인에서 '오늘 마무리').
  ActivityLog? stop(DateTime now) {
    final cur = current;
    if (cur == null) return null;
    final ended = cur.copyWith(end: now);
    _logs = [for (final l in _logs) identical(l, cur) ? ended : l];
    _undoSnapshot = null;
    return ended;
  }

  /// 마지막 탭을 되돌린다. 5초가 지났으면 false.
  bool undo(DateTime now) {
    if (!canUndo(now)) return false;
    _logs = _undoSnapshot!;
    _undoSnapshot = null;
    _lastTapAt = null;
    return true;
  }

  /// 위젯·단축어처럼 앱 밖에서 쌓인 탭을 시간순으로 반영한다. 되돌리기는 없다.
  List<TapResult> applyExternal(List<({Activity activity, DateTime at})> events,
      {LogSource source = LogSource.widget}) {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    return [
      for (final e in sorted) tap(e.activity, e.at, source: source, allowUndo: false),
    ];
  }

  int? _indexOfLastClosedBefore(ActivityLog cur) {
    final idx = _logs.indexOf(cur);
    for (var i = idx - 1; i >= 0; i--) {
      if (!_logs[i].isOpen) return i;
    }
    return null;
  }

  void _remember(List<ActivityLog> snapshot, DateTime now, bool allowUndo) {
    if (allowUndo) {
      _undoSnapshot = snapshot;
      _lastTapAt = now;
    } else {
      _undoSnapshot = null;
      _lastTapAt = null;
    }
  }
}
