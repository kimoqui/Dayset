// 공통 화면 부품. 웹 버전 src/ui/kit.tsx·styles.css와 같은 모양이다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/model/models.dart';
import 'svg_path.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 아이콘: 디자인 시안과 같은 선 아이콘(24px, 선 굵기 1.8)
// ---------------------------------------------------------------------------

enum DsIcons {
  sleep('M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z'),
  meal('M3 11h18a9 9 0 0 1-18 0zM12 3v4M8 5v2M16 5v2'),
  work('M5 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18'),
  exercise('M6 7v10M18 7v10M3 10v4M21 10v4M6 12h12'),
  rest('M4 9h13v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM17 11h1.5a2.5 2.5 0 0 1 0 5H17M8 3v3M12 3v3'),
  home('M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z'),
  calendar('M5 5h14a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM4 10h16M8 3v4M16 3v4'),
  tasks('M10 6h10M10 12h10M10 18h10M4 6l1.5 1.5L8 5M4 12l1.5 1.5L8 11M4 18l1.5 1.5L8 17'),
  stats('M5 20V11M11 20V5M17 20v-7M3 20h18'),
  settings(
      'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z'),
  sun('M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4'),
  back('M15 5l-7 7 7 7'),
  forward('M9 5l7 7-7 7'),
  plus('M12 5v14M5 12h14'),
  minus('M5 12h14'),
  handle('M5 8h14M5 12h14M5 16h14'),
  close('M6 6l12 12M18 6L6 18'),
  check('M5 12l5 5 9-10'),
  bell('M6 10a6 6 0 1 1 12 0c0 5 2 6 2 6H4s2-1 2-6zM10 20a2 2 0 0 0 4 0'),
  moon('M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z'),
  chat('M4 5h16v11H8l-4 4z'),
  link('M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1'),
  trash('M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13'),
  share('M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7M12 3v12M7 8l5-5 5 5'),
  users('M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21v-1a6 6 0 0 1 6-6h2a6 6 0 0 1 6 6v1M16 3.5a4 4 0 0 1 0 7M22 21v-1a6 6 0 0 0-4-5.6'),
  refresh('M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7'),
  grip('M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01'),
  copy('M9 9h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V10a1 1 0 0 1 1-1zM5 15H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v1'),
  download('M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4M12 3v12M7 10l5 5 5-5'),
  upload('M4 15v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4M12 15V3M7 8l5-5 5 5');

  const DsIcons(this.d);
  final String d;

  static DsIcons of(Activity a) => switch (a) {
        Activity.sleep => DsIcons.sleep,
        Activity.meal => DsIcons.meal,
        Activity.work => DsIcons.work,
        Activity.exercise => DsIcons.exercise,
        Activity.rest => DsIcons.rest,
      };
}

final _pathCache = <String, Path>{};

class DsIcon extends StatelessWidget {
  const DsIcon(this.icon, {super.key, this.size = 22, this.stroke = 1.8, this.color});
  final DsIcons icon;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? context.ds.ink;
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: _IconPainter(icon.d, c, stroke))),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.d, this.color, this.stroke);
  final String d;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pathCache.putIfAbsent(d, () => parseSvgPath(d));
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.d != d || old.color != color || old.stroke != stroke;
}

/// 연속 기록 불꽃(채운 모양).
class Flame extends StatelessWidget {
  const Flame({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  static const _d = 'M12 1C13.5 5 18.5 8.5 18.5 14.5A6.5 6.5 0 0 1 5.5 14.5C5.5 11.2 7.3 9.1 8.6 7.6 8.8 9.4 9.7 10.6 11 11 10.5 7.5 11 4 12 1Z';

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _FillPainter(_d, color ?? context.ds.accent)));
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.d, this.color);
  final String d;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_pathCache.putIfAbsent(d, () => parseSvgPath(d)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FillPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// 눌림 모션·진동
// ---------------------------------------------------------------------------

/// 가벼운 진동(웹 haptic(ms)과 같은 자리에 쓴다).
void haptic([int strength = 10]) {
  if (strength >= 18) {
    HapticFeedback.mediumImpact();
  } else if (strength >= 10) {
    HapticFeedback.lightImpact();
  } else {
    HapticFeedback.selectionClick();
  }
}

/// 누르면 살짝 작아졌다가 스프링으로 돌아온다. 동작 줄이기 설정이면 움직이지 않는다.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.95, this.semanticLabel, this.selected});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;
  final bool? selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !reduce ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 80 : 220),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 카드·버튼·알약
// ---------------------------------------------------------------------------

