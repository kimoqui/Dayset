// 알람 화면(기상·취침). 웹 버전 src/ui/AlarmOverlay.tsx와 같은 흐름.
// 1단계에서는 앱이 열려 있을 때만 울린다: 소리 대신 진동 + 시스템 알림음을 1.5초마다 반복한다.
// 기기 알람(앱을 닫아도 울리는 알람)은 3단계(AlarmKit·안드로이드 알람)에서 붙인다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/derive.dart';
import '../app/store.dart';
import '../core/model/models.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

class AlarmOverlay extends StatefulWidget {
  const AlarmOverlay({super.key, required this.ring, this.test = false, required this.onDone});
  final Ring ring;

  /// 설정의 '알람 미리 보기': 기록하지 않는다.
  final bool test;
  final VoidCallback onDone;

  @override
  State<AlarmOverlay> createState() => _AlarmOverlayState();
}

class _AlarmOverlayState extends State<AlarmOverlay> {
  Timer? _beep;

  @override
  void initState() {
    super.initState();
    _ring();
    _beep = Timer.periodic(const Duration(milliseconds: 1500), (_) => _ring());
  }

  void _ring() {
    try {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    } catch (_) {
      // 진동·소리를 낼 수 없는 기기
    }
  }

  void _stop() {
    _beep?.cancel();
    _beep = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _done(VoidCallback action) {
    _stop();
    action();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    const n = DsColors.night;
    final store = context.store;
    final s = context.app;
    final t = context.ui.now;
    final ring = widget.ring;
    final snoozes = s.alarms[ring.key]?.snoozes ?? 0;
    final wake = ring.kind == RingKind.wake;

    final String head;
    final String sub;
    final List<Widget> buttons;
    if (wake) {
      final plan = planFor(s, dateKey(t), t);
      head = widget.test ? '알람 미리 듣기' : '기상 알람';
      sub = plan.plan.alarms.first.reason;
      buttons = [
        _RingButton('알람 끄기 · 기상 기록', primary: true, onTap: () => _done(() {
              if (!widget.test) store.dismissWake(ring);
            })),
        _RingButton('5분 뒤 다시', onTap: () => _done(() {
              if (!widget.test) store.snooze(ring, 5);
            })),
      ];
    } else {
      final tomorrow = planFor(s, dateKey(addDays(t, 1)), t);
      head = '취침 시간이에요';
      sub = '내일 ${formatHm(tomorrow.wake)} 기상까지 ${formatDuration(math.max(0, diffMin(tomorrow.wake, t)))}';
      buttons = [
        _RingButton('잘게요 · 수면 기록', primary: true, onTap: () => _done(() => store.dismissBed(ring, sleepNow: true))),
        _RingButton('30분 뒤 다시', onTap: () => _done(() => store.snooze(ring, 30))),
        _RingButton('오늘은 끄기', borderless: true, onTap: () => _done(() => store.dismissBed(ring, sleepNow: false))),
      ];
    }

    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final pad = MediaQuery.paddingOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 240),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: wake ? '기상 알람' : '취침 알림',
        child: Material(
          color: wake ? n.bg : n.nav,
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, 72 + pad.top, 28, 40 + pad.bottom),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(head, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: n.ink.withValues(alpha: 0.8))),
                const SizedBox(height: 10),
                Text(formatHm(t),
                    style: TextStyle(fontSize: 64, height: 72 / 64, fontWeight: FontWeight.w700, letterSpacing: -1, color: n.ink, fontFeatures: DsText.num)),
                const SizedBox(height: 10),
                Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 22 / 15, color: n.ink.withValues(alpha: 0.85))),
                if (wake && snoozes > 0) ...[
                  const SizedBox(height: 10),
                  Text('$snoozes번 미뤘어요', style: TextStyle(fontSize: 13, color: n.ink.withValues(alpha: 0.7))),
                ],
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(height: 12), buttons[i]],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 알람 화면 단추: 늘 나이트 색(테마와 상관없이 어두운 화면).
class _RingButton extends StatelessWidget {
  const _RingButton(this.label, {required this.onTap, this.primary = false, this.borderless = false});
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    const n = DsColors.night;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? n.accent : Colors.transparent,
          border: Border.all(color: primary ? n.accent : (borderless ? Colors.transparent : n.lineBtn)),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 16, fontWeight: primary ? FontWeight.w700 : FontWeight.w500, color: primary ? n.accentInk : n.ink)),
      ),
    );
  }
}
