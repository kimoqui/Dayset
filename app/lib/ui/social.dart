// 연속 기록 카드, 공유 단추, 친구 순위, 기념일 축하. 웹 버전 src/ui/Social.tsx와 같은 모양.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/social.dart';
import '../app/state.dart';
import '../app/store.dart';
import '../app/streak.dart';
import '../core/engine/coaching.dart';
import '../core/model/models.dart';
import '../platform/share.dart';
import 'kit.dart';
import 'scope.dart';
import 'share_card.dart';
import 'theme.dart';

CardData cardData(AppState s, StreakInfo info) => CardData(
      name: s.profile.name,
      streak: info.current,
      best: info.best,
      week: info.week,
      weekSetDays: info.weekSetDays,
      monthSetDays: info.monthSetDays,
    );

// ---------------------------------------------------------------------------
// 공유 단추(카카오톡·인스타그램 색). 브랜드 색이라 토큰 대신 고정 색을 쓴다(웹 .share-kakao·.share-insta).
// ---------------------------------------------------------------------------

const _kakaoBg = Color(0xFFFEE500);
const _kakaoInk = Color(0xFF191919);
const _instaGradient = LinearGradient(
  begin: Alignment(-0.9, -0.5),
  end: Alignment(0.9, 0.5),
  colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
  stops: [0, 0.55, 1],
);

class _BrandButton extends StatelessWidget {
  const _BrandButton({required this.label, required this.icon, required this.onTap, this.color, this.gradient, this.fg, this.outlined = false});
  final String label;
  final DsIcons icon;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final Color? fg;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final ink = fg ?? c.ink;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
            border: outlined ? Border.all(color: c.lineBtn) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            DsIcon(icon, size: 18, color: ink),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink))),
          ]),
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: left), const SizedBox(width: 8), Expanded(child: right)]);
}

/// 카카오톡·인스타그램 공유 단추. 둘 다 휴대폰의 공유 창을 연다(카카오톡은 친구 코드도 함께 보낸다).
class ShareButtons extends StatefulWidget {
  const ShareButtons({super.key, required this.info});
  final StreakInfo info;

  @override
  State<ShareButtons> createState() => _ShareButtonsState();
}

class _ShareButtonsState extends State<ShareButtons> {
  bool _busy = false;

  Future<void> _run(bool kakao) async {
    if (_busy) return;
    setState(() => _busy = true);
    haptic(8);
    final store = context.store;
    final s = store.state;
    final d = cardData(s, widget.info);
    final code = makeFriendCode(id: s.profile.id, name: s.profile.name, info: widget.info, now: store.now());
    final r = await shareCard(kakao ? CardKind.square : CardKind.story, d, shareMessage(d, kakao ? code : null));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != ShareOutcome.cancelled) {
      context.toast(shareResultText(r));
      store.track('share', kakao ? 'kakao' : 'insta');
    }
  }

  @override
  Widget build(BuildContext context) => _ShareRow(
        left: _BrandButton(label: '카카오톡 공유', icon: DsIcons.chat, color: _kakaoBg, fg: _kakaoInk, onTap: _busy ? null : () => _run(true)),
        right: _BrandButton(label: '인스타 스토리', icon: DsIcons.share, gradient: _instaGradient, fg: const Color(0xFFFFFFFF), onTap: _busy ? null : () => _run(false)),
      );
}

// ---------------------------------------------------------------------------
// 연속 기록 카드
// ---------------------------------------------------------------------------

const _markLabel = {
  DayMark.set: '셋 데이',
  DayMark.rest: '쉬는 날',
  DayMark.miss: '놓친 날',
  DayMark.today: '오늘',
  DayMark.none: '기록 없음',
  DayMark.future: '예정',
};

/// 천천히 숨 쉬듯 커졌다 작아지는 불꽃 바탕(동작 줄이기 설정이면 멈춘다).
class _Flicker extends StatefulWidget {
  const _Flicker({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  State<_Flicker> createState() => _FlickerState();
}

class _FlickerState extends State<_Flicker> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  late final _scale = Tween(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Flicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.on && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: size.center(Offset.zero), radius: r), a, math.pi / n, false, p);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

class _WeekDot extends StatelessWidget {
  const _WeekDot(this.d);
  final WeekMark d;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final label = weekdayLabel(fromKey(d.key));
    Widget circle;
    switch (d.mark) {
      case DayMark.set:
        circle = Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.accent, width: 2)),
          child: Center(child: Flame(size: 16, color: c.accentInk)),
        );
      case DayMark.today:
        circle = SizedBox.square(dimension: 34, child: CustomPaint(painter: _DashedCircle(c.accent)));
      default:
        final border = d.mark == DayMark.future ? c.future : c.lineStrong;
        circle = Opacity(
          opacity: d.mark == DayMark.miss ? 0.7 : 1,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: border, width: 2)),
            child: d.mark == DayMark.rest
                ? Center(child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.dot, shape: BoxShape.circle)))
                : null,
          ),
        );
    }
    return Semantics(
      label: '$label ${_markLabel[d.mark]}',
      child: ExcludeSemantics(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          circle,
          const SizedBox(height: 4),
          Text(label, style: DsText.small.copyWith(color: c.muted)),
        ]),
      ),
    );
  }
}