class DsCard extends StatelessWidget {
  const DsCard({super.key, required this.children, this.tint = false, this.list = false, this.gap = 10, this.padding, this.crossAxisAlignment = CrossAxisAlignment.stretch});
  final List<Widget> children;
  final bool tint;

  /// 줄 목록 카드(위아래 여백이 작고 줄 사이 간격이 없다).
  final bool list;
  final double gap;
  final EdgeInsets? padding;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: padding ?? (list ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4) : DsGap.cardPad),
      decoration: BoxDecoration(
        color: tint ? c.tint : c.surface,
        border: c.outlined ? Border.all(color: c.stroke, width: c.strokeW) : Border.all(color: tint ? c.tintLine : c.line),
        borderRadius: BorderRadius.circular(c.outlined ? 22 : 20),
        boxShadow: c.popShadow ?? (c.dark || tint ? null : const [BoxShadow(color: Color(0x0D141A2A), blurRadius: 2, offset: Offset(0, 1))]),
      ),
      child: Column(crossAxisAlignment: crossAxisAlignment, mainAxisSize: MainAxisSize.min, children: _spaced(children, list ? 0 : gap)),
    );
  }
}

List<Widget> _spaced(List<Widget> xs, double gap) => [
      for (var i = 0; i < xs.length; i++) ...[if (i > 0 && gap > 0) SizedBox(height: gap), xs[i]],
    ];

/// 세로로 쌓기(간격 14).
class DsStack extends StatelessWidget {
  const DsStack({super.key, required this.children, this.gap = DsGap.stack});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: _spaced(children, gap));
}

enum BtnKind { normal, primary, ghost, danger }

class DsButton extends StatelessWidget {
  const DsButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = BtnKind.normal,
    this.small = false,
    this.block = false,
    this.icon,
    this.square = false,
    this.onTint = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final bool small;
  final bool block;
  final DsIcons? icon;
  final bool square;

  /// 옅은 앰버 카드 안의 버튼(테두리를 카드 선 색으로).
  final bool onTint;

  const DsButton.primary(this.label, {super.key, required this.onPressed, this.small = false, this.block = false, this.icon, this.square = false})
      : kind = BtnKind.primary,
        onTint = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final h = small ? 36.0 : 44.0;
    final (Color bg, Color border, Color fg, FontWeight w) = switch (kind) {
      BtnKind.primary => (c.accent, c.outlined ? c.stroke : c.accent, c.accentInk, FontWeight.w700),
      BtnKind.ghost => (Colors.transparent, Colors.transparent, c.accentStrong, FontWeight.w700),
      BtnKind.danger => (Colors.transparent, onTint ? c.tintLine : c.lineBtn, c.miss, FontWeight.w500),
      BtnKind.normal => (Colors.transparent, onTint ? c.tintLine : c.lineBtn, c.ink, FontWeight.w500),
    };
    final disabled = onPressed == null;
    final child = Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: kind == BtnKind.ghost ? 8 : (small ? 14 : 20)),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: c.outlined && kind != BtnKind.ghost ? c.strokeW : 1),
          borderRadius: BorderRadius.circular(square ? 14 : h / 2),
          // 외곽선 테마: 주요 단추만 스티커처럼 살짝 띄운다.
          boxShadow: kind == BtnKind.primary && c.outlined ? [BoxShadow(color: c.stroke, offset: const Offset(2, 3))] : null,
        ),
        child: Row(
          mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[DsIcon(icon!, size: small ? 16 : 18, color: fg), const SizedBox(width: 6)],
            // 너비가 정해지지 않은 Row 안에서도 쓰이므로, 꽉 채우는 단추일 때만 줄인다.
            if (block) Flexible(child: _label(fg, w)) else _label(fg, w),
          ],
        ),
      ),
    );
    return Pressable(onTap: disabled ? null : onPressed, semanticLabel: label, child: child);
  }

  Widget _label(Color fg, FontWeight w) =>
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 13 : 14, fontWeight: w, color: fg, height: 1.2));
}

class DsIconButton extends StatelessWidget {
  const DsIconButton(this.icon, {super.key, required this.onPressed, required this.label, this.size = 44, this.iconSize = 22, this.color});
  final DsIcons icon;
  final VoidCallback? onPressed;
  final String label;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onPressed,
        semanticLabel: label,
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: SizedBox.square(dimension: size, child: Center(child: DsIcon(icon, size: iconSize, color: color ?? context.ds.ink))),
        ),
      );
}

