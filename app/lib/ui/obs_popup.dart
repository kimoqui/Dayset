// 관찰 준비일(1일차 전날) 안내 팝업. 10초 뒤 저절로 닫힌다. 웹 버전 src/ui/ObsPopup.tsx와 같은 문구.
// - intro: 처음 시작했을 때
// - late: 밤 10시가 넘었는데 아직 '수면'을 누르지 않았을 때 한 번 더

import 'package:flutter/material.dart';

import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

const _seconds = 10;

Future<void> showObsPopup(BuildContext context, ObsPopupKind kind, {required VoidCallback onSleep}) {
  var sleep = false;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0x99050810),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, a, b) => _ObsPop(kind: kind, onSleep: () => sleep = true),
    transitionBuilder: (ctx, a, b, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      if (reduce) return child;
      final curve = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curve), child: child));
    },
  ).then((_) {
    if (sleep) onSleep();
  });
}

class _ObsPop extends StatefulWidget {
  const _ObsPop({required this.kind, required this.onSleep});
  final ObsPopupKind kind;
  final VoidCallback onSleep;

  @override
  State<_ObsPop> createState() => _ObsPopState();
}

class _ObsPopState extends State<_ObsPop> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(vsync: this, duration: const Duration(seconds: _seconds));
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _timer.addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    });
    _timer.forward();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    // 바깥을 눌러 이미 닫히는 중이면(닫힘 애니메이션 동안 타이머가 끝나도) 다른 화면을 닫지 않는다.
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final late = widget.kind == ObsPopupKind.late;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            label: '관찰 안내',
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.accent, width: 2),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: c.pillBg, spreadRadius: 6),
                    const BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 24)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                          child: Text(late ? '잘 시간이 가까워요' : '내일이 1일차', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentInk)),
                        ),
                        const SizedBox(height: 14),
                        Semantics(header: true, child: Text('내일 하루를 그대로 기록해요', style: DsText.title.copyWith(color: c.ink))),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: c.pillBg, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                              child: Center(child: DsIcon(DsIcons.sleep, size: 22, color: c.accentInk)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text("오늘 밤 잘 때 '수면'을 눌러 주세요",
                                  style: TextStyle(fontSize: 16, height: 23 / 16, fontWeight: FontWeight.w700, color: c.ink)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Text('내일은 식사·업무·운동을 시작할 때마다 버튼만 누르면 돼요. 내일 저녁에 기록한 하루를 보고 일정을 같이 정해요.',
                            style: DsText.body.copyWith(color: c.inkSoft)),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (late) ...[
                            Expanded(
                              child: DsButton.primary('지금 잘게요 · 수면 시작', block: true, onPressed: () {
                                widget.onSleep();
                                _close();
                              }),
                            ),
                            const SizedBox(width: 8),
                            DsButton('조금 뒤에', onPressed: _close),
                          ] else
                            Expanded(child: DsButton.primary('알겠어요', block: true, onPressed: _close)),
                        ]),
                      ]),
                    ),
                    // 저절로 닫히기까지 남은 시간
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: AnimatedBuilder(
                        animation: _timer,
                        builder: (context, _) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1 - _timer.value,
                          child: ColoredBox(color: c.accent),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
