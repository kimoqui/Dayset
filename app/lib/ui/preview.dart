// 프리뷰(베타)용 화면 조각: 처음 목표 정하기, 동의, 알림 켜기, 설문, 불편 신고, 베타 지표.
// 웹 버전 src/ui/Preview.tsx와 같은 문구·흐름이다.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/goal_text.dart';
import '../app/metrics.dart';
import '../app/state.dart';
import '../core/model/models.dart';
import '../platform/notify.dart';
import '../platform/share.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 단계 화면 공통 부품(처음 설정·동의·알림·내 하루 보기에서 쓴다)
// ---------------------------------------------------------------------------

/// 위는 스크롤되는 내용, 아래는 늘 보이는 단추 줄.
class StepPage extends StatelessWidget {
  const StepPage({super.key, required this.children, required this.footer, this.top = 24});
  final List<Widget> children;
  final Widget footer;
  final double top;

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, top, 20, 16),
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: footer),
      ]);
}

/// '이전' + 넓은 주 단추 한 줄.
class BackNextRow extends StatelessWidget {
  const BackNextRow({super.key, this.onBack, required this.nextLabel, required this.onNext, this.backLabel = '이전'});
  final VoidCallback? onBack;
  final String nextLabel;
  final VoidCallback? onNext;
  final String backLabel;

  @override
  Widget build(BuildContext context) => Row(children: [
        if (onBack != null) ...[DsButton(backLabel, onPressed: onBack), const SizedBox(width: 8)],
        Expanded(child: DsButton.primary(nextLabel, onPressed: onNext, block: true)),
      ]);
}

/// 본문 글자(.t-body).
Text bodyText(BuildContext context, String text, {Color? color, FontWeight? weight}) =>
    Text(text, style: DsText.body.copyWith(color: color ?? context.ds.ink, fontWeight: weight));

/// '**굵게**' 부분만 굵게 쓴다.
Text richBody(BuildContext context, String text, {Color? color}) {
  final c = context.ds;
  final parts = text.split('**');
  return Text.rich(
    TextSpan(children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ]),
    style: DsText.body.copyWith(color: color ?? c.ink),
  );
}

/// 시각 고르기 창을 연다(자정 기준 분). 취소하면 null.
Future<int?> pickClock(BuildContext context, int minutes) async {
  final m = ((minutes % 1440) + 1440) % 1440;
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    initialEntryMode: TimePickerEntryMode.inputOnly,
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

/// 이름표 없는 시각 칸(누르면 시각 고르기).
class ClockBox extends StatelessWidget {
  const ClockBox({super.key, required this.value, required this.onChanged, required this.semanticLabel});
  final int value;
  final ValueChanged<int> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Pressable(
      scale: 0.98,
      semanticLabel: '$semanticLabel ${formatClock(value)}',
      onTap: () async {
        final v = await pickClock(context, value);
        if (v != null) onChanged(v);
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
        child: Text(formatClock(value), style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num)),
      ),
    );
  }
}

/// 시간(0.5시간 단위) 입력. 값은 분.
class HoursField extends StatelessWidget {
  const HoursField({super.key, required this.label, required this.minutes, required this.onChanged, this.minHours = 4, this.maxHours = 12});
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;
  final double minHours;
  final double maxHours;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final h = minutes / 60;
    final text = h == h.roundToDouble() ? '${h.toInt()}' : h.toStringAsFixed(1);
    void set(int m) => onChanged(m.clamp((minHours * 60).round(), (maxHours * 60).round()));
    return DsField(
      label: '$label (시간)',
      child: Container(
        height: 44,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          DsIconButton(DsIcons.minus, onPressed: h > minHours ? () => set(minutes - 30) : null, label: '30분 줄이기', size: 40, iconSize: 18),
          Expanded(child: Center(child: Text(text, style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num)))),
          DsIconButton(DsIcons.plus, onPressed: h < maxHours ? () => set(minutes + 30) : null, label: '30분 늘리기', size: 40, iconSize: 18),
        ]),
      ),
    );
  }
}

