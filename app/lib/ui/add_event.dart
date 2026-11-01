// 캘린더 일정 추가 예시안 세 가지. 웹 버전 src/ui/AddEvent.tsx와 같은 화면.
// A 한 줄 입력 · B 타임라인에서 빈 시간 고르기 · C 버튼만으로 고르기.
// 셋 다 '넣으면 일정이 어떻게 바뀌는지'를 바로 보여 준다.

import 'package:flutter/material.dart';

import '../app/derive.dart';
import '../app/nlp.dart';
import '../app/store.dart';
import '../core/model/models.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

enum _Mode { a, b, c }

class _Draft {
  const _Draft(this.title, this.start, this.end);
  final String title;
  final DateTime start;
  final DateTime end;

  _Draft withTitle(String t) => _Draft(t, start, end);
}

const _modeKey = 'dayset:addMode';
const _titles = ['회의', '수업', '약속', '병원', '운동', '출장'];

/// 캘린더 일정 추가 창. [day]는 처음 고를 날(일정 탭의 오늘·내일).
Future<void> showAddEventSheet(BuildContext context, {required DateTime day}) =>
    showDsSheet(context, title: '캘린더 일정 추가', builder: (_) => _AddEvent(day: day));

class _AddEvent extends StatefulWidget {
  const _AddEvent({required this.day});
  final DateTime day;

  @override
  State<_AddEvent> createState() => _AddEventState();
}

class _AddEventState extends State<_AddEvent> {
  _Mode? _mode;
  _Draft? _draft;
  int? _travel;

  _Mode _readMode(BuildContext context) {
    final v = context.store.storage.kv.read(_modeKey);
    return _Mode.values.where((m) => m.name == v).firstOrNull ?? _Mode.a;
  }

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
      _draft = null;
    });
    context.store.storage.kv.write(_modeKey, m.name);
  }

  void _setDraft(_Draft? d) => setState(() => _draft = d);

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final now = context.ui.now;
    final c = context.ds;
    final mode = _mode ??= _readMode(context);
    final travel = _travel ??= s.settings.travelMinutes;
    final askTravel = !s.asked.travel;
    final d = _draft;
    final valid = d != null && d.title.trim().isNotEmpty && d.end.isAfter(d.start);
    final impact = valid ? eventImpact(s, FixedEvent(id: '__draft', title: d.title, start: d.start, end: d.end), now) : const <PlanDiff>[];

    void save() {
      if (!valid) return;
      haptic(10);
      final title = d.title.trim();
      final r = context.store.saveEvent(FixedEvent(id: Store.newId('ev'), title: title, start: d.start, end: d.end), travelMinutes: askTravel ? travel : null);
      context.toast('$title 일정을 넣었어요${r.replanned ? '. 남은 일정을 바로 다시 짰어요' : ''}', undo: UndoKind.plan);
      Navigator.of(context).pop();
    }

    return DsStack(children: [
      Segmented<_Mode>(
        label: '입력 방식',
        value: mode,
        onChanged: _setMode,
        options: const [SegOption(_Mode.a, 'A 한 줄'), SegOption(_Mode.b, 'B 타임라인'), SegOption(_Mode.c, 'C 버튼')],
      ),
      switch (mode) {
        _Mode.a => _ModeLine(now: now, onDraft: _setDraft),
        _Mode.b => _ModeTimeline(now: now, initialDay: widget.day, draft: d, onDraft: _setDraft),
        _Mode.c => _ModeButtons(now: now, initialDay: widget.day, onDraft: _setDraft),
      },
      if (d != null)
        Semantics(
          container: true,
          label: '미리보기',
          child: Container(
            padding: DsGap.cardPad,
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(d.title.isEmpty ? '제목 없음' : d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.h2.copyWith(color: c.ink))),
                const SizedBox(width: 8),
                Text('${koreanDate(d.start)} ${formatHm(d.start)}–${formatHm(d.end)}', style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num)),
              ]),
              const SizedBox(height: 6),
              const LabelText('넣으면 이렇게 바뀌어요'),
              const SizedBox(height: 6),
              if (impact.isEmpty)
                Text('다른 일정은 그대로예요', style: DsText.body.copyWith(color: c.ink))
              else
                for (final x in impact) ImpactLine(x),
            ]),
          ),
        ),
      if (askTravel && d != null)
        DsField(
          label: '이런 일정까지 보통 이동은 몇 분 걸려요? (한 번만 물어요)',
          child: ChipWrap(children: [
            for (final m in const [0, 20, 40, 60]) DsChip(label: m == 0 ? '이동 없음' : '$m분', selected: travel == m, onTap: () => setState(() => _travel = m)),
          ]),
        ),
      DsButton.primary('추가하기', block: true, onPressed: valid ? save : null),
    ]);
  }
}

