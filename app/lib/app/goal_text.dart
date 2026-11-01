// 처음 목표 정하기의 '기타': 자유롭게 적은 글에서 목표를 읽는다. 웹 버전 src/app/goalText.ts와 같은 규칙.
// 서버·AI 없이 기기 안에서 규칙으로 읽는다(한 줄 일정 입력 nlp.dart와 같은 방식).
// 읽는 것: 기상 시각, 수면 시간(또는 잠드는 시각), 아침 식사, 운동 종류·시간·시각, 할 일·공부.
// 읽지 못한 부분은 숨기지 않고 그대로 돌려준다(화면에 '아직 자동으로 넣지 못해요'로 보여 준다).

import 'dart:math' as math;

import 'state.dart';

class GoalFound {
  const GoalFound(this.focus, this.text);
  final GoalFocus focus;
  final String text;
}

class GoalReading {
  final List<GoalFocus> focus = [];

  /// 목표 기상 시각(자정 기준 분).
  int? wake;

  /// 목표 수면 시간(분).
  int? sleepMinutes;

  /// 잠드는 시각(자정 기준 분, 다음 날 새벽이면 24시 넘게).
  int? bedtime;
  int? exerciseMinutes;

  /// 운동 이름(예: 달리기).
  String? exerciseTitle;

  /// 운동 시각(자정 기준 분).
  int? exerciseStart;

  /// 알아들은 것(화면 칩).
  final List<GoalFound> found = [];

  /// 읽지 못한 부분.
  final List<String> unknown = [];
}

const _native = [
  ('열두', 12), ('열한', 11), ('열', 10), ('아홉', 9), ('여덟', 8), ('일곱', 7),
  ('여섯', 6), ('다섯', 5), ('네', 4), ('세', 3), ('두', 2), ('한', 1),
];

/// 한글 수 말(한 시간·세 시)을 숫자로. 채팅 읽기도 쓴다.
String nativeNumbers(String text) {
  var t = text;
  for (final (w, n) in _native) {
    t = t.replaceAllMapped(RegExp('$w\\s*(시간|시)'), (m) => '$n${m[1]}');
  }
  return t;
}

final _split = RegExp(r'[,，.。!?！？\n·;/]|그리고|또한|(?<=[가-힣])(?:하고|고|며|면서|서|랑|이랑)\s+');
final _filler = RegExp(r'(하고\s*싶어요?|하고\s*싶다|싶어요?|싶다|싶음|싶고|하기|해요|할래요?|매일|매일매일|꾸준히|좀|더|많이|습관|만들기|만들고|정도|쯤|이상|목표|잘|제대로|최대한|있게|되게|되기|수\s*있게|요(?=\s|$)|\s)+');

/// 운동 이름 말 → 표시 이름. 채팅 읽기도 쓴다.
final goalExercises = <(RegExp, String)>[
  (RegExp(r'러닝|달리기|조깅|뛰기|달리'), '달리기'),
  (RegExp(r'헬스|웨이트|근력|근육'), '헬스'),
  (RegExp(r'필라테스'), '필라테스'),
  (RegExp(r'요가'), '요가'),
  (RegExp(r'수영'), '수영'),
  (RegExp(r'스트레칭'), '스트레칭'),
  (RegExp(r'홈트'), '홈트'),
  (RegExp(r'산책|걷기|만보|걷'), '걷기'),
  (RegExp(r'자전거|라이딩'), '자전거'),
  (RegExp(r'등산'), '등산'),
  (RegExp(r'줄넘기'), '줄넘기'),
  (RegExp(r'클라이밍'), '클라이밍'),
  (RegExp(r'운동|체력|다이어트|살\s*빼'), '운동'),
];

final _taskWords = RegExp(r'공부|과제|숙제|업무|미루|할\s*일|집중|시험|토익|토플|자격증|프로젝트|작업|코딩|레포트|리포트|마감');
final _wakeWords = RegExp(r'일어나|일어남|기상|늦잠|아침형|미라클\s*모닝|깨기|깨고|눈\s*뜨');
final _sleepWords = RegExp(r'잠|수면|자기|자고|자는|잘\s*자|취침|잠들|밤샘|밤새|일찍\s*자|늦게\s*자|숙면|\d\s*시간\s*(이상\s*)?자|[\s에]자$');
final _breakfast = RegExp(r'아침[^\d,]{0,5}?(밥|식사|먹|챙기|챙겨|거르)|조식|아침밥');
final _am = RegExp(r'오전|아침|새벽');
final _pm = RegExp(r'오후|저녁|밤');
final _clockRe = RegExp(r'(오전|오후|아침|저녁|밤|새벽)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(?:(반)|(\d{1,2})\s*분)?)(?!\s*간)');

({int h, int m, bool am, bool pm})? _readClock(String clause) {
  final m = _clockRe.firstMatch(clause);
  if (m == null) return null;
  final h = int.parse(m[2]!);
  if (h > 24) return null;
  final min = m[3] != null ? int.parse(m[3]!) : (m[4] != null ? 30 : (m[5] != null ? int.parse(m[5]!) : 0));
  if (min > 59) return null;
  final w = m[1];
  return (h: h, m: min, am: w != null && _am.hasMatch(w), pm: w != null && _pm.hasMatch(w));
}

int? _readHours(String clause) {
  final m = RegExp(r'(\d{1,2}(?:\.\d)?)\s*시간\s*(반)?').firstMatch(clause);
  return m == null ? null : (double.parse(m[1]!) * 60 + (m[2] != null ? 30 : 0)).round();
}