/// 듀오링고식 연속 기록 카드.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, this.share = true});
  final bool share;

  @override
  Widget build(BuildContext context) {
    final info = context.ui.streak;
    if (info == null) return const SizedBox.shrink();
    final c = context.ds;
    final on = info.current > 0;
    return Semantics(
      container: true,
      label: '연속 셋 데이',
      child: DsCard(gap: 14, children: [
        Row(children: [
          _Flicker(
            on: on,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: on ? c.pillBg : c.surface2, shape: BoxShape.circle),
              child: Center(child: Flame(size: 40, color: on ? c.accent : c.lineBtn)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${info.current}'),
                  TextSpan(text: ' 일 연속', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.muted, letterSpacing: 0)),
                ]),
                style: TextStyle(fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.ink, fontFeatures: DsText.num),
              ),
              LabelText('최고 기록 ${info.best}일${info.nextMilestone != null ? ' · 다음 기념일까지 ${info.nextMilestone}일' : ''}'),
            ]),
          ),
        ]),
        if (!info.todayDone) Text('오늘 셋 데이를 채우면 ${info.current + 1}일 연속이에요', style: DsText.body.copyWith(color: c.accentStrong, fontWeight: FontWeight.w600)),
        Row(children: [for (final d in info.week) Expanded(child: Center(child: _WeekDot(d)))]),
        if (share) ShareButtons(info: info),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 순위 줄(친구·근처 공통)
// ---------------------------------------------------------------------------

const _medal = [Color(0xFFF4B04F), Color(0xFFC3CADB), Color(0xFFC9895A)];
const _medalInk = Color(0xFF1A1300);

/// 순위 한 줄: 등수 · 이름(나·예시) · 연속 기록 · 이번 주 셋 데이 · 빼기.
class RankLine extends StatelessWidget {
  const RankLine({
    super.key,
    required this.index,
    required this.count,
    required this.name,
    required this.me,
    required this.streak,
    required this.score,
    this.extra,
    this.demo = false,
    this.onRemove,
    this.last = false,
  });
  final int index;
  final int count;
  final String name;
  final bool me;
  final int streak;
  final int score;

  /// 연속 기록 뒤에 붙일 말(예: '3시간 전', '2km 안').
  final String? extra;
  final bool demo;
  final VoidCallback? onRemove;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final medal = index < 3 && count > 1;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      // 웹은 '나' 줄을 카드 끝까지 넓히지만(음수 여백), 여기서는 모든 줄에 같은 안쪽 여백을 둔다.
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: me ? c.pillBg : null,
        borderRadius: me ? BorderRadius.circular(12) : null,
        border: me || last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: medal ? _medal[index] : c.surface2, shape: BoxShape.circle),
          child: Text('${index + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: medal ? _medalInk : c.muted)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: name),
                    if (me) TextSpan(text: ' · 나', style: DsText.label.copyWith(color: c.muted)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsText.base.copyWith(fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
              if (demo) ...[const SizedBox(width: 6), const DemoTag(small: true)],
            ]),
            Row(children: [
              Flame(size: 12, color: streak > 0 ? c.accent : c.lineBtn),
              const SizedBox(width: 4),
              Flexible(
                child: Text('$streak일 연속${extra != null && extra!.isNotEmpty ? ' · $extra' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.small.copyWith(color: c.muted)),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$score'),
            TextSpan(text: '일', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
          ]),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink, fontFeatures: DsText.num),
        ),
        if (onRemove != null)
          Transform.translate(
            offset: const Offset(8, 0),
            child: DsIconButton(DsIcons.close, onPressed: onRemove, label: '$name 빼기', size: 36, iconSize: 16),
          ),
      ]),
    );
  }
}

/// '예시' 표시(예시 데이터).
class DemoTag extends StatelessWidget {
  const DemoTag({super.key, this.small = false, this.text});
  final bool small;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 6, vertical: small ? 0 : 1),
      decoration: BoxDecoration(border: Border.all(color: c.lineBtn), borderRadius: BorderRadius.circular(6)),
      child: Text(text ?? (small ? '예시' : '예시 포함'), style: TextStyle(fontSize: small ? 10 : 11, fontWeight: FontWeight.w700, color: c.muted)),
    );
  }
}

