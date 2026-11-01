// 한 줄 일정 입력 해석: "내일 오전 9시 팀 회의 1시간" → 날짜·시작·끝·제목.
// 서버·AI 없이 규칙으로 읽는다. 대화형 비서(AI)가 나오기 전까지 쓰는 빠른 입력이다.
// 웹 버전(src/app/nlp.ts)과 같은 규칙이다. 한쪽을 바꾸면 다른 쪽도 맞춘다.

import '../core/model/models.dart';

/// 무엇을 알아들었는지(화면에 칩으로 보여 준다).
class ParsedFound {
  const ParsedFound({this.date, this.time, this.length});

  final String? date;
  final String? time;
  final String? length;
}

class ParsedEvent {
  const ParsedEvent({required this.title, required this.start, required this.end, required this.found});

  final String title;
  final DateTime start;
  final DateTime end;
  final ParsedFound found;
}

const _dayWords = {'오늘': 0, '내일': 1, '모레': 2, '글피': 3};
const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

String _p2(int n) => n.toString().padLeft(2, '0');

ParsedEvent? parseEventText(String input, DateTime now) {
  var text = ' ${input.trim()} ';
  if (text.trim().isEmpty) return null;
  String? fDate;
  String? fTime;
  String? fLength;
  void cut(RegExpMatch m) => text = text.replaceFirst(m[0]!, ' ');

  // 1) 날짜
  var day = dayStart(now);
  RegExpMatch? m = RegExp(r'(오늘|내일|모레|글피)').firstMatch(text);
  if (m != null) {
    day = addDays(day, _dayWords[m[1]]!);
    fDate = m[1];
    cut(m);
  } else if ((m = RegExp(r'(이번\s*주|다음\s*주)?\s*([월화수목금토일])요일').firstMatch(text)) != null) {
    final target = _weekdays.indexOf(m![2]!);
    final mon = addDays(day, -(day.weekday - 1));
    final idx = (target + 6) % 7; // 월=0
    var d = addDays(mon, idx + ((m[1]?.startsWith('다음') ?? false) ? 7 : 0));
    if (m[1] == null && d.isBefore(day)) d = addDays(d, 7);
    day = d;
    fDate = '${m[1] != null ? '${m[1]!.replaceAll(RegExp(r'\s'), ' ')} ' : ''}${m[2]}요일';
    cut(m);
  } else if ((m = RegExp(r'(\d{1,2})\s*월\s*(\d{1,2})\s*일').firstMatch(text)) != null ||
      (m = RegExp(r'\b(\d{1,2})/(\d{1,2})\b').firstMatch(text)) != null) {
    final mo = int.parse(m![1]!);
    final d = int.parse(m[2]!);
    day = DateTime(now.year, mo, d);
    if (day.isBefore(dayStart(now))) day = DateTime(now.year + 1, mo, d);
    fDate = '$mo월 $d일';
    cut(m);
  }

  // 2) 시작 시각
  int? startMin;
  int ampm(String? word, int h) {
    if (word != null && RegExp(r'오후|저녁|밤').hasMatch(word) && h < 12) return h + 12;
    if (word != null && RegExp(r'오전|아침|새벽').hasMatch(word) && h == 12) return 0;
    if (word != null && word.contains('낮') && h < 7) return h + 12;
    // 시간대 말이 없으면 1~7시는 오후로 본다("3시 회의" = 15시).
    if (word == null && h >= 1 && h <= 7) return h + 12;
    return h;
  }

  if ((m = RegExp(r'(오전|오후|아침|저녁|밤|낮|새벽)?\s*(\d{1,2}):(\d{2})').firstMatch(text)) != null) {
    startMin = ampm(m![1], int.parse(m[2]!)) * 60 + int.parse(m[3]!);
    cut(m);
  } else if ((m = RegExp(r'(오전|오후|아침|저녁|밤|낮|새벽)?\s*(\d{1,2})\s*시\s*(반|(\d{1,2})\s*분)?(?!\s*간)').firstMatch(text)) != null) {
    final min = m![3] == '반' ? 30 : (m[4] != null ? int.parse(m[4]!) : 0);
    startMin = ampm(m[1], int.parse(m[2]!)) * 60 + min;
    cut(m);
  }
  if (startMin != null) fTime = '${_p2((startMin ~/ 60) % 24)}:${_p2(startMin % 60)}';

  // 3) 끝 시각("~11시", "11시까지") 또는 길이("1시간 반", "90분")
  var length = 60;
  int? endMin;
  if ((m = RegExp(r'(?:~|-|부터)?\s*(오전|오후|저녁|밤)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(반)?)\s*까지').firstMatch(text)) != null ||
      (m = RegExp(r'~\s*(오전|오후|저녁|밤)?\s*(\d{1,2})(?::(\d{2})|\s*시\s*(반)?)?').firstMatch(text)) != null) {
    var h = int.parse(m![2]!);
    if (m[1] != null) {
      h = ampm(m[1], h);
    } else if (startMin != null && h * 60 <= startMin) {
      h += 12;
    }
    endMin = h * 60 + (m[3] != null ? int.parse(m[3]!) : (m[4] != null ? 30 : 0));
    cut(m);
  } else if ((m = RegExp(r'(\d{1,2})\s*시간\s*(반)?').firstMatch(text)) != null) {
    length = int.parse(m![1]!) * 60 + (m[2] != null ? 30 : 0);
    fLength = '${m[1]}시간${m[2] != null ? ' 반' : ''}';
    cut(m);
  } else if ((m = RegExp(r'(\d{2,3})\s*분').firstMatch(text)) != null) {
    length = int.parse(m![1]!);
    fLength = '$length분';
    cut(m);
  }
  if (startMin == null) return null;
  if (endMin != null && endMin > startMin) {
    length = endMin - startMin;
    fLength = '$fTime~${_p2((endMin ~/ 60) % 24)}:${_p2(endMin % 60)}';
  }

  // 4) 제목: 남은 말에서 조사·잡음을 걷어 낸다.
  var title = text
      .replaceAll(RegExp(r'\s(에|부터|까지|에서|동안|쯤|정도)(?=\s)'), ' ')
      .replaceAllMapped(RegExp(r'(\S)(에|부터|까지)\s'), (x) => '${x[1]} ')
      .replaceAll(RegExp(r'[~,.]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (title.isEmpty) title = '일정';

  final start = addMin(day, startMin);
  return ParsedEvent(
    title: title,
    start: start,
    end: addMin(start, length < 10 ? 10 : length),
    found: ParsedFound(date: fDate, time: fTime, length: fLength),
  );
}

/// 입력 예시(칩으로 보여 준다).
const eventExamples = ['내일 오전 9시 팀 회의', '모레 3시 치과 30분', '금요일 저녁 7시 친구 약속 2시간', '내일 10:30~12:00 수업'];
