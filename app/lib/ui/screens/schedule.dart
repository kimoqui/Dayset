// 일정 탭: 오늘·내일 자동 일정, 근거, 다시 짜기, 캘린더 일정. 웹 버전 src/ui/screens/Schedule.tsx와 같은 화면.

import 'package:flutter/material.dart';

import '../../app/derive.dart';
import '../../app/state.dart';
import '../../app/store.dart';
import '../../core/engine/achievement.dart';
import '../../core/engine/schedule_builder.dart';
import '../../core/model/models.dart';
import '../add_event.dart';
import '../calendar_connect.dart';
import '../kit.dart';
import '../scope.dart';
import '../theme.dart';

enum _Day { today, tomorrow }

class _Row {
  const _Row({required this.key, required this.time, this.end, required this.title, required this.tag, required this.color, this.reason, this.outcome, this.adjusted = false});
  final String key;
  final DateTime time;
  final DateTime? end;
  final String title;
  final String tag;
  final Color color;
  final String? reason;
  final Outcome? outcome;
  final bool adjusted;
}

const _outcomeTag = {Outcome.achieved: '달성', Outcome.missed: '놓침', Outcome.estimated: '기록 없음'};

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  _Day _day = _Day.today;
  String? _openReason;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final now = context.ui.now;
    final c = context.ds;
    final store = context.store;
    final todayKey = dateKey(now);
    final tomorrowKey = dateKey(addDays(now, 1));
    final today = _day == _Day.today;
    final key = today ? todayKey : tomorrowKey;
    final view = planFor(s, key, now);
    final plan = view.plan;
    final tomorrowPlan = planFor(s, tomorrowKey, now).plan;
    final outcomeById = today ? {for (final o in evaluate(s, todayKey, now).outcomes) o.block.id: o.outcome} : const <String, Outcome>{};

    final rows = <_Row>[];
    if (!today) {
      rows.add(_Row(key: 'wake', time: plan.wake, title: '기상 알람', tag: '알람', color: c.alarm, reason: plan.alarms.first.reason));
    }
    for (final b in plan.blocks) {
      if (b.activity == Activity.sleep) continue;
      if (today && b.end.isBefore(dayStart(now))) continue;
      final ended = !b.end.isAfter(now);
      rows.add(_Row(
        key: b.id,
        time: b.start,
        end: b.end,
        title: b.kind == BlockKind.task ? '${b.title} · ${formatDuration(b.minutes)}' : b.title,
        tag: kindLabel(b),
        color: c.block(b),
        outcome: today && ended ? outcomeById[b.id] : null,
        adjusted: b.adjusted,
      ));
    }
    rows.add(today
        ? _Row(key: 'bed', time: tomorrowPlan.bedTonight, title: '취침 알림', tag: '알람', color: c.alarm, reason: tomorrowPlan.alarms[1].reason)
        : _Row(key: 'bed', time: plan.dayEnd, title: '취침 예정', tag: '알람', color: c.alarm, reason: '모레 기상 기준 예정 시각'));
    final sorted = stableSorted(rows, (a, b) => a.time.compareTo(b.time));

    final deferred = [
      for (final d in plan.deferred)
        '${s.tasks.where((x) => x.id == d.taskId).firstOrNull?.title ?? '할 일'} ${formatDuration(d.minutes)}: ${d.reason == DeferReason.budget ? '빈 시간의 75%를 채워 다음 날로 넘겼어요' : '마감 전에 넣을 빈 시간이 없어요'}',
    ];
    final upcoming = stableSorted(s.events.where((e) => !e.end.isBefore(dayStart(now))), (a, b) => a.start.compareTo(b.start));

    final obs = s.observation;
    final noPlan = obs != null && (obs.phase == ObservationPhase.recording || (today && todayKey.compareTo(obs.day1) <= 0));

    return ScreenList(children: [
      // 위 막대: 제목 + 시연 칩, 캘린더 일정 추가
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Semantics(header: true, child: Text('일정', style: DsText.title.copyWith(color: c.ink))),
          const SizedBox(width: 8),
          _HintChip(label: '시연', icon: DsIcons.refresh, onTap: () => context.ui.actions.open(AppPage.demo)),
          const Spacer(),
          DsButton('캘린더 일정', small: true, icon: DsIcons.plus, onPressed: () => showAddEventSheet(context, day: today ? now : addDays(now, 1))),
        ]),
      ),
      Segmented<_Day>(
        label: '날짜',
        value: _day,
        onChanged: (d) => setState(() {
          _day = d;
          _openReason = null;
        }),
        options: const [SegOption(_Day.today, '오늘'), SegOption(_Day.tomorrow, '내일')],
      ),
      if (noPlan)
        DsCard(children: [
          DsTitle(obs.phase == ObservationPhase.recording ? '아직 일정이 없어요' : '오늘은 기록한 날이에요'),
          Text(
            obs.phase == ObservationPhase.recording
                ? '첫날은 하루를 그대로 기록해요. 기록한 하루를 보고 바꾸고 싶은 시각만 고치면, 다음 날부터 일정과 알람이 자동으로 짜여요.'
                : "내일 일정은 '내일'에서 볼 수 있어요.",
            style: DsText.body.copyWith(color: c.muted),
          ),
        ])
      else ...[
        LabelText(today
            ? "자동으로 짠 일정이에요. 코칭으로 바뀐 일정은 '조정됨'으로 표시해요."
            : '${view.stored ? '확정한' : '지금 기준으로 짠'} 내일 일정이에요. 기상 ${formatHm(plan.wake)} · 할 일 ${formatDuration(plan.taskMinutes)}'),
        if (view.outdated)
          DsCard(tint: true, children: [
            Row(children: [
              Expanded(child: Text('할 일·일정이 바뀌었어요. ${today ? '남은 시간을' : '내일 일정을'} 다시 짤까요?', style: DsText.body.copyWith(color: c.ink))),
              const SizedBox(width: 10),
              DsButton.primary('다시 짜기', small: true, onPressed: () => store.regenerate(key)),
            ]),
          ]),
        for (final n in [...plan.notes, ...deferred]) LabelText(n, color: c.miss),
        Semantics(
          container: true,
          label: '${today ? '오늘' : '내일'} 일정',
          child: DsCard(list: true, children: [
            for (var i = 0; i < sorted.length; i++) _rowView(context, sorted[i], now, today, last: i == sorted.length - 1),
          ]),
        ),
        if (today && view.stored && !view.outdated)
          Align(
            alignment: Alignment.centerLeft,
            child: DsButton('남은 일정 다시 짜기', kind: BtnKind.ghost, small: true, icon: DsIcons.refresh, onPressed: () {
              store.regenerate(key);
              context.toast('남은 일정을 다시 짰어요');
            }),
          ),
      ],

      // 캘린더 일정
      Semantics(
        container: true,
        label: '캘린더 일정',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(children: [
              const Expanded(child: DsTitle('캘린더 일정')),
              DsButton(s.calendars.isNotEmpty ? '연결된 캘린더 ${s.calendars.length}' : '캘린더 가져오기', small: true, onPressed: () => showCalendarSheet(context)),
            ]),
          ),
          const SizedBox(height: 6),
          const LabelText('기상 알람과 할 일 배치에 바로 반영해요'),
          for (final cal in s.calendars.where((x) => x.error != null)) ...[
            const SizedBox(height: 6),
            _WarnBanner(text: '${cal.name}: ${cal.error}', onTap: () => showCalendarSheet(context)),
          ],
          const SizedBox(height: 6),
          DsCard(list: true, children: [
            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('아직 없어요. 회의·수업·약속을 넣어 주세요.', textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
              ),
            for (var i = 0; i < upcoming.length; i++) _eventRow(context, s, upcoming[i], last: i == upcoming.length - 1 && !upcoming.any((e) => e.source != null)),
            if (upcoming.any((e) => e.source != null))
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LabelText('가져온 일정은 원래 캘린더에서 고치면 다음 동기화 때 바뀌어요')),
          ]),
        ]),
      ),
    ]);
  }

  Widget _rowView(BuildContext context, _Row r, DateTime now, bool today, {required bool last}) {
    final c = context.ds;
    final isNow = today && r.end != null && !now.isBefore(r.time) && now.isBefore(r.end!);
    final tag = isNow ? '지금' : (r.outcome != null ? (_outcomeTag[r.outcome] ?? r.tag) : r.tag);
    final Color? tagColor = isNow || r.adjusted || r.outcome == Outcome.achieved
        ? c.accentStrong
        : r.outcome == Outcome.missed
            ? c.miss
            : null;
    final open = _openReason == r.key && r.reason != null;
    final title = r.reason != null
        ? Text.rich(
            TextSpan(children: [
              TextSpan(text: r.title),
              TextSpan(text: ' · 근거', style: DsText.small.copyWith(color: c.muted)),
            ]),
            style: DsText.base.copyWith(color: c.ink),
          )
        : Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.base.copyWith(color: c.ink));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        expanded: r.reason != null ? open : null,
        child: _Line(
          time: formatHm(r.time),
          timeColor: isNow ? c.accent : null,
          color: r.color,
          tag: tag,
          tagColor: tagColor,
          now: isNow,
          last: last && !open,
          onTap: r.reason == null ? null : () => setState(() => _openReason = open ? null : r.key),
          child: title,
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 0, 10),
          child: LabelText(r.reason!),
        ),
    ]);
  }

  Widget _eventRow(BuildContext context, AppState s, FixedEvent e, {required bool last}) {
    final c = context.ds;
    final store = context.store;
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: DsText.base.copyWith(color: c.ink)),
      Text('${koreanDate(e.start)} ${formatHm(e.start)}–${formatHm(e.end)}', style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num)),
    ]);
    final border = last ? null : Border(bottom: BorderSide(color: c.line));
    if (e.source != null) {
      final google = s.calendars.where((x) => x.id == e.source).firstOrNull?.kind == CalendarKind.google;
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: border),
        child: Row(children: [
          Expanded(child: info),
          const SizedBox(width: 12),
          Text(google ? '구글' : '가져옴', style: DsText.label.copyWith(color: c.muted, fontWeight: FontWeight.w400)),
        ]),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(border: border),
      child: Row(children: [
        Expanded(
          child: Pressable(
            scale: 0.98,
            semanticLabel: '${e.title} 고치기',
            onTap: () => _showEventSheet(context, e, askTravel: !s.asked.travel && e.id.isEmpty, travel: s.settings.travelMinutes),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: info),
          ),
        ),
        DsIconButton(
          DsIcons.trash,
          iconSize: 18,
          label: '${e.title} 지우기',
          onPressed: () => notifyPlan(context, store.deleteEvent(e.id), '${e.title} 일정을 지우고 남은 일정을 다시 짰어요', '${e.title} 일정을 지웠어요'),
        ),
      ]),
    );
  }
}