// ---------------------------------------------------------------------------
// 친구와 겨루기
// ---------------------------------------------------------------------------

/// 받침이 있으면 '과', 없으면 '와'.
String _withParticle(String word) => hasBatchim(word) ? '과' : '와';

String _ago(DateTime? d, DateTime t) {
  if (d == null) return '';
  final m = math.max(0, (t.difference(d).inMilliseconds / 60000).round());
  if (m < 60) return '$m분 전';
  if (m < 60 * 24) return '${(m / 60).round()}시간 전';
  return '${(m / 1440).round()}일 전';
}

/// 친구와 겨루기: 이번 주 셋 데이 순위.
class Friends extends StatefulWidget {
  const Friends({super.key});

  @override
  State<Friends> createState() => _FriendsState();
}

class _FriendsState extends State<Friends> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _sendCode(AppState s, StreakInfo info, DateTime t) async {
    haptic(8);
    final store = context.store;
    final code = makeFriendCode(id: s.profile.id, name: s.profile.name, info: info, now: t);
    final r = await shareText(shareMessage(cardData(s, info), code), subject: 'DaySet 친구 코드');
    if (!mounted) return;
    if (r != ShareOutcome.cancelled) {
      context.toast(shareResultText(r));
      store.track('share', 'code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = context.ui.streak;
    if (info == null) return const SizedBox.shrink();
    final s = context.app;
    final c = context.ds;
    final t = context.ui.now;
    final rows = leaderboard(id: s.profile.id, name: s.profile.name, info: info, friends: s.friends, now: t);
    final myRank = rows.indexWhere((r) => r.me) + 1;
    final leader = rows.first;
    final gap = !leader.me ? leader.weekSetDays - info.weekSetDays : 0;
    final strong = TextStyle(fontWeight: FontWeight.w700, color: c.accentStrong);

    return DsStack(children: [
      if (s.profile.name.isEmpty)
        DsCard(children: [
          const DsTitle('친구에게 보일 이름'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                maxLength: 12,
                decoration: dsInput(context, hint: '예: 대희').copyWith(counterText: ''),
                style: DsText.base.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(width: 8),
            DsButton.primary('저장', onPressed: _name.text.trim().isEmpty ? null : () => context.store.setProfileName(_name.text)),
          ]),
        ]),
      Semantics(
        container: true,
        label: '이번 주 순위',
        child: DsCard(children: [
          const Row(children: [
            Expanded(child: DsTitle('이번 주 순위')),
            LabelText('셋 데이 → 연속 기록 순'),
          ]),
          Text.rich(
            rows.length == 1
                ? const TextSpan(text: '아직 친구가 없어요. 내 코드를 보내고 친구 코드를 받아 보세요.')
                : myRank == 1
                    ? TextSpan(children: [TextSpan(text: '1위', style: strong), const TextSpan(text: '예요. 이번 주를 지켜요.')])
                    : TextSpan(children: [
                        const TextSpan(text: '지금 '),
                        TextSpan(text: '$myRank위', style: strong),
                        TextSpan(text: ' · 1위까지 셋 데이 ${math.max(1, gap)}일'),
                      ]),
            style: DsText.body.copyWith(color: c.ink),
          ),
          Column(children: [
            for (var i = 0; i < rows.length; i++)
              RankLine(
                index: i,
                count: rows.length,
                name: rows[i].name,
                me: rows[i].me,
                streak: rows[i].streak,
                score: rows[i].weekSetDays,
                extra: rows[i].me ? null : '${rows[i].stale ? '지난주 기록 · ' : ''}${_ago(rows[i].updatedAt, t)}',
                onRemove: rows[i].me ? null : () => context.store.removeFriend(rows[i].id),
                last: i == rows.length - 1,
              ),
          ]),
          _ShareRow(
            left: _BrandButton(label: '내 코드 보내기', icon: DsIcons.chat, color: _kakaoBg, fg: _kakaoInk, onTap: () => _sendCode(s, info, t)),
            right: _BrandButton(label: '친구 코드 넣기', icon: DsIcons.plus, outlined: true, onTap: () => showAddFriendSheet(context)),
          ),
          const LabelText('지금은 서로 코드를 보낼 때 순위가 바뀌어요. 서버가 붙으면 친구 순위가 실시간으로 바뀌어요.'),
        ]),
      ),
      if (s.profile.name.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: DsButton('이름 바꾸기 (${s.profile.name})', kind: BtnKind.ghost, small: true, onPressed: () {
            _name.text = s.profile.name;
            context.store.setProfileName('');
          }),
        ),
    ]);
  }
}

/// 친구 코드 넣기 창.
Future<void> showAddFriendSheet(BuildContext context) => showDsSheet<void>(context, title: '친구 코드 넣기', builder: (_) => const _AddFriend());

