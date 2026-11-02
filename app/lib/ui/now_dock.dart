// 일정 체크 팝업: 화면 아래(탭 위)에 늘 떠 있다. 웹 버전 src/ui/NowDock.tsx와 같은 흐름.
// 일정이 시작됐는데 기록이 없으면 크게 펼쳐 '시작했어요'를 묻고, 기록 중이면 작은 띠로 지금·다음 일정을 보여 준다.

import 'package:flutter/material.dart';

import '../app/now_check.dart';
import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import 'kit.dart';
import 'theme.dart';

const _labelShort = {
  Activity.sleep: '수면',
  Activity.meal: '식사',
  Activity.work: '업무',
  Activity.exercise: '운동',
  Activity.rest: '휴식',
};

class NowDock extends StatefulWidget {
  const NowDock({super.key, required this.check, required this.onRecord, required this.onSkip});
  final NowCheck check;
  /// [at]: 제때 누르지 못했을 때 실제로 시작한(끝난) 시각. 없으면 지금.
  final void Function(Activity a, {DateTime? at}) onRecord;
  final void Function(String id) onSkip;

  @override
  State<NowDock> createState() => _NowDockState();
}

class _NowDockState extends State<NowDock> {
  late bool _min = !_alert;
  late String _key = widget.check.key;
  late bool _wasAlert = _alert;

  /// 늦게 눌렀을 때 고른 시각: null = 일정대로, -1 = 지금, 그 밖 = 직접 고른 분(0~1439).
  int? _when;

  bool get _alert => (widget.check.kind == CheckKind.due || widget.check.kind == CheckKind.over) && !widget.check.skipped;

  @override
  void didUpdateWidget(NowDock old) {
    super.didUpdateWidget(old);
    // 새로 기록할 일이 생기면 다시 펼친다.
    if (widget.check.key != _key || _alert != _wasAlert) {
      _key = widget.check.key;
      _wasAlert = _alert;
      _min = !_alert;
      _when = null;
    }
  }