/// 위 작은 회색 단계 이름 + 큰 제목.
class StepHead extends StatelessWidget {
  const StepHead({super.key, required this.step, required this.title, this.desc});
  final String step;
  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        LabelText(step),
        const SizedBox(height: 6),
        Semantics(header: true, child: Text(title, style: DsText.title.copyWith(color: context.ds.ink))),
        if (desc != null) ...[const SizedBox(height: 6), LabelText(desc!)],
      ]);
}

// ---------------------------------------------------------------------------
// 처음 접속: 목표 정하기
// ---------------------------------------------------------------------------

const _focus = [
  (id: GoalFocus.wake, icon: DsIcons.sun, title: '일찍 일어나기', desc: '기상 시각을 정하고 매주 조금씩 당겨요'),
  (id: GoalFocus.sleep, icon: DsIcons.moon, title: '충분히 자기', desc: '목표 수면 시간에 맞춰 취침 알림을 맞춰요'),
  (id: GoalFocus.breakfast, icon: DsIcons.meal, title: '아침 챙겨 먹기', desc: '기상과 출발 사이에 아침 시간을 넣어요'),
  (id: GoalFocus.exercise, icon: DsIcons.exercise, title: '운동 습관', desc: '매일 빈 시간에 운동을 넣어요'),
  (id: GoalFocus.tasks, icon: DsIcons.tasks, title: '할 일 미루지 않기', desc: '할 일을 빈 시간에 자동으로 배치해요'),
];

class GoalStep extends StatefulWidget {
  const GoalStep({super.key, required this.onBack, required this.onNext});
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  State<GoalStep> createState() => _GoalStepState();
}

class _GoalStepState extends State<GoalStep> {
  /// 직접 고른 목표.
  late List<GoalFocus> _manual;

  /// 글에서 읽었지만 사용자가 끈 목표.
  final List<GoalFocus> _removed = [];

  // 사용자가 직접 바꾼 값은 글에서 읽은 값보다 앞선다(null이면 아직 안 바꿈).
  int? _wakeIn;
  int? _sleepIn;
  int? _exIn;

  bool _otherOn = false;
  late final TextEditingController _text;
  GoalReading _reading = readGoalText('');

