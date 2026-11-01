import 'package:dayset/app/ics.dart';
import 'package:flutter_test/flutter_test.dart';

// 웹 테스트(__tests__/auto.test.ts '.ics 가져오기')와 같은 파일.
final _ics = [
  r'BEGIN:VCALENDAR',
  r'VERSION:2.0',
  r'X-WR-CALNAME:내 캘린더',
  r'BEGIN:VTIMEZONE',
  r'TZID:Asia/Seoul',
  r'BEGIN:STANDARD',
  r'TZOFFSETFROM:+0900',
  r'TZOFFSETTO:+0900',
  r'DTSTART:19700101T000000',
  r'END:STANDARD',
  r'END:VTIMEZONE',
  r'BEGIN:VEVENT',
  r'UID:once@x',
  r'DTSTART;TZID=Asia/Seoul:20261020T100000',
  r'DTEND;TZID=Asia/Seoul:20261020T113000',
  r'SUMMARY:팀 회의\, 주간',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:utc@x',
  r'DTSTART:20261021T050000Z',
  r'DURATION:PT45M',
  r'SUMMARY:점심 약속',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:class@x',
  r'DTSTART;TZID=Asia/Seoul:20261005T090000',
  r'DTEND;TZID=Asia/Seoul:20261005T103000',
  r'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261130T000000Z',
  r'EXDATE;TZID=Asia/Seoul:20261021T090000',
  r'SUMMARY:경영학원론',
  r'BEGIN:VALARM',
  r'ACTION:DISPLAY',
  r'DESCRIPTION:알림',
  r'TRIGGER:-PT10M',
  r'END:VALARM',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:class@x',
  r'RECURRENCE-ID;TZID=Asia/Seoul:20261026T090000',
  r'DTSTART;TZID=Asia/Seoul:20261026T130000',
  r'DTEND;TZID=Asia/Seoul:20261026T143000',
  r'SUMMARY:경영학원론(보강)',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:allday@x',
  r'DTSTART;VALUE=DATE:20261022',
  r'DTEND;VALUE=DATE:20261023',
  r'SUMMARY:휴가',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:free@x',
  r'DTSTART:20261022T010000Z',
  r'DTEND:20261022T020000Z',
  r'TRANSP:TRANSPARENT',
  r'SUMMARY:참고',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:cancel@x',
  r'STATUS:CANCELLED',
  r'DTSTART:20261022T030000Z',
  r'DTEND:20261022T040000Z',
  r'SUMMARY:취소됨',
  r'END:VEVENT',
  r'BEGIN:VEVENT',
  r'UID:daily@x',
  r'DTSTART;TZID=Asia/Seoul:20261019T070000',
  r'DTEND;TZID=Asia/Seoul:20261019T073000',
  r'RRULE:FREQ=DAILY;COUNT=3',
  r'SUMMARY:아침 스터디',
  r'END:VEVENT',
  r'END:VCALENDAR',
].join('\r\n');

String _p2(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime d) => '${d.month}/${d.day} ${_p2(d.hour)}:${_p2(d.minute)}';

