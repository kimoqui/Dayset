// 디자인 B '나이트 링': 하루 24시간을 한 바퀴로 보여 준다. 웹 버전 src/ui/DayRing.tsx와 같은 모양.
// 바깥 굵은 링 = 자동으로 짠 일정, 안쪽 가는 링 = 실제 기록, 점 = 지금.
// 링을 누르면 그 시각에 무엇을, 몇 시부터 몇 시까지 했는지 가운데에 보여 준다(6초 뒤 돌아간다).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/model/models.dart';
import 'kit.dart';
import 'theme.dart';

class RingSegment {
  const RingSegment({required this.start, required this.end, required this.color, required this.title, required this.from, required this.to});

  /// 자정 기준 분(0~1440). 링에 그릴 범위(오늘로 잘린 범위).
  final int start;
  final int end;
  final Color color;

  /// 눌렀을 때 보여 줄 이름과 실제 시작·끝(자정을 넘는 수면도 그대로).
  final String title;
  final DateTime from;
  final DateTime to;
}

/// 그 날 0시 기준으로 자른 링 조각. 하루 밖이면 null.
RingSegment? clipSegment(DateTime day, DateTime start, DateTime end, Color color, String title, {DateTime? from, DateTime? to}) {
  final st = math.max(0, diffMin(start, day));
  final en = math.min(1440, diffMin(end, day));
  return en > st ? RingSegment(start: st, end: en, color: color, title: title, from: from ?? start, to: to ?? end) : null;
}

class _Selection {
  const _Selection(this.minute, this.plan, this.record);
  final int minute;
  final RingSegment? plan;
  final RingSegment? record;
}

/// 짧은 구간이 긴 구간 위에 그려지므로, 겹치면 짧은 것을 고른다.
RingSegment? _at(List<RingSegment> segs, int m) {
  final hits = segs.where((s) => s.start <= m && m < s.end).toList()..sort((a, b) => (a.end - a.start) - (b.end - b.start));
  return hits.firstOrNull;
}

class DayRing extends StatefulWidget {
  const DayRing({super.key, required this.plan, required this.records, required this.nowMinutes, required this.label, this.recordsOnly = false, required this.child, this.size = 248});
  final List<RingSegment> plan;
  final List<RingSegment> records;
  final int nowMinutes;
  final String label;

  /// 계획 없이 기록만 보여 줄 때(관찰 1일차).
  final bool recordsOnly;

  /// 가운데 내용(선택하지 않았을 때).
  final Widget child;
  final double size;

  @override
  State<DayRing> createState() => _DayRingState();
}