  @override
  void initState() {
    super.initState();
    final i = context.store.state.intent;
    _manual = [...?i?.focus];
    _wakeIn = i?.wake;
    _sleepIn = i?.sleepMinutes;
    _exIn = i?.exerciseMinutes;
    _otherOn = i?.note != null;
    _text = TextEditingController(text: i?.note ?? '');
    _reread();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reread() => _reading = readGoalText(_otherOn ? _text.text : '');

  int get _wake => _wakeIn ?? _reading.wake ?? 7 * 60;
  int get _sleep => _sleepIn ?? _reading.sleepMinutes ?? 420;
  int get _ex => _exIn ?? _reading.exerciseMinutes ?? 30;

  List<GoalFocus> get _sel => [
        for (final f in _focus)
          if (_manual.contains(f.id) || (_reading.focus.contains(f.id) && !_removed.contains(f.id))) f.id,
      ];

  bool _on(GoalFocus f) => _sel.contains(f);
  bool _auto(GoalFocus f) => !_manual.contains(f) && _reading.focus.contains(f) && !_removed.contains(f);

  void _toggle(GoalFocus f) {
    haptic(6);
    setState(() {
      if (_on(f)) {
        _manual.remove(f);
        if (_reading.focus.contains(f)) _removed.add(f);
      } else {
        _manual.add(f);
        _removed.remove(f);
      }
    });
  }

  Widget _card({required bool on, required DsIcons icon, required String title, required String desc, required VoidCallback onTap, Widget? tag}) {
    final c = context.ds;
    return Pressable(
      scale: 0.98,
      selected: on,
      semanticLabel: title,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: on ? 13 : 14, vertical: on ? 11 : 12),
        decoration: BoxDecoration(
          color: on ? c.pillBg : c.surface,
          border: Border.all(color: on ? c.accent : c.lineBtn, width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: on ? c.accent : c.surface2, shape: BoxShape.circle),
            child: Center(child: DsIcon(on ? DsIcons.check : icon, size: 18, color: on ? c.accentInk : c.accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: DsText.base.copyWith(fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: 2),
              LabelText(desc),
            ]),
          ),
          if (tag != null) ...[const SizedBox(width: 8), tag],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final sel = _sel;
    final r = _reading;
    final typed = _text.text.trim().isNotEmpty;
    final exChoices = ({15, 30, 45, 60, _ex}.toList()..sort());
    return StepPage(
      children: [
        const StepHead(step: '목표 정하기', title: '무엇을 바꾸고 싶어요?', desc: "여러 개 골라도 돼요. 마땅한 게 없으면 '기타'에 적어 주세요. 첫날 기록을 본 뒤 이 목표에 맞춰 일정을 짜요."),
        Semantics(
          label: '바꾸고 싶은 것',
          container: true,
          child: Column(children: [
            for (final f in _focus) ...[
              if (f != _focus.first) const SizedBox(height: 8),
              _card(
                on: _on(f.id),
                icon: f.icon,
                title: f.title,
                desc: f.desc,
                onTap: () => _toggle(f.id),
                tag: _auto(f.id)
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: c.pillBg, borderRadius: BorderRadius.circular(999)),
                        child: Text('적은 글에서', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.accentStrong)),
                      )
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            _card(
              on: _otherOn,
              icon: DsIcons.chat,
              title: '기타 · 직접 적기',
              desc: '하고 싶은 걸 적으면 알아서 읽고 목표를 맞춰요',
              onTap: () {
                haptic(6);
                setState(() {
                  _otherOn = !_otherOn;
                  _reread();
                });
              },
            ),
          ]),
        ),
        if (_otherOn)
          DsCard(gap: 12, children: [
            DsField(
              label: '바꾸고 싶은 것을 편하게 적어 주세요',
              child: TextField(
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                style: DsText.body.copyWith(color: c.ink),
                decoration: dsInput(context, hint: '예: 6시 반에 일어나고 저녁 8시에 30분 달리기').copyWith(counterText: ''),
                onChanged: (_) => setState(_reread),
              ),
            ),
            if (!typed)
              ChipWrap(children: [
                for (final e in goalExamples)
                  DsChip(
                    label: e,
                    selected: false,
                    onTap: () => setState(() {
                      _text.text = e;
                      _reread();
                    }),
                  ),
              ])
            else
              Semantics(
                liveRegion: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LabelText(r.found.isNotEmpty ? '이렇게 읽고 위 목표에 반영했어요' : '아직 읽은 목표가 없어요'),
                  if (r.found.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in r.found) Pill(f.text, kind: _removed.contains(f.focus) ? PillKind.gray : PillKind.accent),
                    ]),
                  ],
                  if (r.unknown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    LabelText("'${r.unknown.join("', '")}'${_hasFinal(r.unknown.last) ? '은' : '는'} 아직 일정에 자동으로 넣지 못해요. 시작한 뒤 할 일로 넣을 수 있어요."),
                  ],
                ]),
              ),
          ]),
        if (_on(GoalFocus.wake) || _on(GoalFocus.sleep) || _on(GoalFocus.exercise))
          DsCard(gap: 14, children: [
            if (_on(GoalFocus.wake)) TimeField(label: '목표 기상 시각', value: _wake, onChanged: (v) => setState(() => _wakeIn = v)),
            if (_on(GoalFocus.sleep)) HoursField(label: '목표 수면 시간', minutes: _sleep, minHours: 5, maxHours: 10, onChanged: (v) => setState(() => _sleepIn = v)),
            if (_on(GoalFocus.exercise))
              DsField(
                label: '운동 시간${r.exerciseTitle != null && r.exerciseTitle != '운동' ? ' · ${r.exerciseTitle}' : ''}',
                child: ChipWrap(children: [
                  for (final m in exChoices) DsChip(label: '$m분', selected: _ex == m, onTap: () => setState(() => _exIn = m)),
                ]),
              ),
            if (_on(GoalFocus.wake)) LabelText('지금 기상이 ${formatClock(_wake)}보다 30분 넘게 늦으면, 한 번에 바꾸지 않고 매주 30분씩 당겨요.'),
          ]),
      ],
      footer: BackNextRow(
        onBack: widget.onBack,
        nextLabel: sel.isNotEmpty ? '${sel.length}개 목표로 다음' : '하나 이상 골라 주세요',
        onNext: sel.isEmpty
            ? null
            : () {
                final ex = sel.contains(GoalFocus.exercise);
                final note = _text.text.trim();
                context.store.setIntent(
                  focus: sel,
                  wake: _wake,
                  sleepMinutes: _sleep,
                  exerciseMinutes: _ex,
                  exerciseTitle: ex ? r.exerciseTitle : null,
                  exerciseStart: ex ? r.exerciseStart : null,
                  note: _otherOn && note.isNotEmpty ? note : null,
                );
                widget.onNext();
              },
      ),
    );
  }
}

