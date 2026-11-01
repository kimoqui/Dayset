// 캘린더 가져오기: .ics 파일, 연결된 캘린더 관리. 웹 버전 src/ui/CalendarConnect.tsx·src/app/calendarSync.ts와 같은 규칙.
// 원칙: 가져오기에 실패해도 이전에 가져온 일정은 지우지 않고 그대로 일정을 짠다.
// 앱 1단계는 .ics 파일만 받는다. 기기 캘린더(구글·애플) 연결은 다음 업데이트에서 붙인다.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/ics.dart';
import '../app/state.dart';
import '../app/store.dart';
import '../core/model/models.dart';
import '../platform/share.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

const _maxIcsBytes = 5 * 1024 * 1024;

/// 이보다 오래 못 가져오면 '오래됨'으로 알린다.
const _stale = Duration(hours: 24);

/// 캘린더 가져오기 창(.ics 파일).
Future<void> showCalendarSheet(BuildContext context) => showDsSheet(context, title: '캘린더 가져오기', builder: (_) => const _CalendarSheet());

String _ago(DateTime d, DateTime t) {
  final m = (t.difference(d).inMilliseconds / 60000).round();
  if (m < 1) return '방금';
  if (m < 60) return '$m분 전';
  if (m < 24 * 60) return '${(m / 60).round()}시간 전';
  return '${koreanDate(d)} ${formatHm(d)}';
}

String _summary(ImportOutcome o, IcsSkipped skipped, String what) {
  final notes = <String>[
    if (skipped.allDay > 0) '하루 종일 ${skipped.allDay}개',
    if (o.dupes > 0) '이미 있는 일정 ${o.dupes}개',
    if (skipped.long > 0) '12시간 넘는 일정 ${skipped.long}개',
    if (o.capped > 0) '너무 많아 ${o.capped}개',
  ];
  final head = '$what 일정 ${o.count}개를 가져왔어요${o.replanned ? '. 남은 일정을 바로 다시 짰어요' : ''}';
  return notes.isEmpty ? head : '$head · ${notes.join('·')}는 뺐어요';
}

String _stripIcs(String name) => name.replaceFirst(RegExp(r'\.ics$', caseSensitive: false), '');

String _sourceIdFor(String name) {
  var n = _stripIcs(name).trim().toLowerCase();
  if (n.length > 60) n = n.substring(0, 60);
  return 'ics:${n.isEmpty ? 'file' : n}';
}

sealed class _IcsCheck {
  const _IcsCheck();
}

class _IcsError extends _IcsCheck {
  const _IcsError(this.text);
  final String text;
}

class _IcsEmptyReplace extends _IcsCheck {
  const _IcsEmptyReplace({required this.id, required this.name, required this.previous, required this.text});
  final String id;
  final String name;
  final int previous;
  final String text;
}

class _IcsReady extends _IcsCheck {
  const _IcsReady(this.run);
  final String Function() run;
}

/// .ics 글을 검사한다. 0개로 기존 일정을 지우게 되면 먼저 묻는다.
_IcsCheck _checkIcs(Store store, String text, String fileName, int size) {
  if (size > _maxIcsBytes) return const _IcsError('파일이 너무 커요(5MB 초과). 캘린더 하나만 골라 내보내 주세요');
  if (!RegExp('BEGIN:VCALENDAR', caseSensitive: false).hasMatch(text)) {
    return const _IcsError('캘린더 파일(.ics)이 아니에요. 캘린더 앱의 내보내기로 받은 파일을 골라 주세요');
  }
  final win = store.importWindow();
  final IcsResult parsed;
  try {
    parsed = parseIcs(text, win.from, win.to);
  } catch (_) {
    return const _IcsError('파일을 읽다가 문제가 생겼어요. 다시 내보낸 파일로 해 주세요');
  }
  final cal = parsed.calName;
  final stripped = _stripIcs(fileName);
  final name = (cal != null && cal.isNotEmpty) ? cal : (stripped.isNotEmpty ? stripped : '가져온 캘린더');
  final id = _sourceIdFor((cal != null && cal.isNotEmpty) ? cal : fileName);
  final previous = store.state.calendars.where((c) => c.id == id).firstOrNull?.count ?? 0;
  if (parsed.events.isEmpty) {
    final why = parsed.skipped.allDay > 0 ? ' (하루 종일 일정 ${parsed.skipped.allDay}개는 시각이 없어 빼요)' : '';
    if (previous > 0) return _IcsEmptyReplace(id: id, name: name, previous: previous, text: '이 파일에는 앞으로 2주 안에 시각이 있는 일정이 없어요$why.');
    return _IcsError('앞으로 2주 안에 시각이 있는 일정이 없어요$why');
  }
  return _IcsReady(() {
    final o = store.importCalendar(parsed.events, id: id, kind: CalendarKind.ics, name: name);
    return _summary(o, parsed.skipped, "'$name'");
  });
}

class _Confirm {
  const _Confirm(this.text, this.run);
  final String text;
  final VoidCallback run;
}

