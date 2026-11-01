// .ics(iCalendar) 읽기. 구글·애플·아웃룩 캘린더에서 내보낸 파일을 그대로 읽는다.
// 웹 버전(src/app/ics.ts)과 같은 규칙이다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
//
// 읽는 것: 시각이 있는 일정(SUMMARY, DTSTART/DTEND 또는 DURATION, TZID·UTC·현지 시각),
//          반복 일정(RRULE: DAILY·WEEKLY·MONTHLY·YEARLY, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTHDAY),
//          빠진 날(EXDATE), 한 번만 바뀐 날(RECURRENCE-ID), 취소(STATUS:CANCELLED).
// 빼는 것: 하루 종일 일정(시각이 없어 일정 배치에 쓰지 않는다), '한가함'(TRANSP:TRANSPARENT), 12시간 넘는 일정.
//
// 시간대: Dart에는 시간대 DB가 없다. 웹은 Intl로 모든 TZID를 읽지만, 여기서는 자주 쓰는 시간대만
// 아래 표(_zones)로 계산한다(미국·유럽은 서머타임 규칙 포함). 표에 없는 TZID는 기기 현지 시각으로 읽는다.
// 돌려주는 시각은 모두 기기 현지 시각(DateTime local)이다.

class ImportedEvent {
  const ImportedEvent({required this.uid, required this.title, required this.start, required this.end});

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
}

class IcsSkipped {
  IcsSkipped();

  int allDay = 0;
  int long = 0;
  int free = 0;
}

class IcsResult {
  const IcsResult({required this.calName, required this.events, required this.skipped});

  final String? calName;
  final List<ImportedEvent> events;
  final IcsSkipped skipped;
}

class _Prop {
  const _Prop(this.params, this.value);

  final Map<String, String> params;
  final String value;
}

typedef _Comp = Map<String, List<_Prop>>;

const _windowsTz = {
  'Korea Standard Time': 'Asia/Seoul',
  'Tokyo Standard Time': 'Asia/Tokyo',
  'China Standard Time': 'Asia/Shanghai',
  'UTC': 'UTC',
  'GMT Standard Time': 'Europe/London',
  'Pacific Standard Time': 'America/Los_Angeles',
  'Eastern Standard Time': 'America/New_York',
};

// ---------------------------------------------------------------------------
// 시간대 표
// ---------------------------------------------------------------------------

enum _Dst { none, us, eu }

class _Zone {
  const _Zone(this.std, [this.dst = _Dst.none]);

  /// 표준시 UTC 차이(분).
  final int std;
  final _Dst dst;
}

const _zones = {
  'UTC': _Zone(0),
  'Etc/UTC': _Zone(0),
  'GMT': _Zone(0),
  'Etc/GMT': _Zone(0),
  'Asia/Seoul': _Zone(540),
  'Asia/Tokyo': _Zone(540),
  'Asia/Shanghai': _Zone(480),
  'Asia/Hong_Kong': _Zone(480),
  'Asia/Taipei': _Zone(480),
  'Asia/Singapore': _Zone(480),
  'America/New_York': _Zone(-300, _Dst.us),
  'America/Chicago': _Zone(-360, _Dst.us),
  'America/Denver': _Zone(-420, _Dst.us),
  'America/Los_Angeles': _Zone(-480, _Dst.us),
  'Europe/London': _Zone(0, _Dst.eu),
  'Europe/Paris': _Zone(60, _Dst.eu),
  'Europe/Berlin': _Zone(60, _Dst.eu),
  'Europe/Madrid': _Zone(60, _Dst.eu),
  'Europe/Rome': _Zone(60, _Dst.eu),
  'Europe/Amsterdam': _Zone(60, _Dst.eu),
};

/// 그 달의 n번째 일요일(n = -1이면 마지막 일요일) 날짜.
int _sunday(int year, int month, int n) {
  if (n > 0) {
    final first = DateTime.utc(year, month, 1).weekday % 7; // 일=0
    return 1 + (7 - first) % 7 + (n - 1) * 7;
  }
  final last = DateTime.utc(year, month + 1, 0);
  return last.day - last.weekday % 7;
}