int? _readLength(String clause) {
  final min = RegExp(r'(\d{1,3})\s*분').firstMatch(clause);
  if (min != null) return int.parse(min[1]!);
  return _readHours(clause);
}

int _clamp(int v, int lo, int hi) => math.min(hi, math.max(lo, v));

/// JS Math.round와 같게(.5는 위로).
int _jsRound(num v) => (v + 0.5).floor();
int _round5(int v) => _jsRound(v / 5) * 5;

String _hm(int v) {
  final m = ((v % 1440) + 1440) % 1440;
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

String _hoursText(int min) => min % 60 != 0 ? '${min ~/ 60}시간 ${min % 60}분' : '${min ~/ 60}시간';

GoalReading readGoalText(String input) {
  final r = GoalReading();
  var text = nativeNumbers(input.trim());
  if (text.length > 300) text = text.substring(0, 300);
  if (text.isEmpty) return r;
  void add(GoalFocus f) {
    if (!r.focus.contains(f)) r.focus.add(f);
  }

  for (final raw in text.split(_split)) {
    final clause = raw.trim();
    if (clause.isEmpty) continue;
    var hit = false;

    // 아침 식사(기상 시각 '아침 6시'와 헷갈리지 않게 먼저 본다)
    if (_breakfast.hasMatch(clause)) {
      add(GoalFocus.breakfast);
      hit = true;
    }

    // 운동
    final ex = goalExercises.where((e) => e.$1.hasMatch(clause)).firstOrNull;
    if (ex != null) {
      add(GoalFocus.exercise);
      hit = true;
      if (ex.$2 != '운동' || r.exerciseTitle == null) r.exerciseTitle = ex.$2;
      final len = _readLength(clause);
      if (len != null && len > 0) r.exerciseMinutes = _clamp(_round5(len), 10, 120);
      final c = _readClock(clause.replaceAll(RegExp(r'\d{1,3}\s*분'), ''));
      if (c != null) {
        // 운동 시각: 낮·밤 말이 없으면 1~11시는 오후로 본다. '아침·새벽'이면 오전.
        final h = c.am ? c.h % 12 : (c.pm || (c.h >= 1 && c.h <= 11)) ? (c.h % 12) + 12 : c.h;
        r.exerciseStart = (h % 24) * 60 + c.m;
      }
    }

    // 기상
    if (_wakeWords.hasMatch(clause)) {
      add(GoalFocus.wake);
      hit = true;
      final c = _readClock(clause);
      if (c != null) {
        final h = c.pm && c.h < 12 ? c.h + 12 : c.h;
        r.wake = _clamp(h * 60 + c.m, 4 * 60, 12 * 60);
      }
    }

    // 수면
    if (_sleepWords.hasMatch(clause.replaceAll('늦잠', ''))) {
      add(GoalFocus.sleep);
      hit = true;
      final hrs = _readHours(clause);
      if (hrs != null && hrs >= 180 && hrs <= 12 * 60) {
        r.sleepMinutes = _clamp(_jsRound(hrs / 30) * 30, 300, 600);
      } else {
        final c = _readClock(clause);
        if (c != null) {
          // 잠드는 시각: 7~11시는 밤, 12시는 자정, 1~4시는 새벽(다음 날).
          var h = c.h;
          if (c.am || (!c.pm && h >= 0 && h <= 4)) {
            h = h % 12 + 24;
          } else if (h == 12) {
            h = 24;
          } else if (h < 12) {
            h += 12;
          }
          r.bedtime = h * 60 + c.m;
        }
      }
    }

    // 할 일·공부
    if (_taskWords.hasMatch(clause)) {
      add(GoalFocus.tasks);
      hit = true;
    }

    if (!hit) {
      final rest = clause.replaceAll(_filler, '');
      if (RegExp(r'[가-힣a-zA-Z]{2,}').hasMatch(rest)) {
        r.unknown.add(clause.replaceAll(RegExp(r'\s*(하고\s*)?싶(어요?|다|음|고)\s*$'), '').trim());
      }
    }
  }

  // 잠드는 시각만 적었으면 기상 목표(없으면 7시)와의 차이로 수면 시간을 정한다.
  if (r.sleepMinutes == null && r.bedtime != null) {
    final span = (r.wake ?? 7 * 60) + 24 * 60 - r.bedtime!;
    if (span >= 300 && span <= 600) r.sleepMinutes = _jsRound(span / 30) * 30;
  }

  r.focus.sort((a, b) => a.index - b.index);
  for (final f in r.focus) {
    final text = switch (f) {
      GoalFocus.wake => '일찍 일어나기${r.wake != null ? ' · ${_hm(r.wake!)} 기상' : ''}',
      GoalFocus.sleep =>
        '충분히 자기${r.sleepMinutes != null ? ' · ${_hoursText(r.sleepMinutes!)}' : ''}${r.bedtime != null ? ' · ${_hm(r.bedtime!)} 취침' : ''}',
      GoalFocus.breakfast => '아침 챙겨 먹기',
      GoalFocus.exercise =>
        '운동 습관 · ${r.exerciseTitle ?? '운동'}${r.exerciseMinutes != null ? ' ${r.exerciseMinutes}분' : ''}${r.exerciseStart != null ? ' · ${_hm(r.exerciseStart!)}' : ''}',
      GoalFocus.tasks => '할 일 미루지 않기',
    };
    r.found.add(GoalFound(f, text));
  }
  return r;
}

/// 입력 예시(칩으로 보여 준다).
const goalExamples = ['6시 반에 일어나고 저녁 8시에 30분 달리기', '11시 전에 자고 7시간 반 자기', '아침 꼭 챙겨 먹고 토익 공부 미루지 않기'];