class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet();

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  bool _busy = false;
  ({String text, bool bad})? _msg;
  _Confirm? _confirm;

  Future<void> _pick() async {
    setState(() {
      _msg = null;
      _busy = true;
    });
    ({String name, String text})? f;
    try {
      f = await pickTextFile(const ['ics']);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = (text: '파일을 열지 못했어요', bad: true);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (f == null) return; // 고르지 않고 닫음
    final store = context.store;
    final check = _checkIcs(store, f.text, f.name, utf8.encode(f.text).length);
    switch (check) {
      case _IcsError(:final text):
        setState(() => _msg = (text: text, bad: true));
      case _IcsEmptyReplace(:final id, :final name, :final previous, :final text):
        setState(() => _confirm = _Confirm("$text 전에 가져온 '$name' 일정 $previous개를 지울까요?", () {
              store.removeCalendar(id);
              context.toast("'$name' 일정을 지웠어요", undo: UndoKind.plan);
              Navigator.of(context).pop();
            }));
      case _IcsReady(:final run):
        final text = run();
        haptic(12);
        context.toast(text, undo: UndoKind.plan);
        Navigator.of(context).pop();
    }
  }

  void _disconnect(CalendarSource c) {
    setState(() => _confirm = _Confirm("'${c.name}'에서 가져온 일정 ${c.count}개를 지우고 연결을 끊을까요?", () {
          context.store.removeCalendar(c.id);
          context.toast('연결을 끊고 남은 일정을 다시 짰어요', undo: UndoKind.plan);
          setState(() => _confirm = null);
        }));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final t = context.ui.now;
    final c = context.ds;
    final confirm = _confirm;
    final msg = _msg;
    return DsStack(children: [
      const LabelText('회의·수업·약속이 자동으로 들어오고, 기상 알람과 할 일 배치가 바로 바뀌어요. 앞으로 2주 일정만 가져와요.'),
      if (s.calendars.isNotEmpty)
        Semantics(
          container: true,
          label: '연결된 캘린더',
          child: DsCard(list: true, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), children: [
            for (var i = 0; i < s.calendars.length; i++) _source(context, s.calendars[i], t, last: i == s.calendars.length - 1),
          ]),
        ),
      if (confirm != null)
        Semantics(
          container: true,
          label: '확인',
          child: DsCard(tint: true, children: [
            Text(confirm.text, style: DsText.body.copyWith(color: c.ink)),
            Row(children: [
              Expanded(child: DsButton('지우기', kind: BtnKind.danger, onTint: true, block: true, onPressed: confirm.run)),
              const SizedBox(width: 8),
              Expanded(child: DsButton('그대로 두기', onTint: true, block: true, onPressed: () => setState(() => _confirm = null))),
            ]),
          ]),
        ),
      Semantics(
        container: true,
        label: '기기 캘린더',
        child: DsCard(children: [
          Row(children: [
            DsIcon(DsIcons.calendar, size: 18, color: c.muted),
            const SizedBox(width: 8),
            const Expanded(child: DsTitle('구글·애플 캘린더 바로 연결')),
          ]),
          const LabelText('기기 캘린더 연결은 다음 업데이트에서 붙어요. 지금은 아래 .ics 파일로 가져오세요.'),
        ]),
      ),
      Semantics(
        container: true,
        label: '.ics 파일',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DsButton(_busy ? '파일을 여는 중…' : '.ics 파일 고르기', block: true, onPressed: _busy ? null : _pick),
          const SizedBox(height: 8),
          const LabelText('구글 캘린더: 설정 → 가져오기/내보내기 → 내보내기(압축을 풀면 .ics). 애플 캘린더(맥): 파일 → 내보내기. 같은 캘린더를 다시 고르면 통째로 바꿔요.'),
        ]),
      ),
      if (msg != null) Semantics(liveRegion: true, child: LabelText(msg.text, color: msg.bad ? c.miss : null)),
    ]);
  }

  Widget _source(BuildContext context, CalendarSource cal, DateTime t, {required bool last}) {
    final c = context.ds;
    final stale = t.difference(cal.lastSync) > _stale;
    final google = cal.kind == CalendarKind.google;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.base.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            LabelText('${google ? '구글 연결' : '.ics 파일'} · ${cal.count}개 · ${_ago(cal.lastSync, t)} 가져옴'),
            if (cal.error != null) LabelText(cal.error!, color: c.miss),
            // 웹에서 가져온 백업의 구글 연결: 앱 1단계에서는 다시 가져올 수 없다.
            if (cal.error == null && google) const LabelText('앱에서는 아직 구글 연결을 다시 가져오지 못해요. 마지막으로 가져온 일정으로 짜요'),
            if (cal.error == null && stale && !google) const LabelText('파일은 자동으로 바뀌지 않아요. 일정이 바뀌면 새로 내보내 고르세요'),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (!google) DsButton('새 파일', small: true, onPressed: _busy ? null : _pick),
          const SizedBox(height: 6),
          DsButton('연결 끊기', kind: BtnKind.ghost, small: true, onPressed: () => _disconnect(cal)),
        ]),
      ]),
    );
  }
}
