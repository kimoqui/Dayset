// 저녁 확인: 기록 없는 일정만 골라 '했어요·못 했어요·쉬는 날'을 묻고, 내일 일정을 확정한다.
// 웹 버전 src/ui/screens/Evening.tsx와 같은 흐름.

import 'package:flutter/material.dart';

import '../../core/engine/achievement.dart';
import '../../core/model/models.dart';
import '../../app/derive.dart';
import '../kit.dart';
import '../scope.dart';
import '../theme.dart';

class EveningScreen extends StatefulWidget {
  const EveningScreen({super.key});

  @override
  State<EveningScreen> createState() => _EveningScreenState();
}

class _EveningScreenState extends State<EveningScreen> {
  String? _missOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final store = context.store;
    final c = context.ds;
    final now = context.ui.now;
    final key = dateKey(now);
    final view = evaluate(s, key, now);
    final tomorrow = planFor(s, dateKey(addDays(now, 1)), now);
    final done = s.eveningDone.contains(key);
    final today0 = dayStart(now);

    final logs = logsAround(s, key).where((l) => !l.isEstimate && l.source != LogSource.evening && (l.end == null || l.end!.isAfter(today0))).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final missed = {for (final m in s.misses) if (m.day == key) m.blockId: m.reason};
    final skipped = {for (final m in s.skips) if (m.day == key) m.blockId};
    final didIds = {for (final l in s.logs) if (l.source == LogSource.evening) l.id.replaceFirst(RegExp('^ev-'), '')};

    // 물어볼 블록: 시작한 지 지난 습관·할 일 중 기록으로 달성이 확인되지 않은 것 + 이미 답한 것
    final asked = view.plan.blocks.where((b) {
      if (b.activity == null || b.kind == BlockKind.fixed || b.activity == Activity.sleep) return false;
      if (b.start.isAfter(now)) return false;
      if (didIds.contains(b.id) || missed.containsKey(b.id) || skipped.contains(b.id)) return true;
      final o = view.outcomes.where((x) => x.block.id == b.id).firstOrNull;
      return o != null && o.outcome != Outcome.achieved && o.outcome != Outcome.pending;
    }).toList();

    final firstEvent = tomorrow.blocks.where((b) => b.kind == BlockKind.fixed && b.locked).firstOrNull;

