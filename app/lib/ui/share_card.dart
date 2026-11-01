// 공유: 연속 기록 카드 이미지를 만들어 휴대폰의 공유 창(카카오톡·인스타그램 등)으로 보낸다.
// 웹 버전 src/ui/share.ts의 캔버스 그림과 같은 모양이다.
// 카카오 SDK·인스타그램 스토리 바로 보내기는 다음 단계에서 붙인다. 지금은 두 단추 모두 공유 창을 연다.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../app/streak.dart';
import '../platform/share.dart';
import 'svg_path.dart';

const flamePath = 'M12 1C13.5 5 18.5 8.5 18.5 14.5A6.5 6.5 0 0 1 5.5 14.5C5.5 11.2 7.3 9.1 8.6 7.6 8.8 9.4 9.7 10.6 11 11 10.5 7.5 11 4 12 1Z';

class CardData {
  const CardData({required this.name, required this.streak, required this.best, required this.week, required this.weekSetDays, required this.monthSetDays});
  final String name;
  final int streak;
  final int best;
  final List<WeekMark> week;
  final int weekSetDays;
  final int monthSetDays;
}

enum CardKind { story, square }

/// 카드 이미지의 고정 색(앱 테마와 관계없이 나이트 링 색으로 그린다).
class _C {
  static const bg1 = Color(0xFF0D1220);
  static const bg2 = Color(0xFF1A2340);
  static const ink = Color(0xFFEEF1F7);
  static const muted = Color(0xFF9AA4BB);
  static const line = Color(0xFF263049);
  static const amber = Color(0xFFF4B04F);
  static const amberInk = Color(0xFF1A1300);
  static const future = Color(0xFF1E2638);
}

const _week = ['월', '화', '수', '목', '금', '토', '일'];

/// 가운데 정렬로 글자를 그린다. y는 글자 기준선(웹 textBaseline 'alphabetic').
void _text(Canvas canvas, String text, double cx, double baseline, double size, FontWeight weight, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontFamily: 'Pretendard', fontSize: size, fontWeight: weight, color: color, height: 1)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  final b = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  tp.paint(canvas, Offset(cx - tp.width / 2, baseline - b));
}

void _flame(Canvas canvas, double cx, double cy, double size, Color color) {
  canvas.save();
  canvas.translate(cx - size / 2, cy - size / 2);
  canvas.scale(size / 24, size / 24);
  canvas.drawPath(parseSvgPath(flamePath), Paint()..color = color);
  canvas.restore();
}