/// utcMs 순간의 그 시간대 UTC 차이(ms).
int _tzOffsetMs(int utcMs, _Zone z) {
  const minute = 60000;
  final y = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).year;
  var summer = false;
  switch (z.dst) {
    case _Dst.none:
      break;
    case _Dst.us:
      // 3월 둘째 일요일 02:00(표준시) ~ 11월 첫째 일요일 02:00(서머타임)
      final start = DateTime.utc(y, 3, _sunday(y, 3, 2), 2).millisecondsSinceEpoch - z.std * minute;
      final end = DateTime.utc(y, 11, _sunday(y, 11, 1), 2).millisecondsSinceEpoch - (z.std + 60) * minute;
      summer = utcMs >= start && utcMs < end;
    case _Dst.eu:
      // 3월 마지막 일요일 01:00 UTC ~ 10월 마지막 일요일 01:00 UTC
      final start = DateTime.utc(y, 3, _sunday(y, 3, -1), 1).millisecondsSinceEpoch;
      final end = DateTime.utc(y, 10, _sunday(y, 10, -1), 1).millisecondsSinceEpoch;
      summer = utcMs >= start && utcMs < end;
  }
  return (z.std + (summer ? 60 : 0)) * minute;
}

DateTime _zoned(int y, int mo, int d, int h, int mi, int s, _Zone z) {
  final guess = DateTime.utc(y, mo, d, h, mi, s).millisecondsSinceEpoch;
  var t = guess - _tzOffsetMs(guess, z);
  t = guess - _tzOffsetMs(t, z); // 서머타임 경계 보정
  return DateTime.fromMillisecondsSinceEpoch(t);
}

_Zone? _validTz(String? tz) {
  if (tz == null || tz.isEmpty) return null;
  final name = _windowsTz[tz] ?? tz.replaceFirst(RegExp(r'^/[^/]+/[^/]+/'), ''); // '/mozilla.org/.../Asia/Seoul' 형태
  return _zones[name];
}

// ---------------------------------------------------------------------------
// 읽기
// ---------------------------------------------------------------------------

String _unescapeText(String v) =>
    v.replaceAll(RegExp(r'\\n', caseSensitive: false), ' ').replaceAllMapped(RegExp(r'\\([,;\\])'), (m) => m[1]!).trim();

({_Comp cal, List<_Comp> events}) _parseComponents(String text) {
  final lines = text.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'\n[ \t]'), '').split('\n');
  final _Comp cal = {};
  final events = <_Comp>[];
  _Comp? cur;
  var depth = 0; // VEVENT 안의 VALARM 같은 하위 블록은 건너뛴다.
  final beginEvent = RegExp(r'^BEGIN:VEVENT$', caseSensitive: false);
  final endEvent = RegExp(r'^END:VEVENT$', caseSensitive: false);
  final begin = RegExp(r'^BEGIN:', caseSensitive: false);
  final end = RegExp(r'^END:', caseSensitive: false);
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    if (beginEvent.hasMatch(line)) {
      cur = {};
      depth = 0;
      continue;
    }
    if (endEvent.hasMatch(line)) {
      if (cur != null) events.add(cur);
      cur = null;
      continue;
    }
    if (cur != null && begin.hasMatch(line)) {
      depth++;
      continue;
    }
    if (cur != null && end.hasMatch(line)) {
      depth = depth > 0 ? depth - 1 : 0;
      continue;
    }
    if (cur != null && depth > 0) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final head = line.substring(0, colon).split(';');
    final name = head[0].toUpperCase();
    final params = <String, String>{};
    for (final p in head.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll(RegExp(r'^"|"$'), '');
    }
    final target = cur ?? cal;
    (target[name] ??= []).add(_Prop(params, line.substring(colon + 1)));
  }
  return (cal: cal, events: events);
}

_Prop? _first(_Comp c, String name) {
  final l = c[name];
  return l == null || l.isEmpty ? null : l.first;
}

class _When {
  const _When(this.allDay, this.date);

  final bool allDay;
  final DateTime date;
}