/// 일정 한 줄(시각 · 색 막대 · 내용 · 꼬리표). 지금 줄은 옅은 앰버로 칠한다.
class _Line extends StatelessWidget {
  const _Line({required this.time, this.timeColor, required this.color, required this.child, required this.tag, this.tagColor, this.now = false, this.last = false, this.onTap});
  final String time;
  final Color? timeColor;
  final Color color;
  final Widget child;
  final String tag;
  final Color? tagColor;
  final bool now;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: now ? const EdgeInsets.symmetric(horizontal: 8) : null,
      decoration: BoxDecoration(
        color: now ? c.pillBg : null,
        borderRadius: now ? BorderRadius.circular(12) : null,
        border: now || last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        SizedBox(
          width: 44,
          child: Text(time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: timeColor ?? c.muted, fontFeatures: DsText.num)),
        ),
        const SizedBox(width: 12),
        Container(width: 4, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child)),
        const SizedBox(width: 12),
        Text(tag, style: TextStyle(fontSize: 12, color: tagColor ?? c.muted, fontWeight: tagColor != null ? FontWeight.w700 : FontWeight.w400)),
      ]),
    );
    return onTap == null ? row : Pressable(scale: 0.98, onTap: onTap, child: row);
  }
}

/// 앰버 테두리 작은 칩(시연).
class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.icon, required this.onTap});
  final String label;
  final DsIcons icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: c.pillBg, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(15)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          DsIcon(icon, size: 14, color: c.accentStrong),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentStrong)),
        ]),
      ),
    );
  }
}

