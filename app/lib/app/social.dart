// 친구와 겨루기. 서버 없이 '친구 코드'(DS1-)를 주고받아 이번 주 셋 데이 순위를 본다.
// 웹 버전 src/app/social.ts와 같은 코드 형식이라 웹과 앱이 서로 코드를 읽는다.
// 서버(Supabase)를 붙이면 같은 구조를 올려 실시간 순위로 바꾼다.

import 'dart:convert';

import '../core/model/models.dart';
import 'state.dart';
import 'streak.dart';

const _prefix = 'DS1-';

String _toBase64Url(String text) => base64Url.encode(utf8.encode(text)).replaceAll('=', '');

String _fromBase64Url(String code) {
  final pad = (4 - code.length % 4) % 4;
  return utf8.decode(base64Url.decode(code + '=' * pad));
}

/// 내 기록을 친구 코드로 만든다.
String makeFriendCode({required String id, required String name, required StreakInfo info, required DateTime now, bool anon = false, String? cell}) {
  final payload = <String, Object?>{
    if (anon) 'a': 1,
    if (cell != null) 'c': cell,
    'i': id,
    'n': name,
    's': info.current,
    'b': info.best,
    'w': dateKey(mondayOf(now)),
    'd': info.weekSetDays,
    'm': info.monthSetDays,
    't': now.millisecondsSinceEpoch,
  };
  return _prefix + _toBase64Url(jsonEncode(payload));
}

final _codeRe = RegExp(r'DS1-[A-Za-z0-9_-]{10,}');
final _cellRe = RegExp(r'^-?\d+\.\d{2},-?\d+\.\d{2}$');

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// 붙여 넣은 글에서 친구 코드를 찾아 읽는다. 공유 문구 전체를 붙여 넣어도 된다.
Friend? readFriendCode(String text, {DateTime? now}) {
  final m = _codeRe.firstMatch(text);
  if (m == null) return null;
  try {
    final j = jsonDecode(_fromBase64Url(m[0]!.substring(_prefix.length)));
    if (j is! Map || j['i'] is! String || j['n'] is! String) return null;
    int n(Object? v) => v is num && v.isFinite ? (v < 0 ? 0 : v.round()) : 0;
    final t = n(j['t']);
    final cell = j['c'];
    final name = _cut(j['n'] as String, 20);
    final wsd = n(j['d']);
    final msd = n(j['m']);
    return Friend(
      id: _cut(j['i'] as String, 40),
      name: name.isEmpty ? '친구' : name,
      streak: n(j['s']),
      best: n(j['b']),
      week: j['w'] is String ? _cut(j['w'] as String, 10) : '',
      weekSetDays: wsd > 7 ? 7 : wsd,
      monthSetDays: msd > 31 ? 31 : msd,
      updatedAt: t > 0 ? DateTime.fromMillisecondsSinceEpoch(t) : (now ?? DateTime.now()),
      anon: j['a'] == 1,
      cell: cell is String && _cellRe.hasMatch(cell) ? cell : null,
    );
  } catch (_) {
    return null;
  }
}

class RankRow {
  const RankRow({required this.id, required this.name, required this.me, required this.weekSetDays, required this.streak, required this.stale, this.updatedAt});
  final String id;
  final String name;
  final bool me;
  final int weekSetDays;
  final int streak;

  /// 이번 주 기록이 아니면 지난 기록이라고 표시한다.
  final bool stale;
  final DateTime? updatedAt;
}

int _rankOrder(({int week, int streak, bool me}) a, ({int week, int streak, bool me}) b) {
  if (b.week != a.week) return b.week - a.week;
  if (b.streak != a.streak) return b.streak - a.streak;
  return a.me ? -1 : (b.me ? 1 : 0);
}

/// 이번 주 순위: 셋 데이 수 → 연속 기록 순. 다른 주에 만든 코드는 이번 주 0일로 본다.
List<RankRow> leaderboard({required String id, required String name, required StreakInfo info, required List<Friend> friends, required DateTime now}) {
  final week = dateKey(mondayOf(now));
  final rows = <RankRow>[
    RankRow(id: id, name: name.isEmpty ? '나' : name, me: true, weekSetDays: info.weekSetDays, streak: info.current, stale: false),
    for (final f in friends)
      RankRow(id: f.id, name: f.name, me: false, weekSetDays: f.week == week ? f.weekSetDays : 0, streak: f.streak, stale: f.week != week, updatedAt: f.updatedAt),
  ];
  rows.sort((a, b) => _rankOrder((week: a.weekSetDays, streak: a.streak, me: a.me), (week: b.weekSetDays, streak: b.streak, me: b.me)));
  return rows;
}