_When? _parseWhen(String value, Map<String, String> params) {
  final v = value.trim();
  final dOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
  if (dOnly != null || params['VALUE'] == 'DATE') {
    final m = dOnly ?? RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(v);
    if (m == null) return null;
    return _When(true, DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$').firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final h = int.parse(m[4]!);
  final mi = int.parse(m[5]!);
  final s = int.parse(m[6] ?? '0');
  if (m[7] != null) return _When(false, DateTime.utc(y, mo, d, h, mi, s).toLocal());
  final tz = _validTz(params['TZID']);
  return _When(false, tz != null ? _zoned(y, mo, d, h, mi, s, tz) : DateTime(y, mo, d, h, mi, s));
}

int? _parseDuration(String v) {
  final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  int n(int i) => int.parse(m[i] ?? '0');
  final min = (n(2) * 7 + n(3)) * 1440 + n(4) * 60 + n(5) + (n(6) / 60).round();
  return m[1] == '-' ? -min : min;
}

enum _Freq { daily, weekly, monthly, yearly }

class _Rule {
  const _Rule({required this.freq, required this.interval, this.count, this.until, this.byDay, this.byMonthDay});

  final _Freq freq;
  final int interval;
  final int? count;
  final DateTime? until;

  /// 0 = 일요일.
  final List<int>? byDay;
  final List<int>? byMonthDay;
}

const _dayCode = {'SU': 0, 'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6};
const _freqs = {'DAILY': _Freq.daily, 'WEEKLY': _Freq.weekly, 'MONTHLY': _Freq.monthly, 'YEARLY': _Freq.yearly};

_Rule? _parseRule(String v) {
  final kv = <String, String>{};
  for (final p in v.split(';')) {
    final parts = p.split('=');
    kv[parts[0].toUpperCase()] = parts.length > 1 ? parts[1] : '';
  }
  final freq = _freqs[kv['FREQ']];
  if (freq == null) return null;
  DateTime? until;
  final u = kv['UNTIL'];
  if (u != null && u.isNotEmpty) {
    final w = _parseWhen(u, const {});
    // 날짜만 있으면 그날 끝까지 포함한다.
    until = w == null ? null : (w.allDay ? w.date.add(const Duration(milliseconds: 86400000 - 1)) : w.date);
  }
  final bd = kv['BYDAY'];
  final byDay = bd != null && bd.isNotEmpty
      ? [
          for (final d in bd.split(','))
            if (d.length >= 2 && _dayCode[d.substring(d.length - 2).toUpperCase()] != null) _dayCode[d.substring(d.length - 2).toUpperCase()]!,
        ]
      : null;
  final bmd = kv['BYMONTHDAY'];
  final byMonthDay = bmd != null && bmd.isNotEmpty
      ? [
          for (final x in bmd.split(','))
            if ((int.tryParse(x) ?? 0) > 0) int.parse(x),
        ]
      : null;
  final interval = int.tryParse(kv['INTERVAL'] ?? '1') ?? 1;
  final count = kv['COUNT'];
  return _Rule(
    freq: freq,
    interval: interval < 1 ? 1 : interval,
    count: count != null && count.isNotEmpty ? int.tryParse(count) : null,
    until: until,
    byDay: byDay != null && byDay.isNotEmpty ? byDay : null,
    byMonthDay: byMonthDay != null && byMonthDay.isNotEmpty ? byMonthDay : null,
  );
}

DateTime _sameClock(DateTime day, DateTime t) => DateTime(day.year, day.month, day.day, t.hour, t.minute, t.second);

int _dow(DateTime d) => d.weekday % 7; // 일=0

/// 반복 규칙으로 시작 시각들을 만든다(start 포함, 오름차순). to를 넘으면 멈춘다.
List<DateTime> _expand(DateTime start, _Rule rule, DateTime to) {
  final out = <DateTime>[];
  final until = rule.until;
  final limit = until != null && until.isBefore(to) ? until : to;
  bool push(DateTime d) {
    if (d.isBefore(start)) return true;
    if (d.isAfter(limit)) return false;
    if (rule.count != null && out.length >= rule.count!) return false;
    out.add(d);
    return true;
  }

  const max = 3000;
  switch (rule.freq) {
    case _Freq.daily:
      for (var i = 0; i < max; i++) {
        final d = _sameClock(DateTime(start.year, start.month, start.day + i * rule.interval), start);
        if (rule.byDay != null && !rule.byDay!.contains(_dow(d))) continue;
        if (!push(d)) break;
      }
    case _Freq.weekly:
      final days = rule.byDay ?? [_dow(start)];
      final order = [...days]..sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7)); // 월요일부터
      final monday = DateTime(start.year, start.month, start.day - ((_dow(start) + 6) % 7));
      outer:
      for (var w = 0; w < max; w++) {
        for (final wd in order) {
          final d = _sameClock(DateTime(monday.year, monday.month, monday.day + w * 7 * rule.interval + ((wd + 6) % 7)), start);
          if (!push(d)) break outer;
        }
      }
    case _Freq.monthly:
      final mdays = [...(rule.byMonthDay ?? [start.day])]..sort();
      outer:
      for (var i = 0; i < max; i++) {
        for (final md in mdays) {
          final d = _sameClock(DateTime(start.year, start.month + i * rule.interval, md), start);
          if (d.day != md) continue; // 31일이 없는 달은 건너뛴다
          if (!push(d)) break outer;
        }
      }
    case _Freq.yearly:
      for (var i = 0; i < max; i++) {
        final d = _sameClock(DateTime(start.year + i * rule.interval, start.month, start.day), start);
        if (d.day != start.day) continue;
        if (!push(d)) break;
      }
  }
  return out;
}

/// .ics 글을 읽어 from~to 사이에 걸치는 일정만 돌려준다.
IcsResult parseIcs(String text, DateTime from, DateTime to) {
  final parsed = _parseComponents(text);
  final calProp = _first(parsed.cal, 'X-WR-CALNAME');
  final calName = calProp != null && calProp.value.isNotEmpty ? _unescapeText(calProp.value) : null;
  final skipped = IcsSkipped();
  final out = <ImportedEvent>[];
  final seen = <String>{};

  // 한 번만 바뀐 날: uid → 원래 시작 시각(ms)들
  final overridden = <String, Set<int>>{};
  for (final e in parsed.events) {
    final rid = _first(e, 'RECURRENCE-ID');
    final uid = _first(e, 'UID')?.value;
    if (rid == null || uid == null) continue;
    final w = _parseWhen(rid.value, rid.params);
    if (w == null) continue;
    (overridden[uid] ??= {}).add(w.date.millisecondsSinceEpoch);
  }

  for (var idx = 0; idx < parsed.events.length; idx++) {
    final e = parsed.events[idx];
    final ds = _first(e, 'DTSTART');
    if (ds == null) continue;
    final start = _parseWhen(ds.value, ds.params);
    if (start == null) continue;
    if (start.allDay) {
      skipped.allDay++;
      continue;
    }
    if ((_first(e, 'STATUS')?.value ?? '').toUpperCase() == 'CANCELLED') continue;
    if ((_first(e, 'TRANSP')?.value ?? '').toUpperCase() == 'TRANSPARENT') {
      skipped.free++;
      continue;
    }
    final de = _first(e, 'DTEND');
    final endW = de != null ? _parseWhen(de.value, de.params) : null;
    final durProp = _first(e, 'DURATION');
    var minutes = endW != null
        ? ((endW.date.millisecondsSinceEpoch - start.date.millisecondsSinceEpoch) / 60000).round()
        : durProp != null
            ? _parseDuration(durProp.value) ?? 30
            : 30;
    if (minutes <= 0) minutes = 30;
    if (minutes > 12 * 60) {
      skipped.long++;
      continue;
    }
    final uid = _first(e, 'UID')?.value ?? 'noid-$idx';
    final rawTitle = _unescapeText(_first(e, 'SUMMARY')?.value ?? '');
    final title = rawTitle.isEmpty ? '일정' : rawTitle;
    final isOverride = _first(e, 'RECURRENCE-ID') != null;
    final rrProp = _first(e, 'RRULE');
    final rr = !isOverride && rrProp != null ? _parseRule(rrProp.value) : null;

    final ex = <int>{};
    for (final p in e['EXDATE'] ?? const <_Prop>[]) {
      for (final v in p.value.split(',')) {
        final w = _parseWhen(v, p.params);
        if (w != null) ex.add(w.date.millisecondsSinceEpoch);
      }
    }
    final skipStarts = overridden[uid];
    final starts = rr != null ? _expand(start.date, rr, to) : [start.date];
    for (final s in starts) {
      final ms = s.millisecondsSinceEpoch;
      if (ex.contains(ms)) continue;
      if (rr != null && (skipStarts?.contains(ms) ?? false)) continue;
      final end = s.add(Duration(minutes: minutes));
      if (!end.isAfter(from) || !s.isBefore(to)) continue;
      final key = '$uid@$ms';
      if (!seen.add(key)) continue;
      out.add(ImportedEvent(uid: uid, title: title, start: s, end: end));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return IcsResult(calName: calName, events: out, skipped: skipped);
}
