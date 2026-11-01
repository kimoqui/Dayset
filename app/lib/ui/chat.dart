// 말로 일정 바꾸기(채팅) + 일정 조각 바꾸기 창. 웹 버전 src/ui/Chat.tsx와 같은 화면·같은 문구.
// 바로 바꾸지 않는다: 읽은 내용과 바뀌는 일정을 먼저 보여 주고, '바꾸기'를 눌러야 적용한다(15초 되돌리기).

import 'package:flutter/material.dart';

import '../app/ai_chat.dart';
import '../app/chat_command.dart';
import '../app/edits.dart';
import '../app/state.dart';
import '../app/store.dart';
import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import 'account.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

/// 바꾸기를 적용하고 알린다(바꾸기는 늘 일정을 다시 짠 것으로 알린다).
void _apply(BuildContext context, List<ScheduleEdit> edits, String text) {
  final r = context.store.applyEdits(edits);
  notifyPlan(context, PlanChange(replanned: true, deferred: r.deferred), text);
  haptic(12);
}

/// 변경 미리보기 묶음.
class _Preview extends StatelessWidget {
  const _Preview({required this.s, required this.edits});
  final AppState s;
  final List<ScheduleEdit> edits;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final t = context.ui.now;
    final pv = previewEdits(s, edits, t);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final e in edits)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: DsText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
            Expanded(child: Text(describeEdit(s, e, t), style: DsText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600))),
          ]),
        ),
      for (final p in pv) ...[
        const SizedBox(height: 6),
        Text('${p.label} 일정', style: DsText.label.copyWith(color: c.ink, fontWeight: FontWeight.w700)),
        if (p.diffs.isEmpty) const LabelText('· 겉으로 바뀌는 시각은 없어요') else for (final d in p.diffs) LabelText('· $d'),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------
// 말로 일정 바꾸기
// ---------------------------------------------------------------------------

enum _Ask { ask, done, cancel }

class _Msg {
  _Msg(this.me, this.text, {this.edits, this.state});
  final bool me;
  final String text;
  final List<ScheduleEdit>? edits;
  _Ask? state;
}

Future<void> showChatSheet(BuildContext context) => showDsSheet<void>(context, title: '말로 일정 바꾸기', builder: (_) => const _ChatBody());

class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _msgs = <_Msg>[_Msg(false, '일정을 어떻게 바꿀까요? 말하듯이 적어 주세요. 바꾸기 전에 무엇이 바뀌는지 먼저 보여 드릴게요.')];
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      });

  bool _busy = false;

  Future<void> _send(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _busy) return;
    haptic(6);
    final store = context.store;
    final ui = context.ui;
    final cloud = CloudScope.read(context);
    setState(() {
      _msgs.add(_Msg(true, q));
      _text.clear();
    });
    _toEnd();
    // 로그인했으면 AI(Claude)가 먼저 읽고, 안 되면 기기 안 규칙으로 읽는다.
    ChatReading? r;
    if (cloud?.session != null) {
      setState(() => _busy = true);
      final raw2 = await cloud!.askChat(q, aiContext(store.state, ui.now));
      r = raw2 == null ? null : readAiReply(raw2, store.state, ui.now);
      if (!mounted) return;
      setState(() => _busy = false);
    }
    final reading = r ?? interpretChat(q, store.state, ui.now);
    setState(() => _msgs.add(_Msg(false, reading.reply, edits: reading.edits.isEmpty ? null : reading.edits, state: reading.edits.isEmpty ? null : _Ask.ask)));
    _toEnd();
  }

  void _decide(_Msg m, bool ok) {
    if (m.edits == null) return;
    if (ok) _apply(context, m.edits!, '말한 대로 일정을 바꿨어요');
    setState(() {
      m.state = ok ? _Ask.done : _Ask.cancel;
      _msgs.add(_Msg(false, ok ? '바꿨어요. 일정 탭에서 확인할 수 있어요.' : '그대로 둘게요.'));
    });
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = context.app;
    return DsStack(gap: 12, children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.46),
        child: Semantics(
          liveRegion: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in _msgs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: m.me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                    FractionallySizedBox(
                      widthFactor: 0.86,
                      alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                      child: Align(
                        alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          decoration: BoxDecoration(
                            color: m.me ? c.accent : c.surface,
                            border: Border.all(color: m.me ? c.accent : c.line),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(m.me ? 16 : 6),
                              bottomRight: Radius.circular(m.me ? 6 : 16),
                            ),
                          ),
                          child: Text(m.text, style: DsText.body.copyWith(color: m.me ? c.accentInk : c.ink)),
                        ),
                      ),
                    ),
                    if (m.edits != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: c.tint, border: Border.all(color: c.tintLine), borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _Preview(s: s, edits: m.edits!),
                          const SizedBox(height: 10),
                          if (m.state == _Ask.ask)
                            Row(children: [
                              Expanded(child: DsButton.primary('바꾸기', small: true, block: true, onPressed: () => _decide(m, true))),
                              const SizedBox(width: 8),
                              DsButton('그대로 두기', small: true, onTint: true, onPressed: () => _decide(m, false)),
                            ])
                          else
                            LabelText(m.state == _Ask.done ? '적용했어요' : '적용하지 않았어요'),
                        ]),
                      ),
                    ],
                  ]),
                ),
              if (_busy)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
                    child: Text('읽는 중…', style: DsText.body.copyWith(color: c.muted)),
                  ),
                ),
            ]),
          ),
        ),
      ),
      ChipWrap(children: [
        for (final e in chatExamples.take(4)) DsChip(label: e, selected: false, onTap: () => _send(e)),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _text,
            maxLength: 200,
            textInputAction: TextInputAction.send,
            style: DsText.base.copyWith(color: c.ink),
            decoration: dsInput(context, hint: '예: 내일 운동 7시로 옮겨줘').copyWith(counterText: ''),
            onChanged: (_) => setState(() {}),
            onSubmitted: _send,
          ),
        ),
        const SizedBox(width: 8),
        Opacity(
          opacity: _text.text.trim().isEmpty || _busy ? 0.5 : 1,
          child: Pressable(
            semanticLabel: '보내기',
            onTap: _text.text.trim().isEmpty || _busy ? null : () => _send(_text.text),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14)),
              child: DsIcon(DsIcons.forward, size: 18, color: c.accentInk),
            ),
          ),
        ),
      ]),
      LabelText(CloudScope.maybeOf(context)?.session != null
          ? 'AI(Claude)가 말과 7일 일정 요약을 읽어요. 연결이 안 되면 기기 안 규칙으로 읽어요.'
          : '지금은 기기 안 규칙으로 읽어요. 로그인하면 AI(Claude)가 읽어요.'),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 일정 조각(식사·운동) 바꾸기