/// 일정이 어떻게 바뀌는지 한 줄(앞 점 색: 기상·취침 = 수면, 빠짐·넘김 = 놓침, 그 밖 = 앰버).
class ImpactLine extends StatelessWidget {
  const ImpactLine(this.diff, {super.key});
  final PlanDiff diff;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final dot = switch (diff.kind) {
      PlanDiffKind.dropped || PlanDiffKind.deferred => c.miss,
      PlanDiffKind.wake || PlanDiffKind.bed => c.sleep,
      _ => c.accent,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(diff.text, style: DsText.body.copyWith(height: 20 / 14, color: c.ink))),
      ]),
    );
  }
}

/// 고른 것을 보여 주는(알아들은) 칩.
class _ParsedChip extends StatelessWidget {
  const _ParsedChip(this.label, {this.strong = false});
  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: c.pillBg, border: Border.all(color: c.accent, width: 1.5), borderRadius: BorderRadius.circular(18)),
      child: Center(widthFactor: 1, child: Text(label, style: TextStyle(fontSize: 14, fontWeight: strong ? FontWeight.w700 : FontWeight.w400, color: c.ink))),
    );
  }
}

/// A: "내일 오전 9시 팀 회의 1시간"처럼 한 줄로 쓰면 바로 알아듣는다.
class _ModeLine extends StatefulWidget {
  const _ModeLine({required this.now, required this.onDraft});
  final DateTime now;
  final ValueChanged<_Draft?> onDraft;

  @override
  State<_ModeLine> createState() => _ModeLineState();
}

class _ModeLineState extends State<_ModeLine> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _update(String t) {
    if (_text.text != t) {
      _text.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }
    setState(() {});
    final p = t.trim().isEmpty ? null : parseEventText(t, widget.now);
    widget.onDraft(p == null ? null : _Draft(p.title, p.start, p.end));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = _text.text;
    final parsed = t.trim().isEmpty ? null : parseEventText(t, widget.now);
    final base = dsInput(context, hint: '예: 내일 오전 9시 팀 회의');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _text,
        autofocus: true,
        onChanged: _update,
        style: TextStyle(fontSize: 17, color: c.ink),
        decoration: base.copyWith(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          border: (base.border as OutlineInputBorder).copyWith(borderRadius: BorderRadius.circular(14)),
          enabledBorder: (base.enabledBorder as OutlineInputBorder).copyWith(borderRadius: BorderRadius.circular(14)),
          focusedBorder: (base.focusedBorder as OutlineInputBorder).copyWith(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      const SizedBox(height: 10),
      if (t.trim().isEmpty)
        ChipWrap(children: [for (final e in eventExamples) DsChip(label: e, selected: false, onTap: () => _update(e))])
      else if (parsed != null)
        Semantics(
          label: '알아들은 내용',
          child: ChipWrap(children: [
            _ParsedChip(parsed.found.date ?? '오늘'),
            if (parsed.found.time != null) _ParsedChip(parsed.found.time!),
            _ParsedChip(parsed.found.length ?? '1시간(기본)'),
            _ParsedChip(parsed.title, strong: true),
          ]),
        )
      else
        LabelText('시각을 함께 써 주세요. 예: "3시", "오전 10:30"', color: c.miss),
    ]);
  }
}

