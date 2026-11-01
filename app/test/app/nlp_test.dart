import 'package:dayset/app/nlp.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 19, 21); // 월요일
  Map<String, Object>? p(String t) {
    final r = parseEventText(t, now);
    return r == null ? null : {'title': r.title, 'day': r.start.day, 'start': formatHm(r.start), 'end': formatHm(r.end)};
  }

  group('한 줄 일정 해석', () {
    test('내일 오전 9시 팀 회의 → 20일 09:00~10:00', () {
      expect(p('내일 오전 9시 팀 회의'), equals({'title': '팀 회의', 'day': 20, 'start': '09:00', 'end': '10:00'}));
    });

    test('시간대 말이 없는 3시는 오후, 길이 30분', () {
      expect(p('모레 3시 치과 30분'), equals({'title': '치과', 'day': 21, 'start': '15:00', 'end': '15:30'}));
    });

    test('요일 + 저녁 + 2시간', () {
      expect(p('금요일 저녁 7시 친구 약속 2시간'), equals({'title': '친구 약속', 'day': 23, 'start': '19:00', 'end': '21:00'}));
    });

    test('10:30~12:00 처럼 끝 시각', () {
      expect(p('내일 10:30~12:00 수업'), equals({'title': '수업', 'day': 20, 'start': '10:30', 'end': '12:00'}));
    });

    test('반, 까지, 조사 정리', () {
      expect(p('내일 2시 반부터 4시까지 고객 미팅'), equals({'title': '고객 미팅', 'day': 20, 'start': '14:30', 'end': '16:00'}));
      expect(p('다음주 화요일 오전 11시에 병원'), equals({'title': '병원', 'day': 27, 'start': '11:00', 'end': '12:00'}));
      expect(p('10월 30일 13:00 발표 1시간 반'), equals({'title': '발표', 'day': 30, 'start': '13:00', 'end': '14:30'}));
    });

    test('시각이 없으면 해석하지 않는다', () {
      expect(p('내일 회의'), isNull);
    });

    test('알아들은 것을 칩으로 남긴다', () {
      final r = parseEventText('모레 3시 치과 30분', now)!;
      expect(r.found.date, equals('모레'));
      expect(r.found.time, equals('15:00'));
      expect(r.found.length, equals('30분'));
    });

    test('예시 문장은 모두 해석된다', () {
      for (final e in eventExamples) {
        expect(parseEventText(e, now), isNotNull, reason: e);
      }
    });
  });
}
