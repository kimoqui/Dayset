// SVG path 문자열(d)을 Flutter Path로 바꾼다. 디자인 시안의 선 아이콘(24px 칸)을 그대로 그리려고 쓴다.
// 지원: M L H V C S Q T A Z (대·소문자 모두).

import 'dart:ui';

final _token = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _token.allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  var cx = 0.0, cy = 0.0; // 현재 점
  var sx = 0.0, sy = 0.0; // 하위 경로 시작점
  var lcx = 0.0, lcy = 0.0; // 마지막 제어점(S·T용)
  String cmd = 'M';
  String prev = '';

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  bool flag() {
    // 호의 플래그는 '01' 처럼 붙어 있을 수 있다.
    final t = tokens[i];
    if (t.length > 1 && (t.startsWith('0') || t.startsWith('1')) && !t.contains('.')) {
      tokens[i] = t.substring(1);
      return t[0] == '1';
    }
    i++;
    return t == '1' || t == '1.0';
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == 'Z' || cmd == 'z') {
      break; // 닫은 뒤 숫자가 이어지는 잘못된 경로
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        cx = ox + n();
        cy = oy + n();
        sx = cx;
        sy = cy;
        path.moveTo(cx, cy);
      case 'L':
        cx = ox + n();
        cy = oy + n();
        path.lineTo(cx, cy);
      case 'H':
        cx = ox + n();
        path.lineTo(cx, cy);
      case 'V':
        cy = (rel ? cy : 0.0) + n();
        path.lineTo(cx, cy);
      case 'C':
        final x1 = ox + n(), y1 = oy + n(), x2 = ox + n(), y2 = oy + n();
        cx = ox + n();
        cy = oy + n();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        lcx = x2;
        lcy = y2;
      case 'S':
        final reflect = 'CcSs'.contains(prev);
        final x1 = reflect ? 2 * cx - lcx : cx, y1 = reflect ? 2 * cy - lcy : cy;
        final x2 = ox + n(), y2 = oy + n();
        cx = ox + n();
        cy = oy + n();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        lcx = x2;
        lcy = y2;
      case 'Q':
        final x1 = ox + n(), y1 = oy + n();
        cx = ox + n();
        cy = oy + n();
        path.quadraticBezierTo(x1, y1, cx, cy);
        lcx = x1;
        lcy = y1;
      case 'T':
        final reflect = 'QqTt'.contains(prev);
        final x1 = reflect ? 2 * cx - lcx : cx, y1 = reflect ? 2 * cy - lcy : cy;
        cx = ox + n();
        cy = oy + n();
        path.quadraticBezierTo(x1, y1, cx, cy);
        lcx = x1;
        lcy = y1;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = flag(), sweep = flag();
        cx = ox + n();
        cy = oy + n();
        path.arcToPoint(Offset(cx, cy), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
    }
    prev = cmd;
  }
  return path;
}