    return ScreenList(tab: false, children: [
      TopBar(
        title: '오늘 하루 확인',
        sub: '기록 없는 일정만 골라요',
        onBack: context.ui.actions.back,
        right: Pill(view.isSetDay ? '셋 데이' : '습관 ${view.achieved}/${view.total}'),
      ),
      Semantics(
        container: true,
        label: '자동으로 기록된 것',
        child: DsCard(list: true, children: [
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('오늘 자동으로 기록된 것이 없어요', textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
            ),
          for (final (i, l) in logs.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(border: i == logs.length - 1 ? null : Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: c.tint, shape: BoxShape.circle),
                  child: Center(child: DsIcon(DsIcons.check, size: 13, stroke: 3, color: c.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l.activity.label, style: DsText.base.copyWith(color: c.ink))),
                Text('${formatHm(l.start)}${l.end != null ? '–${formatHm(l.end!)}' : ' 부터'}',
                    style: DsText.body.copyWith(color: c.ink, fontFeatures: DsText.num)),
                const SizedBox(width: 12),
                SizedBox(width: 32, child: Text(l.source.label, textAlign: TextAlign.right, style: DsText.label.copyWith(color: c.muted))),
              ]),
            ),
        ]),
      ),
      if (asked.isEmpty)
        DsCard(children: [Text('기록이 없는 일정이 없어요. 오늘은 모두 자동으로 기록됐어요.', style: DsText.body.copyWith(color: c.ink))])
      else
        for (final b in asked) _askCard(context, key, b, missed[b.id], didIds.contains(b.id), skipped.contains(b.id)),
      DsCard(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4), children: [
        DsSwitch(
          value: s.restDays.contains(key),
          onChanged: (v) => store.setRestDay(key, v),
          label: '오늘은 쉬는 날',
          sub: '셋 데이 판정에서 빼요',
          onText: '쉬는 날',
          offText: '아니요',
        ),
      ]),
      Semantics(
        container: true,
        label: '내일',
        child: DsCard(tint: true, children: [
          const LabelText('내일'),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _kv(context, '기상 알람', formatHm(tomorrow.wake), strong: true),
            LabelText(tomorrow.plan.alarms.first.reason),
            const SizedBox(height: 4),
            _kv(context, '오늘 밤 취침', formatHm(tomorrow.bedTonight), strong: true),
            if (firstEvent != null) ...[const SizedBox(height: 4), _kv(context, '첫 일정', '${formatHm(firstEvent.start)} ${firstEvent.title}')],
            const SizedBox(height: 4),
            _kv(context, '할 일', formatDuration(tomorrow.plan.taskMinutes)),
            for (final n in tomorrow.plan.notes) ...[const SizedBox(height: 4), LabelText(n)],
          ]),
          if (done)
            Text('내일 일정을 확정했어요. 기상 알람 ${formatHm(tomorrow.wake)}.', style: DsText.body.copyWith(color: c.accentStrong, fontWeight: FontWeight.w600))
          else
            DsButton.primary('확인 끝 · 내일 일정 확정', block: true, onPressed: () {
              haptic(12);
              store.finishEvening(key);
            }),
        ]),
      ),
    ]);
  }

  Widget _kv(BuildContext context, String k, String v, {bool strong = false}) {
    final c = context.ds;
    return Row(children: [
      Text(k, style: DsText.body.copyWith(color: c.ink)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(v,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DsText.body.copyWith(color: c.ink, fontWeight: strong ? FontWeight.w600 : FontWeight.w400, fontFeatures: DsText.num)),
      ),
    ]);
  }

  Widget _askCard(BuildContext context, String key, ScheduleBlock b, MissReason? reason, bool did, bool skip) {
    final c = context.ds;
    final store = context.store;
    final state = did
        ? 'did'
        : reason != null
            ? 'missed'
            : skip
                ? 'skip'
                : _missOpen == b.id
                    ? 'asking'
                    : 'open';
    final status = switch (state) { 'did' => '했어요', 'skip' => '쉬는 날', 'missed' => '못 했어요', _ => '기록이 없어요' };
    return Semantics(
      container: true,
      label: '${b.title} 확인',
      child: DsCard(children: [
        Text.rich(TextSpan(style: DsText.base.copyWith(color: c.ink), children: [
          TextSpan(text: '${b.title} ${formatHm(b.start)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' · $status'),
        ])),
        if (state == 'open' || state == 'asking')
          Row(children: [
            Expanded(child: DsButton.primary('했어요', square: true, block: true, onPressed: () => store.markDid(key, b))),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                expanded: state == 'asking',
                child: DsButton('못 했어요', square: true, block: true, onPressed: () => setState(() => _missOpen = state == 'asking' ? null : b.id)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: DsButton('쉬는 날', square: true, block: true, onPressed: () => store.markSkipped(key, b))),
          ]),
        if (state == 'asking' || state == 'missed') ...[
          const LabelText('이유를 고르면 다음 일정에 반영해요'),
          Semantics(
            label: '못 한 이유',
            container: true,
            child: ChipWrap(children: [
              for (final r in MissReason.values)
                DsChip(
                  label: r.label,
                  selected: reason == r,
                  onTap: () {
                    store.markMissed(key, b, r);
                    setState(() => _missOpen = null);
                  },
                ),
            ]),
          ),
        ],
        if (state == 'did')
          Row(children: [
            Expanded(
              child: Text(
                b.kind == BlockKind.task ? '${b.title} ${formatDuration(b.minutes)}을 반영했어요' : '${b.activity!.label} ${formatDuration(b.minutes)}을 기록했어요',
                style: DsText.body.copyWith(color: c.accentStrong, fontWeight: FontWeight.w600),
              ),
            ),
            DsButton('바꾸기', kind: BtnKind.ghost, small: true, onPressed: () => store.clearAnswer(key, b)),
          ]),
        if (state == 'did' && b.kind == BlockKind.task) _TaskFinishAsk(taskId: b.taskId),
        if (state == 'skip')
          Row(children: [
            Expanded(child: Text('쉬는 날로 기록했어요. 달성률에서 빼요.', style: DsText.body.copyWith(color: c.muted))),
            DsButton('바꾸기', kind: BtnKind.ghost, small: true, onPressed: () => store.clearAnswer(key, b)),
          ]),
        if (state == 'missed')
          Align(alignment: Alignment.centerLeft, child: DsButton('다시 고르기', kind: BtnKind.ghost, small: true, onPressed: () => store.clearAnswer(key, b))),
      ]),
    );
  }
}

/// 잡은 시간을 다 쓴 할 일: 다 끝냈는지, 시간이 더 필요한지 묻는다(걸리는 시간 보정에 쓴다).
class _TaskFinishAsk extends StatelessWidget {
  const _TaskFinishAsk({required this.taskId});
  final String? taskId;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final store = context.store;
    final t = s.tasks.where((x) => x.id == taskId).firstOrNull;
    if (t == null || t.done || store.taskPlanMinutes(t).remaining > 0) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: '${t.title} 다 끝났는지',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabelText('${t.title}에 잡은 시간을 다 썼어요. 다 끝냈어요?'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            DsButton.primary('끝났어요', small: true, onPressed: () => store.toggleTaskDone(t.id)),
            DsButton('+30분', small: true, onPressed: () => store.extendTask(t.id, 30)),
            DsButton('+1시간', small: true, onPressed: () => store.extendTask(t.id, 60)),
          ]),
        ]),
      ),
    );
  }
}