/// 공유 카드 그리기. story = 1080×1920(인스타 스토리), square = 1080×1080(카카오톡). PNG 바이트를 돌려준다.
Future<Uint8List> renderCard(CardKind kind, CardData d) async {
  final story = kind == CardKind.story;
  const w = 1080.0;
  final h = story ? 1920.0 : 1080.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), const [_C.bg1, _C.bg2]),
  );

  // 뒤쪽 큰 링(나이트 링 모티프)
  final ringY = story ? 760.0 : 420.0;
  final ringR = story ? 330.0 : 250.0;
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 36
    ..color = _C.line;
  canvas.drawCircle(Offset(w / 2, ringY), ringR, ring);
  final frac = math.min(1.0, d.weekSetDays / 7);
  if (frac > 0) {
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w / 2, ringY), radius: ringR),
      -math.pi / 2,
      frac * math.pi * 2,
      false,
      ring
        ..color = _C.amber
        ..strokeCap = StrokeCap.round,
    );
  }

  final top = story ? 200.0 : 110.0;
  _text(canvas, 'DaySet', w / 2, top, story ? 56 : 46, FontWeight.w700, _C.amber);
  _flame(canvas, w / 2, ringY - (story ? 140 : 110), story ? 150 : 110, _C.amber);
  _text(canvas, '${d.streak}', w / 2, ringY + (story ? 110 : 80), story ? 220 : 170, FontWeight.w700, _C.ink);
  _text(canvas, '일 연속 셋 데이', w / 2, ringY + (story ? 200 : 150), story ? 56 : 44, FontWeight.w700, _C.ink);

  // 이번 주 7칸
  final rowY = story ? 1240.0 : 760.0;
  final cell = story ? 104.0 : 88.0;
  final gap = story ? 22.0 : 18.0;
  final startX = (w - (cell * 7 + gap * 6)) / 2;
  for (var i = 0; i < d.week.length && i < 7; i++) {
    final day = d.week[i];
    final x = startX + i * (cell + gap);
    _text(canvas, _week[i], x + cell / 2, rowY - 22, story ? 30 : 26, FontWeight.w500, _C.muted);
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, rowY, cell, cell * 1.25), const Radius.circular(22));
    if (day.mark == DayMark.set) {
      canvas.drawRRect(r, Paint()..color = _C.amber);
      _flame(canvas, x + cell / 2, rowY + cell * 0.62, cell * 0.5, _C.amberInk);
    } else {
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = day.mark == DayMark.future ? _C.future : (day.mark == DayMark.today ? _C.amber : _C.line),
      );
      if (day.mark == DayMark.rest) canvas.drawCircle(Offset(x + cell / 2, rowY + cell * 0.62), 8, Paint()..color = _C.muted);
    }
  }

  final infoY = rowY + cell * 1.25 + (story ? 110 : 80);
  _text(canvas, '이번 주 ${d.weekSetDays}일 · 이번 달 ${d.monthSetDays}일 · 최고 ${d.best}일', w / 2, infoY, story ? 44 : 38, FontWeight.w700, _C.ink);
  _text(canvas, '셋 데이 = 기상 알람 ±30분 + 습관 70%를 지킨 날', w / 2, infoY + (story ? 70 : 56), story ? 34 : 30, FontWeight.w500, _C.muted);
  if (story) {
    _text(canvas, '${d.name.isEmpty ? '나' : d.name}의 생활습관', w / 2, h - 200, 40, FontWeight.w700, _C.ink);
    _text(canvas, '자동으로 짜주는 일정으로 편하게 생활습관 잡기', w / 2, h - 140, 32, FontWeight.w500, _C.muted);
  }

  final image = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('이미지를 만들지 못했어요');
  return bytes.buffer.asUint8List();
}

String shareMessage(CardData d, [String? code]) {
  final lines = [
    'DaySet에서 ${d.streak}일 연속 셋 데이를 지키고 있어요.',
    '이번 주 ${d.weekSetDays}일 · 최고 기록 ${d.best}일',
  ];
  if (code != null) lines.addAll(['', '같이 겨뤄요! DaySet 소셜 탭 → 친구 → 친구 코드 넣기', code]);
  return lines.join('\n');
}

/// 카드 이미지 + 문구 공유. 이미지를 만들거나 공유 창을 열지 못하면 문구만 복사한다.
Future<ShareOutcome> shareCard(CardKind kind, CardData d, String text) async {
  final Uint8List bytes;
  try {
    bytes = await renderCard(kind, d);
  } catch (_) {
    return await copyText(text) ? ShareOutcome.copied : ShareOutcome.failed;
  }
  final r = await shareFile(kind == CardKind.story ? 'dayset-story.png' : 'dayset-streak.png', bytes, mimeType: 'image/png', text: text);
  if (r == ShareOutcome.failed) return await copyText(text) ? ShareOutcome.copied : ShareOutcome.failed;
  return r;
}

/// 공유 결과 알림 문구(웹 RESULT_TEXT와 같다).
String shareResultText(ShareOutcome r) => switch (r) {
      ShareOutcome.shared => '공유했어요',
      ShareOutcome.copied => '복사했어요. 카카오톡에 붙여 넣어 보내 주세요',
      ShareOutcome.cancelled => '공유를 취소했어요',
      ShareOutcome.failed => '공유하지 못했어요',
    };