class _AddFriend extends StatefulWidget {
  const _AddFriend();

  @override
  State<_AddFriend> createState() => _AddFriendState();
}

class _AddFriendState extends State<_AddFriend> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final raw = _text.text.trim();
    final f = raw.isEmpty ? null : readFriendCode(raw, now: context.ui.now);
    return DsStack(children: [
      const LabelText("카카오톡으로 받은 메시지를 통째로 붙여 넣어도 돼요. 'DS1-'로 시작하는 코드를 찾아 읽어요."),
      SizedBox(
        height: 120,
        child: TextField(
          controller: _text,
          autofocus: true,
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          decoration: dsInput(context, hint: 'DS1-...'),
          style: DsText.body.copyWith(color: c.ink),
        ),
      ),
      if (raw.isNotEmpty && f == null) LabelText('코드를 찾지 못했어요', color: c.miss),
      if (f != null)
        DsCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), gap: 2, children: [
          Text(f.name, style: DsText.base.copyWith(fontWeight: FontWeight.w600, color: c.ink)),
          LabelText('${f.streak}일 연속 · 이번 주 셋 데이 ${f.weekSetDays}일'),
        ]),
      DsButton.primary('넣기', block: true, onPressed: f == null
          ? null
          : () {
              final r = context.store.addFriend(f);
              haptic(10);
              context.toast(switch (r) {
                AddResult.self => '내 코드예요. 친구 코드를 넣어 주세요',
                AddResult.updated => '${f.name}의 기록을 새로 받았어요',
                AddResult.added => '${f.name}${_withParticle(f.name)} 겨루기 시작!',
              });
              if (r != AddResult.self) Navigator.of(context).pop();
            }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 기념일 축하(3·7·14·30일…)
// ---------------------------------------------------------------------------

Future<void> showCelebrate(BuildContext context, StreakInfo info, int days) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      barrierColor: const Color(0x9905080F),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, a, b) => _Celebrate(info: info, days: days),
      transitionBuilder: (ctx, a, b, child) {
        final reduce = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
        if (reduce) return FadeTransition(opacity: a, child: child);
        return FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
        );
      },
    );

class _Celebrate extends StatefulWidget {
  const _Celebrate({required this.info, required this.days});
  final StreakInfo info;
  final int days;

  @override
  State<_Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<_Celebrate> with SingleTickerProviderStateMixin {
  late final _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduce && !_burst.isAnimating && _burst.value == 0) _burst.forward();
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final days = widget.days;
    final line = days >= 30 ? '한 달을 지켰어요. 이제 습관이 됐어요.' : days >= 7 ? '일주일을 지켰어요. 이 흐름을 이어 가요.' : '좋은 시작이에요. 내일도 이어 가요.';
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Material(
            color: Colors.transparent,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: '$days일 연속 달성',
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.accent, width: 2),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: c.pillBg, spreadRadius: 6),
                    const BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 24)),
                  ],
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(
                      child: _Flicker(
                        on: true,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(color: c.pillBg, shape: BoxShape.circle),
                          child: const Center(child: Flame(size: 84)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$days'),
                        TextSpan(text: ' 일 연속', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.muted, letterSpacing: 0)),
                      ]),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 56, height: 60 / 56, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.ink, fontFeatures: DsText.num),
                    ),
                    const SizedBox(height: 14),
                    Text('셋 데이 $days일 연속 달성!', textAlign: TextAlign.center, style: DsText.title.copyWith(color: c.ink)),
                    const SizedBox(height: 14),
                    Text(line, textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.inkSoft)),
                    const SizedBox(height: 14),
                    ShareButtons(info: widget.info),
                    const SizedBox(height: 14),
                    DsButton('계속하기', block: true, onPressed: () => Navigator.of(context).pop()),
                  ]),
                  // 불꽃 둘레로 퍼지는 조각
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 60,
                    child: IgnorePointer(
                      child: Center(
                        child: SizedBox.square(
                          dimension: 1,
                          child: AnimatedBuilder(
                            animation: _burst,
                            builder: (context, _) => CustomPaint(painter: _BurstPainter(_burst.value, [c.accent, c.sleep, c.work])),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 12조각이 가운데에서 바깥으로 퍼지며 사라진다(웹 .burst).
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.colors);
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    // 앞 150ms는 기다린다.
    final p = ((t * 1050 - 150) / 900).clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return;
    final e = Curves.easeOutCubic.transform(p);
    final dist = 20 + 100 * e;
    for (var i = 0; i < 12; i++) {
      final color = i % 3 == 2 ? colors[2] : (i % 3 == 0 ? colors[1] : colors[0]);
      canvas.save();
      canvas.rotate(i * math.pi / 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-3, -dist - 18, 6, 18), const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 1 - p),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
