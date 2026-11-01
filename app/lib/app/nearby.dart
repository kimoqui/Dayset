// 근처 사람들과 익명으로 겨루기. 웹 버전 src/app/nearby.ts와 같은 규칙.
//
// 개인정보 원칙
//  - 실명·사진·정확한 위치는 쓰지 않는다. 기기마다 정해지는 익명 별명(예: '새벽 수달 #284')만 보인다.
//  - 위치는 사용자가 켰을 때만 읽고, 위도·경도를 약 2km 칸으로 뭉개서 칸 이름만 저장한다.
//  - 서버가 없을 때는 가까이 있는 사람과 QR·코드를 직접 주고받아 보드에 올린다.

import '../core/model/models.dart';
import 'state.dart';
import 'streak.dart';

const _adj = ['새벽', '부지런한', '차분한', '느긋한', '반짝이는', '꾸준한', '용감한', '산뜻한', '단단한', '포근한', '씩씩한', '고요한'];
const _animal = ['수달', '고래', '여우', '부엉이', '다람쥐', '펭귄', '판다', '고양이', '사슴', '토끼', '거북이', '참새'];

/// FNV-1a 32비트(웹과 같은 값). 문자는 UTF-16 단위로 섞는다.
int fnv1a(String text) {
  var h = 2166136261;
  for (final c in text.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// 기기마다 고정되는 익명 별명. 실명과 연결되지 않는다.
String anonName(String deviceId) {
  final h = fnv1a(deviceId);
  return '${_adj[h % _adj.length]} ${_animal[(h >> 8) % _animal.length]} #${((h >> 16) % 1000).toString().padLeft(3, '0')}';
}

/// 위도·경도를 약 2km 칸으로 뭉갠다(0.02도 ≈ 위도 2.2km). 정확한 위치는 남기지 않는다.
String cellOf(double lat, double lon) {
  String r(double v) => ((v / 0.02).floor() * 0.02).toStringAsFixed(2);
  return '${r(lat)},${r(lon)}';
}

/// 두 칸 사이 거리대. 같은 칸 = 2km 안, 바로 옆 칸 = 4km 안.
String? distanceBand(String? a, String? b) {
  if (a == null || b == null) return null;
  final pa = a.split(',').map(double.tryParse).toList();
  final pb = b.split(',').map(double.tryParse).toList();
  if (pa.length != 2 || pb.length != 2 || pa.contains(null) || pb.contains(null)) return null;
  final dLat = (pa[0]! - pb[0]!).abs();
  final dLon = (pa[1]! - pb[1]!).abs();
  final d = (dLat > dLon ? dLat : dLon) / 0.02;
  if (d < 0.5) return '2km 안';
  if (d < 1.5) return '4km 안';
  if (d < 3.5) return '8km 안';
  return '멀리';
}

class NearbyRow {
  const NearbyRow({required this.id, required this.name, required this.me, required this.weekSetDays, required this.streak, this.band, this.demo = false});
  final String id;
  final String name;
  final bool me;
  final int weekSetDays;
  final int streak;
  final String? band;
  final bool demo;
}

class NearbyBoard {
  const NearbyBoard({required this.rows, required this.myRank, required this.topPercent, required this.avgWeek});
  final List<NearbyRow> rows;
  final int myRank;

  /// 상위 몇 %인지(1~100).
  final int topPercent;
  final double avgWeek;
}

NearbyBoard nearbyBoard(String deviceId, StreakInfo info, NearbyState n, DateTime now) {
  final week = dateKey(mondayOf(now));
  final rows = <NearbyRow>[
    NearbyRow(id: deviceId, name: anonName(deviceId), me: true, weekSetDays: info.weekSetDays, streak: info.current),
    for (final p in n.people)
      NearbyRow(id: p.id, name: p.name, me: false, weekSetDays: p.week == week ? p.weekSetDays : 0, streak: p.streak, band: distanceBand(n.cell, p.cell), demo: p.demo),
  ];
  rows.sort((a, b) {
    if (b.weekSetDays != a.weekSetDays) return b.weekSetDays - a.weekSetDays;
    if (b.streak != a.streak) return b.streak - a.streak;
    return a.me ? -1 : (b.me ? 1 : 0);
  });
  final myRank = rows.indexWhere((r) => r.me) + 1;
  final avg = rows.fold<int>(0, (s, r) => s + r.weekSetDays) / rows.length;
  final top = (myRank / rows.length * 100).round();
  return NearbyBoard(rows: rows, myRank: myRank, topPercent: top < 1 ? 1 : top, avgWeek: avg);
}
