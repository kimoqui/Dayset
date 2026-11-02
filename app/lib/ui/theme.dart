// 디자인 B '나이트 링' 토큰. 웹 버전 src/ui/styles.css의 변수와 같은 값이다.
// 색·글자 크기는 여기 토큰만 쓴다(화면에서 색을 직접 적지 않는다). 기본은 나이트, 설정에서 밝게·파스텔.
// 파스텔 다이어리: 크림 바탕, 갈색 외곽선과 밀린 그림자(스티커 느낌), 둥근 글꼴(DaySetPastel = 고운돋움 + 굵게는 주아).

import 'package:flutter/material.dart';

import '../core/model/models.dart';

@immutable
class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.faint,
    required this.line,
    required this.lineStrong,
    required this.lineBtn,
    required this.accent,
    required this.accentStrong,
    required this.accentInk,
    required this.tint,
    required this.tintLine,
    required this.pillBg,
    required this.miss,
    required this.sleep,
    required this.meal,
    required this.work,
    required this.exercise,
    required this.rest,
    required this.alarm,
    required this.task,
    required this.calendar,
    required this.future,
    required this.track,
    required this.dot,
    required this.nav,
    required this.ringBg,
    required this.dark,
    this.font = 'Pretendard',
    this.stroke = const Color(0x00000000),
    this.strokeW = 0,
    this.pop = Offset.zero,
  });

  final Color bg, surface, surface2, ink, inkSoft, muted, faint, line, lineStrong, lineBtn;
  final Color accent, accentStrong, accentInk, tint, tintLine, pillBg, miss;
  final Color sleep, meal, work, exercise, rest, alarm, task, calendar, future, track, dot, nav, ringBg;
  final bool dark;

  /// 글꼴 이름(pubspec의 family).
  final String font;

  /// 카드·주요 단추 외곽선(strokeW가 0이면 쓰지 않는다)과 그 아래 밀린 그림자.
  final Color stroke;
  final double strokeW;
  final Offset pop;

  bool get outlined => strokeW > 0;

  /// 외곽선 테마의 밀린 그림자(없으면 null).
  List<BoxShadow>? get popShadow => outlined && pop != Offset.zero ? [BoxShadow(color: stroke, offset: pop)] : null;

  static const night = DsColors(
    bg: Color(0xFF0D1220),
    surface: Color(0xFF161D2E),
    surface2: Color(0xFF1B2336),
    ink: Color(0xFFEEF1F7),
    inkSoft: Color(0xFFDDE2EE),
    muted: Color(0xFF9AA4BB),
    faint: Color(0xFF7E88A0),
    line: Color(0xFF1E2638),
    lineStrong: Color(0xFF263049),
    lineBtn: Color(0xFF3A4560),
    accent: Color(0xFFF4B04F),
    accentStrong: Color(0xFFF4B04F),
    accentInk: Color(0xFF1A1300),
    tint: Color(0xFF1B2336),
    tintLine: Color(0xFF3A4560),
    pillBg: Color(0x24F4B04F),
    miss: Color(0xFFF07C6B),
    sleep: Color(0xFF5C6BC0),
    meal: Color(0xFFF4B04F),
    work: Color(0xFF3FA796),
    exercise: Color(0xFFF2EEE6),
    rest: Color(0xFFB7A6F5),
    alarm: Color(0xFF8C9CE6),
    task: Color(0xFF7FD1C1),
    calendar: Color(0xFF7E88A0),
    future: Color(0xFF1E2638),
    track: Color(0xFF1E2638),
    dot: Color(0xFF7E88A0),
    nav: Color(0xFF111829),
    ringBg: Color(0xFF0D1220),
    dark: true,
  );

  static const light = DsColors(
    bg: Color(0xFFF3F4F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F8FB),
    ink: Color(0xFF141A2A),
    inkSoft: Color(0xFF2A3247),
    muted: Color(0xFF5E6782),
    faint: Color(0xFF7E88A0),
    line: Color(0xFFE6E9F0),
    lineStrong: Color(0xFFD5DAE5),
    lineBtn: Color(0xFFC9CFDC),
    accent: Color(0xFFF4B04F),
    accentStrong: Color(0xFFA8690C),
    accentInk: Color(0xFF1A1300),
    tint: Color(0xFFFFF6E6),
    tintLine: Color(0xFFF0D6A8),
    pillBg: Color(0xFFFFF1D9),
    miss: Color(0xFFC24A36),
    sleep: Color(0xFF5C6BC0),
    meal: Color(0xFFE39A2D),
    work: Color(0xFF2F9483),
    exercise: Color(0xFF9A8F7A),
    rest: Color(0xFF8E7BD6),
    alarm: Color(0xFF5C6BC0),
    task: Color(0xFF2E8C7D),
    calendar: Color(0xFF7E88A0),
    future: Color(0xFFECEFF4),
    track: Color(0xFFE6E9F0),
    dot: Color(0xFF9AA4BB),
    nav: Color(0xFFFFFFFF),
    ringBg: Color(0xFFF3F4F8),
    dark: false,
  );

  static const pastel = DsColors(
    bg: Color(0xFFFFF7EC),
    surface: Color(0xFFFFFDF8),
    surface2: Color(0xFFFFF1DC),
    ink: Color(0xFF3B2F2A),
    inkSoft: Color(0xFF4D3F38),
    muted: Color(0xFF76665C),
    faint: Color(0xFF8E7E72),
    line: Color(0xFFF0DFC8),
    lineStrong: Color(0xFFE4CFB2),
    lineBtn: Color(0xFF3B2F2A),
    accent: Color(0xFFFFB36B),
    accentStrong: Color(0xFFB4621A),
    accentInk: Color(0xFF3B2F2A),
    tint: Color(0xFFFFE3C2),
    tintLine: Color(0xFF3B2F2A),
    pillBg: Color(0xFFFFE3C2),
    miss: Color(0xFFC9503C),
    sleep: Color(0xFF9C95EA),
    meal: Color(0xFFFFB36B),
    work: Color(0xFF6CC4A4),
    exercise: Color(0xFFFF9DB4),
    rest: Color(0xFF8CBCF0),
    alarm: Color(0xFF9C95EA),
    task: Color(0xFF52B08E),
    calendar: Color(0xFFB8A898),
    future: Color(0xFFF6EAD8),
    track: Color(0xFFF3E4CF),
    dot: Color(0xFFC8B6A2),
    nav: Color(0xFFFFFDF8),
    ringBg: Color(0xFFFFF7EC),
    dark: false,
    font: 'DaySetPastel',
    stroke: Color(0xFF3B2F2A),
    strokeW: 2,
    pop: Offset(3, 4),
  );

  Color activity(Activity? a) => switch (a) {
        Activity.sleep => sleep,
        Activity.meal => meal,
        Activity.work => work,
        Activity.exercise => exercise,
        Activity.rest => rest,
        null => calendar,
      };

  /// 일정 조각 색: 할 일 = task, 캘린더 = calendar, 습관 = 활동 색.
  Color block(ScheduleBlock b) => switch (b.kind) {
        BlockKind.task => task,
        BlockKind.fixed => calendar,
        _ => activity(b.activity),
      };

  @override
  DsColors copyWith() => this;

  @override
  DsColors lerp(ThemeExtension<DsColors>? other, double t) => t < 0.5 || other is! DsColors ? this : other;
}