class _DayRingState extends State<DayRing> {
  _Selection? _sel;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(Offset local) {
    // 240 칸 좌표로 바꾼다.
    final k = 240 / widget.size;
    final x = local.dx * k - 120;
    final y = local.dy * k - 120;
    final dist = math.sqrt(x * x + y * y);
    _timer?.cancel();
    if (dist < 64 || dist > 118) {
      setState(() => _sel = null); // 가운데나 바깥을 누르면 닫는다
      return;
    }
    final a = (math.atan2(x, -y) + 2 * math.pi) % (2 * math.pi);
    final minute = (a / (2 * math.pi) * 1440).floor();
    setState(() => _sel = _Selection(minute, _at(widget.plan, minute), _at(widget.records, minute)));
    haptic(6);
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _sel = null);
    });
  }

  String _span(RingSegment s) => '${formatHm(s.from)}–${formatHm(s.to)} · ${formatDuration(math.max(1, diffMin(s.to, s.from)))}';

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final sel = _sel;
    final main = sel == null ? null : (sel.plan ?? sel.record);
    return Semantics(
      label: '${widget.label}. 링을 누르면 그 시각의 일정과 기록을 보여 줘요',
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(alignment: Alignment.center, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _pick(d.localPosition),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _RingPainter(
                plan: widget.plan,
                records: widget.records,
                nowMinutes: widget.nowMinutes,
                selMinute: sel?.minute,
                selPlan: sel?.plan,
                selRecord: sel?.record,
                colors: c,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: sel != null,
            child: SizedBox(
              width: widget.size * 0.52,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: sel == null
                    ? KeyedSubtree(key: const ValueKey('child'), child: widget.child)
                    : Column(key: ValueKey(sel.minute), mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                          child: Text(formatClock((sel.minute / 5).round() * 5),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentInk, fontFeatures: DsText.num)),
                        ),
                        const SizedBox(height: 6),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (main != null) ...[
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: main.color, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(main?.title ?? '비어 있는 시간',
                                maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: DsText.h2.copyWith(color: c.ink)),
                          ),
                        ]),
                        if (sel.plan != null)
                          Text('${widget.recordsOnly ? '기록 ' : ''}${_span(sel.plan!)}',
                              textAlign: TextAlign.center, style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num)),
                        if (sel.record != null)
                          Text('실제 ${sel.record!.title} ${_span(sel.record!)}',
                              textAlign: TextAlign.center, style: DsText.label.copyWith(color: c.accentStrong, fontFeatures: DsText.num))
                        else if (!widget.recordsOnly && sel.plan != null && sel.minute < widget.nowMinutes)
                          Text('실제 기록 없음', style: DsText.label.copyWith(color: c.miss)),
                      ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.plan,
    required this.records,
    required this.nowMinutes,
    required this.selMinute,
    required this.selPlan,
    required this.selRecord,
    required this.colors,
  });
  final List<RingSegment> plan;
  final List<RingSegment> records;
  final int nowMinutes;
  final int? selMinute;
  final RingSegment? selPlan;
  final RingSegment? selRecord;
  final DsColors colors;

  static const _r = 100.0;

  Offset _point(int minute, double r) {
    final a = minute / 1440 * 2 * math.pi;
    return Offset(120 + r * math.sin(a), 120 - r * math.cos(a));
  }

  void _arc(Canvas canvas, RingSegment s, double r, double width, double opacity) {
    final sweep = (s.end - s.start) / 1440 * 2 * math.pi;
    if (sweep * r <= 0.2) return;
    final startAngle = -math.pi / 2 + s.start / 1440 * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(120, 120), radius: r),
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = s.color.withValues(alpha: s.color.a * opacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 240, size.height / 240);
    final selected = selMinute != null;
    canvas.drawCircle(const Offset(120, 120), _r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = colors.track);
    for (final s in plan) {
      _arc(canvas, s, _r, identical(s, selPlan) ? 22 : 16, selected && !identical(s, selPlan) ? 0.3 : 1);
    }
    for (final s in records) {
      _arc(canvas, s, 84, identical(s, selRecord) ? 7 : 4, selected && !identical(s, selRecord) ? 0.3 : 0.9);
    }
    // 0·6·12·18시
    for (final (label, x, y) in const [('0시', 120.0, 46.0), ('6시', 198.0, 124.0), ('12시', 120.0, 202.0), ('18시', 42.0, 124.0)]) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontFamily: colors.font, fontSize: 11, color: colors.faint)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height + 2));
    }
    // 지금
    final dot = _point(nowMinutes, _r);
    canvas.drawCircle(dot, 9, Paint()..color = colors.accent.withValues(alpha: selected ? 0.5 : 1));
    canvas.drawCircle(dot, 9, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = colors.ringBg);
    // 고른 시각
    final m = selMinute;
    if (m != null) {
      final p = _point(m, _r);
      final line = Paint()
        ..color = colors.ink.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      // 점선(2 칠하고 3 비우기)
      final d = p - const Offset(120, 120);
      final len = d.distance;
      final u = d / len;
      for (var t = 0.0; t < len; t += 5) {
        canvas.drawLine(const Offset(120, 120) + u * t, const Offset(120, 120) + u * math.min(t + 2, len), line);
      }
      canvas.drawCircle(p, 7, Paint()..color = colors.ink);
      canvas.drawCircle(p, 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = colors.ringBg);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.plan != plan || old.records != records || old.nowMinutes != nowMinutes || old.selMinute != selMinute || old.colors != colors;
}
