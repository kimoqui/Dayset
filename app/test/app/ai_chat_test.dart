import 'dart:convert';

import 'package:dayset/app/ai_chat.dart';
import 'package:dayset/app/cloud.dart';
import 'package:dayset/app/edits.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 웹 src/app/__tests__/aiChat.test.ts를 옮긴 것.
void main() {
  final now = DateTime(2026, 11, 2, 9, 0); // 월요일 오전 9시
  final s = demoState(now);
  final today = dateKey(now);
  final tomorrow = dateKey(addDays(now, 1));

  group('서버 AI 답 읽기', () {
    test('요약에 습관·사흘 일정·일정 id가 들어간다', () {
      final c = aiContext(s, now);
      expect(c['now'], '${today}T09:00');
      expect(c['weekday'], '월');
      expect(c['habits'] as List, contains('운동'));
      final days = c['days'] as List;
      expect(days, hasLength(3));
      expect((days.first as Map)['habits'] as List, isNotEmpty);
      for (final e in c['events'] as List) {
        expect(s.events.any((x) => x.id == (e as Map)['id']), isTrue);
      }
      // 서버로 보낼 수 있는 JSON이어야 한다.
      expect(jsonEncode(c), isA<String>());
    });

    test('맞는 항목은 바꾸기 목록으로 바꾼다', () {
      final r = readAiReply({
        'reply': '내일 운동을 저녁 9시로 옮길게요.',
        'edits': [
          {'kind': 'habit', 'day': tomorrow, 'title': '운동', 'start': '21:00', 'scope': 'day'},
          {'kind': 'wake', 'day': tomorrow, 'start': '06:30', 'scope': 'every'},
          {'kind': 'event-add', 'title': '치과', 'start': '${tomorrow}T15:00', 'end': '${tomorrow}T16:00'},
          {'kind': 'task-add', 'title': '보고서', 'minutes': 120, 'taskType': 'work', 'due': tomorrow},
        ],
      }, s, now)!;
      expect(r.reply, '내일 운동을 저녁 9시로 옮길게요.');
      expect(r.edits, hasLength(4));
      final h = r.edits[0] as HabitChange;
      expect((h.day, h.title, h.patch, h.scope), (tomorrow, '운동', const HabitEdit(start: 21 * 60), EditScope.day));
      final w = r.edits[1] as WakeChange;
      expect((w.day, w.minutes, w.scope), (tomorrow, 390, EditScope.every));
      final a = r.edits[2] as EventAdd;
      expect((a.title, a.start, a.end), ('치과', DateTime(2026, 11, 3, 15), DateTime(2026, 11, 3, 16)));
      final t = r.edits[3] as TaskAdd;
      expect((t.title, t.minutes, t.type, t.dueAt), ('보고서', 120, TaskType.work, DateTime(2026, 11, 3, 23)));
    });

    test('없는 습관·없는 일정·지난 날·이상한 시각은 버리고 알려 준다', () {
      final r = readAiReply({
        'reply': '바꿀게요.',
        'edits': [
          {'kind': 'habit', 'day': today, 'title': '명상', 'start': '07:00'},
          {'kind': 'event-delete', 'id': 'nope'},
          {'kind': 'habit', 'day': dateKey(addDays(now, -1)), 'title': '운동', 'skip': true},
          {'kind': 'wake', 'day': today, 'start': '25:00'},
          {'kind': 'drop-table'},
        ],
      }, s, now)!;
      expect(r.edits, isEmpty);
      expect(r.unknown, ['명상', '일정', '지난 날', '기상 시각']);
      expect(r.reply, contains('바꿀 수 없는 것은 뺐어요'));
    });

    test('가져온 캘린더 일정은 옮기거나 지우지 않는다', () {
      final ev = FixedEvent(id: 'g1', title: '수업', start: DateTime(2026, 11, 3, 10), end: DateTime(2026, 11, 3, 11), source: 'google');
      final st = s.copyWith(events: [...s.events, ev]);
      final r = readAiReply({
        'reply': '',
        'edits': [
          {'kind': 'event-delete', 'id': 'g1'},
          {'kind': 'event-move', 'id': 'g1', 'start': '${tomorrow}T12:00', 'end': '${tomorrow}T13:00'},
        ],
      }, st, now)!;
      expect(r.edits, isEmpty);
    });

    test('형식이 틀리면 null(기기 안 규칙으로 읽는다)', () {
      expect(readAiReply(null, s, now), isNull);
      expect(readAiReply('hello', s, now), isNull);
      expect(readAiReply({'edits': 'x'}, s, now), isNull);
    });

    test('클라이언트는 로그인 토큰으로 서버 함수를 부른다', () async {
      ({String method, Uri url, String auth, Object? body})? seen;
      final c = CloudClient(const CloudConfig(url: 'https://x.supabase.co', key: 'pk'), (method, url, headers, body) async {
        seen = (method: method, url: url, auth: headers['Authorization']!, body: jsonDecode(body!));
        return (status: 200, body: jsonEncode({'reply': 'ok', 'edits': []}));
      });
      const session = Session(accessToken: 'tok', refreshToken: 'r', expiresAt: 1 << 50, userId: 'u', email: 'a@b.c');
      final out = await c.askChat(session, '내일 운동 빼줘', {'now': 'x'});
      expect(out, {'reply': 'ok', 'edits': []});
      expect(seen!.method, 'POST');
      expect(seen!.url.toString(), 'https://x.supabase.co/functions/v1/dayset-chat');
      expect(seen!.auth, 'Bearer tok');
      expect(seen!.body, {'text': '내일 운동 빼줘', 'context': {'now': 'x'}});
    });
  });
}