enum PillKind { accent, gray, miss }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.kind = PillKind.accent});
  final String text;
  final PillKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final (Color bg, Color fg, Border? border) = switch (kind) {
      PillKind.accent => (c.pillBg, c.accentStrong, null),
      PillKind.gray => (c.future, c.muted, null),
      PillKind.miss => (Colors.transparent, c.miss, Border.all(color: c.miss)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: border),
      child: Text(text, style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// 안내 띠(옅은 회색).
class DsBanner extends StatelessWidget {
  const DsBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: context.ds.future, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 13, height: 19 / 13, color: context.ds.muted)),
      );
}

// ---------------------------------------------------------------------------
// 글자
// ---------------------------------------------------------------------------

/// 회색 작은 설명 글자(.t-label).
class LabelText extends StatelessWidget {
  const LabelText(this.text, {super.key, this.color, this.maxLines, this.align});
  final String text;
  final Color? color;
  final int? maxLines;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, textAlign: align, style: DsText.label.copyWith(color: color ?? context.ds.muted));
}

class DsTitle extends StatelessWidget {
  const DsTitle(this.text, {super.key, this.style = DsText.h2, this.color});
  final String text;
  final TextStyle style;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(text, style: style.copyWith(color: color ?? context.ds.ink));
}

// ---------------------------------------------------------------------------
// 위 막대·세그먼트·칩·스위치
// ---------------------------------------------------------------------------

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.sub, this.onBack, this.right});
  final String title;
  final String? sub;
  final VoidCallback? onBack;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          if (onBack != null) Transform.translate(offset: const Offset(-12, 0), child: DsIconButton(DsIcons.back, onPressed: onBack, label: '뒤로')),
          Expanded(
            child: Transform.translate(
              offset: Offset(onBack != null ? -8 : 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(header: true, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.title.copyWith(color: context.ds.ink))),
                  if (sub != null) LabelText(sub!),
                ],
              ),
            ),
          ),
          if (right != null) right!,
        ],
      ),
    );
  }
}

class SegOption<T> {
  const SegOption(this.value, this.label);
  final T value;
  final String label;
}

/// 고른 칸 표시가 미끄러져 이동하는 세그먼트.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged, required this.label});
  final T value;
  final List<SegOption<T>> options;
  final ValueChanged<T> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final idx = options.indexWhere((o) => o.value == value).clamp(0, options.length - 1);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: label,
      container: true,
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.outlined ? c.surface2 : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: c.outlined ? Border.all(color: c.stroke, width: c.strokeW) : null,
        ),
        child: LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 2 * (options.length - 1)) / options.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: idx * (w + 2),
              top: 0,
              bottom: 0,
              width: w,
              child: DecoratedBox(decoration: BoxDecoration(color: c.outlined ? c.accent : c.lineStrong, borderRadius: BorderRadius.circular(11))),
            ),
            Row(children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Semantics(
                    inMutuallyExclusiveGroup: true,
                    checked: i == idx,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i != idx) haptic(6);
                        onChanged(options[i].value);
                      },
                      child: Center(
                        child: Text(options[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500, color: i == idx ? c.accentStrong : c.muted)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ]);
        }),
      ),
    );
  }
}

/// 고를 수 있는 알약 칩.
class DsChip extends StatelessWidget {
  const DsChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Pressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: label,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? c.pillBg : Colors.transparent,
          border: Border.all(color: selected ? c.accent : c.lineStrong, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        // Wrap 안에서 칩이 한 줄 너비로 늘어나지 않도록 글자 너비에 맞춘다.
        child: Center(widthFactor: 1, child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: c.ink))),
      ),
    );
  }
}

class ChipWrap extends StatelessWidget {
  const ChipWrap({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

/// 크고 눈에 띄는 토글 스위치. 켜지면 앰버로 채워진다.
class DsSwitch extends StatelessWidget {
  const DsSwitch({super.key, required this.value, required this.onChanged, required this.label, this.sub, this.onText = '켜짐', this.offText = '꺼짐'});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? sub;
  final String onText;
  final String offText;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final d = reduce ? Duration.zero : const Duration(milliseconds: 280);
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          haptic(8);
          onChanged(!value);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w700, color: c.ink)),
                  if (sub != null) LabelText(sub!),
                ]),
              ),
              const SizedBox(width: 12),
              Text(value ? onText : offText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: value ? c.accentStrong : c.muted)),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: d,
                width: 60,
                height: 34,
                decoration: BoxDecoration(color: value ? c.accent : c.lineBtn, borderRadius: BorderRadius.circular(17)),
                child: AnimatedAlign(
                  duration: d,
                  curve: Curves.easeOutBack,
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 아래에서 올라오는 창
// ---------------------------------------------------------------------------

/// 제목과 닫기 단추가 있는 아래 창. 키보드가 올라오면 위로 밀린다.
Future<T?> showDsSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.ds.bg,
    barrierColor: const Color(0x59000000),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: ctx.ds.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: DsText.sub.copyWith(color: ctx.ds.ink)))),
              DsIconButton(DsIcons.close, onPressed: () => Navigator.of(ctx).pop(), label: '닫기'),
            ]),
            const SizedBox(height: 6),
            Builder(builder: builder),
          ]),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 입력