const _slot = 30;
const _from = 6 * 60;
const _to = 24 * 60;

/// B: 그 날 자동 일정 위에서 빈 시간을 눌러 고른다. 한 번 누르면 1시간, 아래를 한 번 더 누르면 거기까지.
class _ModeTimeline extends StatefulWidget {
  const _ModeTimeline({required this.now, required this.initialDay, required this.draft, required this.onDraft});
  final DateTime now;
  final DateTime initialDay;
  final _Draft? draft;
  final ValueChanged<_Draft?> onDraft;

  @override
  State<_ModeTimeline> createState() => _ModeTimelineState();
}

class _ModeTimelineState extends State<_ModeTimeline> {
  late DateTime _day = dayStart(widget.initialDay);
  String _title = '';

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final c = context.ds;
    final plan = planFor(s, dateKey(_day), widget.now).plan;
    final draft = widget.draft;
    final sel = draft != null && dateKey(draft.start) == dateKey(_day) ? (s: diffMin(draft.start, _day), e: diffMin(draft.end, _day)) : null;

    void tap(int m) {
      haptic(5);
      var st = m;
      var en = m + 60;
      if (sel != null && m >= sel.s && m < sel.s + _slot) {
        widget.onDraft(null); // 같은 칸을 다시 누르면 지우기
        return;
      }
      if (sel != null && m > sel.s) {
        st = sel.s;
        en = m + _slot;
      }
      widget.onDraft(_Draft(_title, addMin(_day, st), addMin(_day, en > _to ? _to : en)));
    }

    final slots = [for (var m = _from; m < _to; m += _slot) m];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChipWrap(children: [
        for (var i = 0; i < 3; i++)
          DsChip(
            label: const ['오늘', '내일', '모레'][i],
            selected: dateKey(addDays(dayStart(widget.now), i)) == dateKey(_day),
            onTap: () {
              setState(() => _day = addDays(dayStart(widget.now), i));
              widget.onDraft(null);
            },
          ),
      ]),
      const SizedBox(height: 10),
      const LabelText('빈 칸을 누르면 1시간, 아래 칸을 한 번 더 누르면 거기까지 늘어나요'),
      const SizedBox(height: 10),
      Semantics(
        label: '${koreanDate(_day)} 시간표',
        child: Container(
          height: 300,
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            itemCount: slots.length,
            itemExtent: 30,
            itemBuilder: (context, i) {
              final m = slots[i];
              final st = addMin(_day, m);
              final blk = plan.blocks.where((b) => b.activity != Activity.sleep && b.overlaps(st, addMin(st, _slot))).firstOrNull;
              final on = sel != null && m >= sel.s && m < sel.e;
              final first = sel != null && m == sel.s;
              final hour = m % 60 == 0;
              Widget slot;
              if (on) {
                slot = Container(
                  color: c.accent,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 10),
                  child: first
                      ? Text('${draft!.title.isEmpty ? '새 일정' : draft.title} · ${formatDuration(sel.e - sel.s)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentInk))
                      : null,
                );
              } else if (blk != null) {
                slot = Container(
                  decoration: BoxDecoration(color: c.surface2, border: Border(left: BorderSide(color: c.block(blk), width: 3))),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(!blk.start.isBefore(st) || m == _from ? blk.title : '',
                      maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 12, color: c.muted)),
                );
              } else {
                slot = const SizedBox.expand();
              }
              return Semantics(
                button: true,
                label: '${formatHm(st)}${on ? ' 고름' : blk != null ? ' ${blk.title}' : ' 비어 있음'}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tap(m),
                  child: Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: hour ? c.line : Colors.transparent))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        width: 52,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10, top: 2),
                          child: Text(hour ? formatHm(st) : '', style: TextStyle(fontSize: 11, color: c.faint, fontFeatures: DsText.num)),
                        ),
                      ),
                      Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: slot)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      _TitlePicker(
        value: _title,
        onChanged: (t) {
          setState(() => _title = t);
          if (draft != null) widget.onDraft(draft.withTitle(t));
        },
      ),
    ]);
  }
}