  BoxDecoration _box(DsColors c, {required bool open, bool warn = false}) => BoxDecoration(
        color: c.surface,
        border: Border.all(color: open || warn ? c.accent : c.lineStrong, width: open ? 2 : 1),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 28, offset: Offset(0, 10))],
      );

  @override
  Widget build(BuildContext context) {
    final check = widget.check;
    if (check.kind == CheckKind.none) return const SizedBox.shrink();
    final c = context.ds;
    final b = check.block;
    final next = check.next;
    final cur = check.current != null ? '${check.current!.label} ${formatDuration(check.currentMinutes)}째' : '기록 없음';
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // 작은 띠
    if (_min || !_alert) {
      var text = '';
      var warn = false;
      if (check.kind == CheckKind.ok && b != null) {
        text = '지금 ${b.title} · ${formatHm(b.end)}까지';
      } else if (check.kind == CheckKind.next && next != null) {
        text = '다음 ${formatHm(next.start)} ${next.title} · ${formatDuration(check.minutes)} 뒤';
      } else if (check.kind == CheckKind.next) {
        text = '오늘 남은 일정이 없어요';
      } else if (check.kind == CheckKind.due && b != null) {
        text = '${b.title} · ${check.skipped ? '이번엔 건너뜀' : '기록 전'}';
        warn = !check.skipped;
      } else if (check.kind == CheckKind.over && b != null) {
        text = '${b.title} 끝날 시간이 지났어요';
        warn = !check.skipped;
      }
      final canRecord = (check.kind == CheckKind.due || check.kind == CheckKind.over) && check.expected != null;
      return Semantics(
        container: true,
        liveRegion: true,
        label: '일정 체크',
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          decoration: _box(c, open: false, warn: warn),
          child: Row(children: [
            _Dot(kind: check.kind, reduce: reduce),
            const SizedBox(width: 10),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink))),
            if (canRecord) ...[
              const SizedBox(width: 10),
              Pressable(
                semanticLabel: check.kind == CheckKind.over ? '끝났어요' : '기록하기',
                onTap: () => widget.onRecord(check.kind == CheckKind.over ? Activity.rest : check.expected!),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(16)),
                  child: Text(check.kind == CheckKind.over ? '끝났어요' : '기록하기',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentInk)),
                ),
              ),
            ],
            if (_alert) ...[
              const SizedBox(width: 4),
              Transform.rotate(
                angle: 1.5708,
                child: DsIconButton(DsIcons.back, onPressed: () => setState(() => _min = false), label: '펼치기', size: 32, iconSize: 16),
              ),
            ],
          ]),
        ),
      );
    }

    // 펼친 팝업: 기록하라는 알림
    final exp = check.expected!;
    final isOver = check.kind == CheckKind.over;
    final nextAct = next == null ? null : expectedActivity(next);
    // 일정 시각에서 5분 넘게 지났으면 언제 시작(끝)했는지 고르게 한다. 웹 NowDock과 같은 규칙.
    final planAt = isOver ? b!.end : b!.start;
    final nowAt = planAt.add(Duration(minutes: check.minutes));
    final late = check.minutes >= 5;
    DateTime? pickAt() {
      if (!late || _when == -1) return null;
      final w = _when;
      if (w == null) return planAt;
      var d = DateTime(nowAt.year, nowAt.month, nowAt.day, w ~/ 60, w % 60);
      if (d.isAfter(nowAt)) d = d.subtract(const Duration(days: 1));
      return d;
    }

    void record(Activity a) => widget.onRecord(a, at: pickAt());
    final body = Semantics(
      container: true,
      liveRegion: true,
      label: '일정 체크',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: _box(c, open: true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _Dot(kind: CheckKind.due, reduce: reduce),
            const SizedBox(width: 6),
            Expanded(child: Text(isOver ? '끝났는지 확인' : '지금 일정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentStrong))),
            Transform.translate(
              offset: const Offset(6, 0),
              child: DsIconButton(DsIcons.close, onPressed: () => setState(() => _min = true), label: '작게 보기', size: 32, iconSize: 16),
            ),
          ]),
          const SizedBox(height: 8),
          Text(isOver ? '${b.title} 끝났어요?' : '${formatHm(b.start)} ${b.title} 시간이에요',
              style: TextStyle(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 8),
          LabelText(isOver
              ? '${formatHm(b.end)}에 끝나는 일정이었어요 · 지금 기록: $cur'
              : '지금 기록: $cur · ${_labelShort[exp]}${objectParticle(_labelShort[exp]!)} 시작했으면 눌러 주세요'),
          if (late) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              LabelText(isOver ? '끝난 시각' : '시작한 시각'),
              DsChip(label: '일정대로 ${formatHm(planAt)}', selected: _when == null, onTap: () => setState(() => _when = null)),
              DsChip(label: '지금 ${formatHm(nowAt)}', selected: _when == -1, onTap: () => setState(() => _when = -1)),
              DsChip(
                label: (_when ?? -1) >= 0 ? formatClock(_when!) : '다른 시각',
                selected: (_when ?? -1) >= 0,
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: planAt.hour, minute: planAt.minute));
                  if (t != null && mounted) setState(() => _when = t.hour * 60 + t.minute);
                },
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if (isOver) ...[
              Expanded(child: DsButton.primary('끝났어요 · 휴식', block: true, onPressed: () => record(Activity.rest))),
              if (nextAct != null && nextAct != exp) ...[
                const SizedBox(width: 8),
                Expanded(child: DsButton('${_labelShort[nextAct]} 시작', block: true, onPressed: () => record(nextAct))),
              ],
              const SizedBox(width: 8),
              DsButton('아직이에요', onPressed: () => widget.onSkip('${b.id}:over')),
            ] else ...[
              Expanded(child: DsButton.primary('${_labelShort[exp]} 시작했어요', block: true, onPressed: () => record(exp))),
              const SizedBox(width: 8),
              DsButton('지금은 안 해요', onPressed: () => widget.onSkip(b.id)),
            ],
          ]),
        ]),
      ),
    );
    if (reduce) return body;
    return TweenAnimationBuilder<double>(
      key: ValueKey(check.key),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(opacity: v.clamp(0, 1), child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
      child: body,
    );
  }
}

/// 상태 점: 기록 중이면 초록, 기록할 때면 앰버로 깜빡인다.
class _Dot extends StatefulWidget {
  const _Dot({required this.kind, required this.reduce});
  final CheckKind kind;
  final bool reduce;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _pulse => !widget.reduce && (widget.kind == CheckKind.due || widget.kind == CheckKind.over);

  @override
  void initState() {
    super.initState();
    if (_pulse) _a.repeat();
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (_pulse && !_a.isAnimating) {
      _a.repeat();
    } else if (!_pulse && _a.isAnimating) {
      _a.stop();
      _a.value = 0;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final color = switch (widget.kind) {
      CheckKind.ok => c.work,
      CheckKind.due || CheckKind.over => c.accent,
      _ => c.muted,
    };
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        // 0→0.5→1 동안 1 → 0.35 → 1
        final t = _a.value;
        final o = _pulse ? 1 - 0.65 * (1 - (2 * t - 1).abs()) : 1.0;
        return Opacity(opacity: o, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)));
      },
    );
  }
}