// ---------------------------------------------------------------------------

InputDecoration dsInput(BuildContext context, {String? hint}) {
  final c = context.ds;
  OutlineInputBorder b(Color color, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: w));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.faint),
    filled: true,
    fillColor: c.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: b(c.lineStrong),
    enabledBorder: b(c.lineStrong),
    focusedBorder: b(c.accent, 2),
  );
}

/// 이름표가 있는 입력 칸.
class DsField extends StatelessWidget {
  const DsField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.ds.muted)),
        const SizedBox(height: 6),
        child,
      ]);
}

/// 'HH:MM' ↔ 자정 기준 분
String toHm(int minutes) => formatClock(minutes);

/// 시각 고르기(자정 기준 분).
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final m = ((value % 1440) + 1440) % 1440;
    return DsField(
      label: label,
      child: Pressable(
        scale: 0.98,
        semanticLabel: '$label ${toHm(value)}',
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
            initialEntryMode: TimePickerEntryMode.inputOnly,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
          );
          if (picked != null) onChanged(picked.hour * 60 + picked.minute);
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
          child: Text(toHm(value), style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num)),
        ),
      ),
    );
  }
}

/// 숫자 입력(− / + 단추). 범위를 넘지 않는다.
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.label, required this.value, required this.onChanged, this.min = 0, this.max = 600, this.step = 5, this.unit = '분'});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    void set(int v) => onChanged(v.clamp(min, max));
    return DsField(
      label: '$label ($unit)',
      child: Container(
        height: 44,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          DsIconButton(DsIcons.minus, onPressed: value > min ? () => set(value - step) : null, label: '$step $unit 줄이기', size: 40, iconSize: 18),
          Expanded(child: Center(child: Text('$value', style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num)))),
          DsIconButton(DsIcons.plus, onPressed: value < max ? () => set(value + step) : null, label: '$step $unit 늘리기', size: 40, iconSize: 18),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 일정 줄
// ---------------------------------------------------------------------------

String kindLabel(ScheduleBlock b) => switch (b.kind) {
      BlockKind.task => '할 일',
      BlockKind.fixed => '캘린더',
      BlockKind.buffer => '여유',
      _ => b.adjusted ? '조정됨' : '습관',
    };

String pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';

/// 시각 · 색 막대 · 내용 · 오른쪽 꼬리표로 된 한 줄.
class LineRow extends StatelessWidget {
  const LineRow({super.key, required this.time, required this.color, required this.child, this.tag, this.tagColor, this.now = false, this.last = false, this.onTap});
  final String time;
  final Color color;
  final Widget child;
  final String? tag;
  final Color? tagColor;
  final bool now;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      // 지금 줄: 옅은 앰버 바탕(음수 여백은 쓸 수 없어 안쪽 여백만 준다).
      padding: now ? const EdgeInsets.symmetric(horizontal: 8) : null,
      decoration: BoxDecoration(
        color: now ? c.pillBg : null,
        borderRadius: now ? BorderRadius.circular(12) : null,
        border: now || last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        SizedBox(width: 44, child: Text(time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted, fontFeatures: DsText.num))),
        const SizedBox(width: 12),
        Container(width: 4, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child)),
        if (tag != null) ...[
          const SizedBox(width: 12),
          Text(tag!, style: TextStyle(fontSize: 12, color: tagColor ?? c.muted, fontWeight: tagColor != null ? FontWeight.w700 : FontWeight.w400)),
        ],
      ]),
    );
    return onTap == null ? row : Pressable(scale: 0.98, onTap: onTap, child: row);
  }
}

/// 진행 막대(달성률).
class Meter extends StatelessWidget {
  const Meter({super.key, required this.value, this.color});
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: context.ds.future)),
            FractionallySizedBox(widthFactor: value.clamp(0, 1), child: Container(decoration: BoxDecoration(color: color ?? context.ds.accent, borderRadius: BorderRadius.circular(4)))),
          ]),
        ),
      );
}