/// C: 키보드 없이 버튼만으로.
class _ModeButtons extends StatefulWidget {
  const _ModeButtons({required this.now, required this.initialDay, required this.onDraft});
  final DateTime now;
  final DateTime initialDay;
  final ValueChanged<_Draft?> onDraft;

  @override
  State<_ModeButtons> createState() => _ModeButtonsState();
}

class _ModeButtonsState extends State<_ModeButtons> {
  late DateTime _d = dayStart(widget.initialDay);
  int? _start;
  int _len = 60;
  String _title = '';

  void _emit() => widget.onDraft(_start == null ? null : _Draft(_title, addMin(_d, _start!), addMin(_d, _start! + _len)));

  @override
  Widget build(BuildContext context) {
    final today = dayStart(widget.now);
    // 토요일까지 남은 날(오늘이 토요일이면 다음 주 토요일)
    final toSat = (DateTime.saturday - today.weekday + 7) % 7;
    final days = [
      ('오늘', today),
      ('내일', addDays(today, 1)),
      ('모레', addDays(today, 2)),
      ('토요일', addDays(today, toSat == 0 ? 7 : toSat)),
    ];
    const times = [8 * 60, 9 * 60, 10 * 60, 11 * 60, 13 * 60, 14 * 60, 15 * 60, 16 * 60, 18 * 60, 19 * 60];
    final custom = _start != null && !times.contains(_start);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Group(label: '언제', children: [
        for (final (label, d) in days)
          DsChip(
            label: label,
            selected: dateKey(d) == dateKey(_d),
            onTap: () {
              setState(() => _d = d);
              _emit();
            },
          ),
      ]),
      const SizedBox(height: 12),
      _Group(label: '몇 시', children: [
        for (final t in times)
          DsChip(
            label: formatClock(t),
            selected: _start == t,
            onTap: () {
              setState(() => _start = t);
              _emit();
            },
          ),
        DsChip(
          label: custom ? formatClock(_start!) : '직접 고르기',
          selected: custom,
          onTap: () async {
            final init = _start ?? 9 * 60;
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: init ~/ 60, minute: init % 60),
              initialEntryMode: TimePickerEntryMode.inputOnly,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
            );
            if (picked == null || !mounted) return;
            setState(() => _start = picked.hour * 60 + picked.minute);
            _emit();
          },
        ),
      ]),
      const SizedBox(height: 12),
      _Group(label: '얼마나', children: [
        for (final l in const [30, 60, 90, 120, 180])
          DsChip(
            label: formatDuration(l),
            selected: _len == l,
            onTap: () {
              setState(() => _len = l);
              _emit();
            },
          ),
      ]),
      const SizedBox(height: 12),
      _TitlePicker(
        value: _title,
        onChanged: (t) {
          setState(() => _title = t);
          _emit();
        },
      ),
    ]);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DsField(label: label, child: Semantics(label: label, child: ChipWrap(children: children)));
}

class _TitlePicker extends StatefulWidget {
  const _TitlePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TitlePicker> createState() => _TitlePickerState();
}

class _TitlePickerState extends State<_TitlePicker> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_TitlePicker old) {
    super.didUpdateWidget(old);
    if (widget.value != _text.text) {
      _text.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DsField(
        label: '무슨 일정',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ChipWrap(children: [for (final t in _titles) DsChip(label: t, selected: widget.value == t, onTap: () => widget.onChanged(t))]),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            onChanged: widget.onChanged,
            style: DsText.base.copyWith(color: context.ds.ink),
            decoration: dsInput(context, hint: '직접 쓰기 · 예: 팀 회의'),
          ),
        ]),
      );
}