// ---------------------------------------------------------------------------

Future<void> showHabitEditSheet(BuildContext context, {required String day, required String title, required String dayLabel}) =>
    showDsSheet<void>(context, title: '$title 바꾸기', builder: (_) => _HabitEditBody(day: day, title: title, dayLabel: dayLabel));

class _HabitEditBody extends StatefulWidget {
  const _HabitEditBody({required this.day, required this.title, required this.dayLabel});
  final String day;
  final String title;
  final String dayLabel;

  @override
  State<_HabitEditBody> createState() => _HabitEditBodyState();
}

class _HabitEditBodyState extends State<_HabitEditBody> {
  late final HabitSlot? _cur = habitOn(context.store.state, widget.day, widget.title);
  late int _start = _cur?.start.minutes ?? 12 * 60;
  late int _minutes = _cur?.minutes ?? 30;
  EditScope _scope = EditScope.day;

  void _go(List<ScheduleEdit> edits, String text) {
    _apply(context, edits, text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final title = widget.title;
    final label = widget.dayLabel;
    final cur = _cur;
    final edited = s.overrides[widget.day]?.habits[title] != null;
    final edit = HabitChange(day: widget.day, title: title, patch: HabitEdit(start: _start, minutes: _minutes), scope: _scope);
    final changed = cur == null || cur.start.minutes != _start || cur.minutes != _minutes;
    return DsStack(gap: 12, children: [
      LabelText('지금 $label ${cur != null ? '${formatClock(cur.start.minutes)} · ${formatDuration(cur.minutes)}' : '일정에 없음'}${edited ? ' · 이날만 바꾼 값' : ''}'),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TimeField(label: '시작', value: _start, onChanged: (m) => setState(() => _start = m))),
        const SizedBox(width: 10),
        Expanded(child: NumberField(label: '길이', value: _minutes, min: 5, max: 240, onChanged: (m) => setState(() => _minutes = m))),
      ]),
      Segmented<EditScope>(
        label: '적용 범위',
        value: _scope,
        onChanged: (v) => setState(() => _scope = v),
        options: [SegOption(EditScope.day, '$label만'), const SegOption(EditScope.every, '매일 이렇게')],
      ),
      if (changed) _Preview(s: s, edits: [edit]),
      DsButton.primary('바꾸기', block: true, onPressed: changed ? () => _go([edit], '$title${objectParticle(title)} 바꾸고 일정을 다시 짰어요') : null),
      Wrap(spacing: 8, runSpacing: 8, children: [
        DsButton('$label${topicParticle(label)} 빼기', small: true, kind: BtnKind.danger, onPressed: () {
          _go([HabitChange(day: widget.day, title: title, patch: const HabitEdit(skip: true), scope: EditScope.day)], '$label $title${topicParticle(title)} 뺐어요');
        }),
        if (edited) DsButton('원래대로', small: true, onPressed: () => _go([ResetDay(day: widget.day)], '$label 바꾼 것을 되돌렸어요')),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 기상 알람 바꾸기
// ---------------------------------------------------------------------------

Future<void> showWakeEditSheet(BuildContext context, {required String day, required int current, required String dayLabel}) =>
    showDsSheet<void>(context, title: '기상 알람 바꾸기', builder: (_) => _WakeEditBody(day: day, current: current, dayLabel: dayLabel));

class _WakeEditBody extends StatefulWidget {
  const _WakeEditBody({required this.day, required this.current, required this.dayLabel});
  final String day;
  final int current;
  final String dayLabel;

  @override
  State<_WakeEditBody> createState() => _WakeEditBodyState();
}

class _WakeEditBodyState extends State<_WakeEditBody> {
  late int _wake = widget.current;
  EditScope _scope = EditScope.day;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final label = widget.dayLabel;
    final edit = WakeChange(day: widget.day, minutes: _wake, scope: _scope);
    final changed = _wake != widget.current;
    return DsStack(gap: 12, children: [
      LabelText('지금 $label ${formatClock(widget.current)}. 첫 일정이 이르면 준비·이동 시간만큼 더 일찍 울려요.'),
      TimeField(label: '기상 목표', value: _wake, onChanged: (m) => setState(() => _wake = m)),
      Segmented<EditScope>(
        label: '적용 범위',
        value: _scope,
        onChanged: (v) => setState(() => _scope = v),
        options: [SegOption(EditScope.day, '$label만'), const SegOption(EditScope.every, '매일 이렇게')],
      ),
      if (changed) _Preview(s: s, edits: [edit]),
      DsButton.primary('바꾸기', block: true, onPressed: !changed
          ? null
          : () {
              _apply(context, [edit], '기상 알람을 ${formatClock(_wake)}으로 바꿨어요');
              Navigator.of(context).pop();
            }),
      if (_scope == EditScope.every && s.correction != null) const LabelText('매일로 바꾸면 단계적 교정은 멈추고 이 시각으로 맞춰요.'),
    ]);
  }
}
