import 'dart:convert';

import '../core/model/models.dart';

/// 위젯·단축어가 공유 저장소에 쌓아둔 탭 기록을 읽는다.
///
/// 형식(네이티브 코드와 맞춘다):
/// `[{"activity":"work","at":"2026-10-14T09:00:00+09:00"}, ...]`
/// 알 수 없는 상태나 깨진 항목은 건너뛴다.
List<({Activity activity, DateTime at})> parsePendingEvents(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final out = <({Activity activity, DateTime at})>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    final name = e['activity'];
    final at = e['at'];
    if (name is! String || at is! String) continue;
    final activity = Activity.values.where((a) => a.name == name).firstOrNull;
    final time = DateTime.tryParse(at);
    if (activity == null || time == null) continue;
    out.add((activity: activity, at: time.toLocal()));
  }
  return out;
}