/// 캘린더 동기화 실패 띠(누르면 캘린더 창).
class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Pressable(
      scale: 0.98,
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.miss.withValues(alpha: 0.14), c.surface),
          border: Border.all(color: c.miss.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, height: 19 / 13, color: c.ink)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 직접 넣은 캘린더 일정 고치기
// ---------------------------------------------------------------------------

Future<void> _showEventSheet(BuildContext context, FixedEvent event, {required bool askTravel, required int travel}) =>
    showDsSheet(context, title: event.id.isNotEmpty ? '캘린더 일정 고치기' : '캘린더 일정 추가', builder: (_) => _EventSheet(event: event, askTravel: askTravel, travel: travel));

class _EventSheet extends StatefulWidget {
  const _EventSheet({required this.event, required this.askTravel, required this.travel});
  final FixedEvent event;
  final bool askTravel;
  final int travel;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  late final _title = TextEditingController(text: widget.event.title);
  late DateTime _date = dayStart(widget.event.start);
  late int _start = widget.event.start.hour * 60 + widget.event.start.minute;
  late int _end = widget.event.end.hour * 60 + widget.event.end.minute;
  late int _travel = widget.travel;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final st = addMin(_date, _start);
    final en = addMin(_date, _end);
    final valid = _title.text.trim().isNotEmpty && en.isAfter(st);
    return DsStack(children: [
      const LabelText('.ics 파일을 가져오면 자동으로 들어와요. 여기서는 한 건씩 직접 넣어요.'),
      DsField(
        label: '제목',
        child: TextField(
          controller: _title,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: DsText.base.copyWith(color: c.ink),
          decoration: dsInput(context, hint: '예: 팀 회의'),
        ),
      ),
      DsField(
        label: '날짜',
        child: Pressable(
          scale: 0.98,
          semanticLabel: '날짜 ${koreanDate(_date)}',
          onTap: () async {
            final now = context.ui.now;
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: addDays(now, -365), lastDate: addDays(now, 730));
            if (d != null && mounted) setState(() => _date = dayStart(d));
          },
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
            child: Text(koreanDate(_date), style: DsText.base.copyWith(color: c.ink, fontFeatures: DsText.num)),
          ),
        ),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TimeField(label: '시작', value: _start, onChanged: (m) => setState(() => _start = m))),
        const SizedBox(width: 10),
        Expanded(child: TimeField(label: '끝', value: _end, onChanged: (m) => setState(() => _end = m))),
      ]),
      if (!en.isAfter(st)) LabelText('끝 시각이 시작보다 늦어야 해요', color: c.miss),
      if (widget.askTravel) _TravelPicker(value: _travel, noneLabel: '재택·이동 없음', hint: '첫 일정이 이르면 기상 알람을 이동 시간만큼 당겨요.', onChanged: (m) => setState(() => _travel = m)),
      DsButton.primary('저장', block: true, onPressed: !valid
          ? null
          : () {
              final title = _title.text.trim();
              final r = context.store.saveEvent(
                FixedEvent(id: widget.event.id.isNotEmpty ? widget.event.id : Store.newId('ev'), title: title, start: st, end: en),
                travelMinutes: widget.askTravel ? _travel : null,
              );
              notifyPlan(context, r, '$title 일정을 넣고 남은 일정을 다시 짰어요', '$title 일정을 저장했어요');
              Navigator.of(context).pop();
            }),
    ]);
  }
}

/// 이동 시간 고르기(처음 한 번만 묻는다).
class _TravelPicker extends StatelessWidget {
  const _TravelPicker({required this.value, required this.onChanged, required this.noneLabel, this.hint});
  final int value;
  final ValueChanged<int> onChanged;
  final String noneLabel;
  final String? hint;

  @override
  Widget build(BuildContext context) => DsField(
        label: '이런 일정까지 보통 이동은 몇 분 걸려요? (한 번만 물어요)',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChipWrap(children: [
            for (final m in const [0, 20, 40, 60]) DsChip(label: m == 0 ? noneLabel : '$m분', selected: value == m, onTap: () => onChanged(m)),
          ]),
          if (hint != null) ...[const SizedBox(height: 6), LabelText(hint!)],
        ]),
      );
}