/// 마지막 글자에 받침이 있는지(조사 고르기).
bool _hasFinal(String word) {
  final w = word.trim();
  if (w.isEmpty) return false;
  final c = w.codeUnitAt(w.length - 1);
  return c >= 0xAC00 && c <= 0xD7A3 && (c - 0xAC00) % 28 != 0;
}

// ---------------------------------------------------------------------------
// 동의: 생활 기록(필수) · 베타 지표 내보내기(선택)
// ---------------------------------------------------------------------------

/// 건강 기록 수집·이용 동의(필수) + 베타 지표 동의(선택).
class ConsentPanel extends StatefulWidget {
  const ConsentPanel({super.key, this.title = '기록 전에 확인해 주세요', this.onBack, required this.onDone});
  final String title;
  final VoidCallback? onBack;
  final VoidCallback onDone;

  @override
  State<ConsentPanel> createState() => _ConsentPanelState();
}

class _ConsentPanelState extends State<ConsentPanel> {
  late bool _health;
  late bool _metrics;
  bool _full = false;

  @override
  void initState() {
    super.initState();
    final c = context.store.state.consent;
    _health = c?.health ?? false;
    _metrics = c?.metrics ?? false;
  }

  Widget _row(BuildContext context, DsIcons icon, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: DsIcon(icon, size: 18, color: context.ds.accent)),
        const SizedBox(width: 10),
        Expanded(child: richBody(context, text)),
      ]);

  Widget _check(BuildContext context, {required bool value, required ValueChanged<bool> onChanged, required String text, String? sub}) {
    final c = context.ds;
    return Semantics(
      checked: value,
      label: text.replaceAll('**', ''),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          haptic(6);
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: value ? c.accent : c.lineBtn), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: value ? c.accent : Colors.transparent,
                border: Border.all(color: value ? c.accent : c.lineBtn, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: value ? Center(child: DsIcon(DsIcons.check, size: 16, stroke: 2.4, color: c.accentInk)) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                richBody(context, text),
                if (sub != null) ...[const SizedBox(height: 2), LabelText(sub)],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return StepPage(
      children: [
        StepHead(step: '동의', title: widget.title),
        DsCard(gap: 14, children: [
          _row(context, DsIcons.check, '**기록하는 것** · 수면·식사·업무·운동·휴식을 시작하고 끝낸 시각, 기상 알람에 응답한 시각'),
          _row(context, DsIcons.home, '**저장하는 곳** · 이 기기에만 저장하고 서버로 보내지 않아요'),
          _row(context, DsIcons.trash, '**지우기** · 설정 → 데이터 → 모든 기록 지우기로 언제든 지워요'),
        ]),
        _check(context, value: _health, onChanged: (v) => setState(() => _health = v), text: '**[필수]** 생활 기록(수면·식사·운동 시각) 수집·이용에 동의해요'),
        _check(
          context,
          value: _metrics,
          onChanged: (v) => setState(() => _metrics = v),
          text: '**[선택]** 베타 지표 파일 내보내기에 동의해요',
          sub: '이름·기록 시각·할 일 제목 없이, 쓴 날 수와 주별 셋 데이 수 같은 숫자만 담겨요. 내보낼 때마다 내용을 먼저 보여 드려요.',
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pressable(
            scale: 0.98,
            semanticLabel: '개인정보 처리 안내 전문 ${_full ? '접기' : '펼치기'}',
            onTap: () => setState(() => _full = !_full),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: LabelText('${_full ? '▾' : '▸'} 개인정보 처리 안내 전문')),
          ),
          if (_full)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in const [
                  '1. 처리 항목: 활동 종류와 시작·끝 시각, 알람 응답 시각, 스누즈 횟수, 목표 값, 할 일 이름·걸리는 시간, 가져온 캘린더 일정.',
                  '2. 목적: 하루 일정과 알람을 자동으로 짜고, 목표를 단계적으로 맞추기 위해서.',
                  '3. 보관: 이 기기의 앱 저장 공간. 사용자가 지울 때까지. 서버 전송·제3자 제공 없음.',
                  '4. 베타 지표(선택): 사용자가 직접 내보낸 파일만 운영자가 받으며, 익명 번호로만 구분해요.',
                  '5. DaySet은 의료 서비스가 아니에요. 진단·치료·처방을 하지 않아요.',
                  '6. 동의 철회: 설정 → 데이터에서 동의를 거두면 기록을 지우고 처음 화면으로 돌아가요.',
                ]) ...[LabelText(t, color: c.muted), const SizedBox(height: 6)],
              ]),
            ),
        ]),
      ],
      footer: BackNextRow(
        onBack: widget.onBack,
        nextLabel: _health ? '동의하고 계속' : '필수 항목에 동의해 주세요',
        onNext: !_health
            ? null
            : () {
                context.store.setConsent(health: _health, metrics: _metrics);
                widget.onDone();
              },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 알림 켜기
// ---------------------------------------------------------------------------

/// 알림 단계. 이 빌드에 알림 기능이 없으면(1단계) 설정만 저장하고 그렇다고 알린다.
class NotifyStep extends StatefulWidget {
  const NotifyStep({super.key, required this.onBack, required this.onDone});
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<NotifyStep> createState() => _NotifyStepState();
}

class _NotifyStepState extends State<NotifyStep> {
  bool _busy = false;
  String? _msg;

  Future<void> _turnOn() async {
    final store = context.store;
    if (!notifyPort.available) {
      store.setNotify((n) => n.copyWith(enabled: false));
      store.track('notify_enable', 'unavailable');
      setState(() => _msg = '잠금화면 알림은 다음 업데이트에서 켜져요. 지금은 앱이 열려 있을 때 화면 안 팝업으로 알려 드려요.');
      return;
    }
    setState(() => _busy = true);
    final ok = await notifyPort.request();
    if (!mounted) return;
    setState(() => _busy = false);
    store.setNotify((n) => n.copyWith(enabled: ok));
    store.track('notify_enable', ok ? 'granted' : 'denied');
    setState(() => _msg = ok ? '알림을 켰어요. 기록할 때가 되면 알려 드릴게요.' : '알림을 허용하지 않았어요. 기기 설정에서 언제든 켤 수 있어요. 앱 안 팝업으로는 계속 알려 드려요.');
    if (ok) Future.delayed(const Duration(milliseconds: 900), () => mounted ? widget.onDone() : null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return StepPage(
      children: [
        const StepHead(step: '알림', title: '기록할 때를 알려 드릴게요'),
        bodyText(context, "지금 일정을 알림에 계속 띄워 두고, 일정이 시작됐는데 기록이 없으면 알려요. 알림의 '기록하기'를 누르면 바로 기록돼요."),
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: c.surface2, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DaySet · 지금', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 4),
              Text('12:00 점심 식사 시간이에요', style: DsText.base.copyWith(fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 4),
              const LabelText("시작했으면 '기록하기'를 눌러 주세요"),
              const SizedBox(height: 10),
              Row(children: [
                Text('기록하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentStrong)),
                const SizedBox(width: 18),
                Text('지금은 안 해요', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentStrong)),
              ]),
            ]),
          ),
        ),
        LabelText(notifyPort.available
            ? '잠금화면에서도 알림의 버튼으로 바로 기록할 수 있어요.'
            : '잠금화면 알림은 다음 업데이트에서 켜져요. 그 전까지는 앱이 열려 있을 때 화면 안 팝업으로 같은 내용을 보여 드려요.'),
        if (_msg != null) Semantics(liveRegion: true, child: LabelText(_msg!, color: c.accentStrong)),
      ],
      footer: Column(mainAxisSize: MainAxisSize.min, children: [
        DsButton.primary(_busy ? '허용 창을 확인해 주세요…' : '알림 켜기', icon: DsIcons.bell, block: true, onPressed: _busy || _msg != null && !notifyPort.available ? null : _turnOn),
        const SizedBox(height: 8),
        Row(children: [
          DsButton('이전', onPressed: widget.onBack),
          const SizedBox(width: 8),
          Expanded(child: DsButton(_msg != null ? '계속' : '나중에 · 앱 안 팝업만', block: true, onPressed: widget.onDone)),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 설문(7일째·28일째): 없어지면 얼마나 아쉬운지
// ---------------------------------------------------------------------------

const _answers = [
  (id: 'very', label: '매우 아쉬워요'),
  (id: 'some', label: '조금 아쉬워요'),
  (id: 'not', label: '아쉽지 않아요'),
  (id: 'stopped', label: '이미 안 써요'),
];

/// 7일째·28일째 설문 카드(때가 아니면 아무것도 그리지 않는다).
class SurveyCard extends StatefulWidget {
  const SurveyCard({super.key});

  @override
  State<SurveyCard> createState() => _SurveyCardState();
}

class _SurveyCardState extends State<SurveyCard> {
  String? _answer;
  final _best = TextEditingController();
  final _worst = TextEditingController();

  @override
  void dispose() {
    _best.dispose();
    _worst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final due = surveyDue(s, context.ui.now);
    if (due == null) return const SizedBox.shrink();
    final c = context.ds;
    return Semantics(
      label: '짧은 설문',
      container: true,
      child: DsCard(tint: true, gap: 14, children: [
        Row(children: [
          Expanded(child: DsTitle(due == 'd7' ? '일주일 써 보니 어때요?' : '한 달 써 보니 어때요?')),
          const LabelText('1분'),
        ]),
        bodyText(context, 'DaySet을 더 이상 쓸 수 없게 되면 어떨 것 같아요?'),
        ChipWrap(children: [
          for (final a in _answers) DsChip(label: a.label, selected: _answer == a.id, onTap: () => setState(() => _answer = a.id)),
        ]),
        if (_answer != null) ...[
          TextField(controller: _best, maxLength: 200, decoration: dsInput(context, hint: '가장 좋았던 점(선택)').copyWith(counterText: ''), style: DsText.base.copyWith(color: c.ink)),
          TextField(controller: _worst, maxLength: 200, decoration: dsInput(context, hint: '가장 불편했던 점(선택)').copyWith(counterText: ''), style: DsText.base.copyWith(color: c.ink)),
        ],
        Row(children: [
          Expanded(
            child: DsButton.primary('보내기', block: true, onPressed: _answer == null
                ? null
                : () {
                    final best = _best.text.trim();
                    final worst = _worst.text.trim();
                    context.store.answerSurvey(key: due, answer: _answer!, best: best.isEmpty ? null : best, worst: worst.isEmpty ? null : worst);
                    haptic(10);
                    context.toast('답해 줘서 고마워요. 다음 일정 개선에 반영할게요');
                  }),
          ),
          const SizedBox(width: 8),
          DsButton('나중에', onTint: true, onPressed: context.store.surveyLater),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 불편 신고·의견
// ---------------------------------------------------------------------------

const _kinds = [(id: 'bug', label: '오류'), (id: 'hard', label: '불편해요'), (id: 'idea', label: '제안')];

/// 불편·제안 보내기 창.
Future<void> showReportSheet(BuildContext context, {required String page}) =>
    showDsSheet<void>(context, title: '불편 신고·의견', builder: (ctx) => _ReportBody(page: page, toast: context.toast));

class _ReportBody extends StatefulWidget {
  const _ReportBody({required this.page, required this.toast});
  final String page;
  final void Function(String text, {UndoKind undo}) toast;

  @override
  State<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<_ReportBody> {
  String _kind = 'hard';
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return DsStack(children: [
      ChipWrap(children: [
        for (final k in _kinds) DsChip(label: k.label, selected: _kind == k.id, onTap: () => setState(() => _kind = k.id)),
      ]),
      TextField(
        controller: _text,
        autofocus: true,
        minLines: 5,
        maxLines: 5,
        maxLength: 1000,
        onChanged: (_) => setState(() {}),
        style: DsText.base.copyWith(color: c.ink),
        decoration: dsInput(context, hint: '어느 화면에서 무엇을 하다가 어땠는지 적어 주세요').copyWith(counterText: ''),
      ),
      const LabelText('이 기기에 저장되고, 베타 지표 파일을 보낼 때 함께 담겨요.'),
      DsButton.primary('남기기', block: true, onPressed: _text.text.trim().isEmpty
          ? null
          : () {
              context.store.addReport(kind: _kind, text: _text.text.trim(), page: widget.page);
              widget.toast('남겼어요. 지표 파일을 보낼 때 함께 전달돼요');
              Navigator.of(context).pop();
            }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 베타 지표: 미리 보기 + 파일 내보내기
// ---------------------------------------------------------------------------

/// 설정의 베타 지표 카드(보기·내보내기).
class MetricsCard extends StatefulWidget {
  const MetricsCard({super.key});

  @override
  State<MetricsCard> createState() => _MetricsCardState();
}

class _MetricsCardState extends State<MetricsCard> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final c = context.ds;
    if (!(s.consent?.metrics ?? false)) {
      return Semantics(
        label: '베타 지표',
        container: true,
        child: const DsCard(gap: 14, children: [
          DsTitle('베타 지표'),
          LabelText("지표 내보내기에 동의하지 않았어요. 아래 '동의 다시 보기'에서 바꿀 수 있어요."),
        ]),
      );
    }
    final report = computeMetrics(s, context.ui.now);
    final text = const JsonEncoder.withIndent('  ').convert(report);
    final retention = report['retention'] as Map;
    final activation = report['activation'] as Map;
    final weeks = (report['habit'] as Map)['weeks'] as List;
    final lastWeek = weeks.isEmpty ? null : weeks.last as Map;
    final surveys = report['surveys'] as List;
    final feedback = report['feedback'] as List;
    final anon = report['anonId'] as String;
    final date = (report['generatedAt'] as String).substring(0, 10);

    Widget cell(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LabelText(label),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink, fontFeatures: DsText.num)),
          ]),
        );

    return Semantics(
      label: '베타 지표',
      container: true,
      child: DsCard(gap: 14, children: [
        Row(children: [const Expanded(child: DsTitle('베타 지표')), LabelText('익명 $anon')]),
        Row(children: [
          Expanded(child: cell('쓴 날', '${retention['activeDays']}일')),
          const SizedBox(width: 8),
          Expanded(child: cell('활성화', activation['activated'] == true ? '완료' : '전')),
        ]),
        Row(children: [
          Expanded(child: cell('이번 주 셋 데이', '${lastWeek?['setDays'] ?? 0}일')),
          const SizedBox(width: 8),
          Expanded(child: cell('7일 유지', retention['d7'] == true ? '예' : '아직')),
        ]),
        LabelText('담기는 것: 쓴 날 수, 주별 셋 데이 수, 기능 사용 횟수, 설문(${surveys.isNotEmpty ? '응답함' : '없음'}), 불편 신고 ${feedback.length}건 · 담기지 않는 것: 이름, 기록 시각, 할 일·일정 제목, 위치'),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DsButton.primary('지표 파일 내보내기', onPressed: () async {
            final store = context.store;
            final toast = context.ui.actions.toast;
            final r = await shareTextFile('dayset-metrics-$anon-$date.json', text);
            store.track('metrics_export');
            toast(r == ShareOutcome.shared ? '지표 파일을 내보냈어요. 베타 설문 폼에 올려 주세요' : r.text);
          }),
          DsButton('복사', onPressed: () async {
            final toast = context.ui.actions.toast;
            toast(await copyText(text) ? '지표를 복사했어요' : '복사하지 못했어요. 파일로 내보내 주세요');
          }),
          DsButton(_show ? '내용 접기' : '보낼 내용 보기', kind: BtnKind.ghost, small: true, onPressed: () => setState(() => _show = !_show)),
        ]),
        if (_show)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(child: SelectableText(text, style: TextStyle(fontSize: 11, height: 15 / 11, color: c.ink, fontFamily: 'monospace'))),
          ),
      ]),
    );
  }
}