void main() {
  // 시각은 한국 시간으로 비교한다(기기 시간대와 상관없이).
  DateTime kst(DateTime d) => d.toUtc().add(const Duration(hours: 9));
  final from = DateTime.utc(2026, 10, 18, 15); // 10/19 00:00 KST
  final to = DateTime.utc(2026, 11, 1, 15); // 11/2 00:00 KST

  group('.ics 가져오기', () {
    final r = parseIcs(_ics, from, to);
    final list = [for (final e in r.events) '${_fmt(kst(e.start))}-${_fmt(kst(e.end)).substring(_fmt(kst(e.end)).length - 5)} ${e.title}'];

    test('시간대·UTC·기간·이스케이프를 읽는다', () {
      expect(r.calName, equals('내 캘린더'));
      expect(list, contains('10/20 10:00-11:30 팀 회의, 주간'));
      expect(list, contains('10/21 14:00-14:45 점심 약속'));
    });

    test('반복 일정을 펼치고, 빠진 날과 바뀐 날을 반영한다', () {
      final cls = list.where((x) => x.contains('경영학원론')).toList();
      expect(cls, equals(['10/19 09:00-10:30 경영학원론', '10/26 13:00-14:30 경영학원론(보강)', '10/28 09:00-10:30 경영학원론']));
      expect(list.where((x) => x.contains('아침 스터디')).toList(), hasLength(3));
    });

    test('하루 종일·한가함·취소 일정은 빼고 센다', () {
      expect(list.any((x) => RegExp('휴가|참고|취소됨').hasMatch(x)), isFalse);
      expect(r.skipped.allDay, equals(1));
      expect(r.skipped.free, equals(1));
    });
  });

  group('시간대 표', () {
    String one(String tz, String local) => [
          'BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'UID:a', 'DTSTART;TZID=$tz:$local', 'DURATION:PT1H', 'SUMMARY:x', 'END:VEVENT', 'END:VCALENDAR',
        ].join('\n');
    DateTime utcOf(String tz, String local) =>
        parseIcs(one(tz, local), DateTime.utc(2000), DateTime.utc(2100)).events.single.start.toUtc();

    test('미국 서머타임: 7월은 −4시간, 1월은 −5시간', () {
      expect(utcOf('America/New_York', '20260715T090000'), equals(DateTime.utc(2026, 7, 15, 13)));
      expect(utcOf('America/New_York', '20260115T090000'), equals(DateTime.utc(2026, 1, 15, 14)));
    });

    test('유럽 서머타임: 파리 7월은 +2시간, 1월은 +1시간', () {
      expect(utcOf('Europe/Paris', '20260715T090000'), equals(DateTime.utc(2026, 7, 15, 7)));
      expect(utcOf('Europe/Paris', '20260115T090000'), equals(DateTime.utc(2026, 1, 15, 8)));
    });

    test('윈도우 이름·모질라 경로도 읽는다', () {
      expect(utcOf('Korea Standard Time', '20261020T100000'), equals(DateTime.utc(2026, 10, 20, 1)));
      expect(utcOf('/mozilla.org/20070129_1/Asia/Seoul', '20261020T100000'), equals(DateTime.utc(2026, 10, 20, 1)));
    });

    test('표에 없는 시간대는 기기 현지 시각으로 읽는다', () {
      expect(utcOf('Mars/Olympus', '20261020T100000'), equals(DateTime(2026, 10, 20, 10).toUtc()));
    });
  });

  group('반복 규칙', () {
    String rule(String rr, {String start = '20261001T090000'}) => [
          'BEGIN:VCALENDAR', 'BEGIN:VEVENT', 'UID:r', 'DTSTART:$start', 'DTEND:${start.substring(0, 9)}100000', 'RRULE:$rr', 'SUMMARY:반복', 'END:VEVENT', 'END:VCALENDAR',
        ].join('\n');
    List<int> days(String rr, {String start = '20261001T090000'}) =>
        [for (final e in parseIcs(rule(rr, start: start), DateTime(2026, 1, 1), DateTime(2027, 6, 1)).events) e.start.day];

    test('매달 31일은 31일이 없는 달을 건너뛴다', () {
      expect(days('FREQ=MONTHLY;COUNT=4', start: '20261031T090000'), equals([31, 31, 31, 31]));
    });

    test('INTERVAL과 UNTIL(날짜만)을 따른다', () {
      expect(days('FREQ=DAILY;INTERVAL=2;UNTIL=20261007'), equals([1, 3, 5, 7]));
    });

    test('12시간 넘는 일정은 빼고 센다', () {
      final t = ['BEGIN:VEVENT', 'UID:l', 'DTSTART:20261020T000000Z', 'DTEND:20261020T130000Z', 'END:VEVENT'].join('\n');
      final r = parseIcs(t, DateTime(2026), DateTime(2027));
      expect(r.events, isEmpty);
      expect(r.skipped.long, equals(1));
    });
  });
}