/// 글자 크기(웹 .t-* 클래스와 같다).
class DsText {
  DsText._();
  static const display = TextStyle(fontSize: 30, height: 38 / 30, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static const hero = TextStyle(fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w700, letterSpacing: -0.5);
  static const title = TextStyle(fontSize: 22, height: 30 / 22, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static const sub = TextStyle(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontSize: 14, height: 21 / 14);
  static const base = TextStyle(fontSize: 15, height: 22 / 15);
  static const label = TextStyle(fontSize: 12, height: 17 / 12, fontWeight: FontWeight.w500);
  static const small = TextStyle(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500);
  static const num = [FontFeature.tabularFigures()];
}

/// 간격
class DsGap {
  DsGap._();
  static const screen = EdgeInsets.fromLTRB(20, 12, 20, 24);
  static const stack = 14.0;
  static const cardPad = EdgeInsets.symmetric(horizontal: 18, vertical: 16);
}

ThemeData buildTheme(DsColors c) {
  final base = c.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final text = base.textTheme.apply(fontFamily: c.font, bodyColor: c.ink, displayColor: c.ink);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: c.accent,
      onPrimary: c.accentInk,
      secondary: c.accent,
      surface: c.surface,
      onSurface: c.ink,
      error: c.miss,
      outline: c.lineStrong,
    ),
    textTheme: text.copyWith(bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 22 / 15, letterSpacing: -0.15)),
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.accent, selectionColor: c.pillBg, selectionHandleColor: c.accent),
    timePickerTheme: TimePickerThemeData(backgroundColor: c.surface, dialHandColor: c.accent, hourMinuteTextColor: c.ink),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.bg, modalBackgroundColor: c.bg, showDragHandle: false),
    extensions: [c],
  );
}

extension DsTheme on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>() ?? DsColors.night;
}
