// 소셜 탭: 내 연속 기록 공유, 근처 사람들(익명)과 겨루기, 친구와 겨루기. 웹 버전 src/ui/screens/SocialTab.tsx와 같은 화면.
//
// 1단계(앱 프리뷰)는 위치를 읽지 않는다(위치기반서비스 신고·검토 전). QR·코드를 주고받은 사람만 근처 순위에 올라온다.
// 카메라로 QR 찍기는 다음 업데이트에서 붙인다(지금은 코드 붙여 넣기).

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/nearby.dart';
import '../../app/social.dart';
import '../../app/store.dart';
import '../../app/streak.dart';
import '../../platform/share.dart';
import '../kit.dart';
import '../scope.dart';
import '../social.dart';
import '../theme.dart';

/// 근처 순위에 위치를 쓰는지. 앱 1단계는 쓰지 않는다.
const nearbyUsesLocation = false;

enum _Who { nearby, friends }

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  _Who _view = _Who.nearby;

  @override
  Widget build(BuildContext context) {
    final info = context.ui.streak;
    return ScreenList(children: [
      const TopBar(title: '소셜'),
      if (info != null) ...[
        const StreakCard(),
        Segmented<_Who>(
          label: '누구와',
          value: _view,
          onChanged: (v) => setState(() => _view = v),
          options: const [SegOption(_Who.nearby, '근처 (익명)'), SegOption(_Who.friends, '친구')],
        ),
        if (_view == _Who.nearby) _Nearby(info: info) else const Friends(),
      ],
    ]);
  }
}

class _Nearby extends StatelessWidget {
  const _Nearby({required this.info});
  final StreakInfo info;

  void _turn(BuildContext context, bool on) {
    final store = context.store;
    if (!on) {
      store.setNearbyOn(false);
      context.toast('근처에 보이지 않게 했어요');
      return;
    }
    // 위치를 쓰지 않는 빌드: 익명으로만 켠다.
    store.setNearbyOn(true);
    context.toast('익명으로 켰어요. QR을 주고받은 사람만 순위에 보여요');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final c = context.ds;
    final me = anonName(s.profile.id);
    final n = s.nearby;
    final board = nearbyBoard(s.profile.id, info, n, context.ui.now);
    final hasDemo = n.people.any((p) => p.demo);

    return DsStack(children: [
      Semantics(
        container: true,
        label: '근처 공개',
        child: DsCard(children: [
          DsSwitch(
            value: n.on,
            onChanged: (v) => _turn(context, v),
            label: '근처에 익명으로 보이기',
            sub: nearbyUsesLocation ? "실명 대신 '$me'로 보여요 · 위치는 약 2km 칸으로만" : "실명 대신 '$me'로 보여요 · 지금은 위치를 쓰지 않아요",
            onText: '보이는 중',
            offText: '꺼짐',
          ),
        ]),
      ),
      if (n.on)
        Semantics(
          container: true,
          label: '내 주변 이번 주 순위',
          child: DsCard(children: [
            Row(children: [
              const Expanded(child: DsTitle('내 주변 이번 주')),
              if (hasDemo) const DemoTag(),
            ]),
            Row(children: [
              Expanded(child: _SumBox(label: '내 순위', value: '${board.myRank}위', small: ' / ${board.rows.length}명')),
              const SizedBox(width: 8),
              Expanded(child: _SumBox(label: '상위', value: '${board.topPercent}%', accent: true)),
              const SizedBox(width: 8),
              Expanded(child: _SumBox(label: '근처 평균', value: '${board.avgWeek.toStringAsFixed(1)}일')),
            ]),
            Column(children: [
              for (var i = 0; i < board.rows.length; i++)
                RankLine(
                  index: i,
                  count: board.rows.length,
                  name: board.rows[i].name,
                  me: board.rows[i].me,
                  streak: board.rows[i].streak,
                  score: board.rows[i].weekSetDays,
                  extra: board.rows[i].band,
                  demo: board.rows[i].demo,
                  onRemove: board.rows[i].me ? null : () => context.store.removeNearby(board.rows[i].id),
                  last: i == board.rows.length - 1,
                ),
            ]),
            DsButton.primary('가까운 사람과 QR로 주고받기', icon: DsIcons.share, block: true, onPressed: () => _showExchange(context, info, me)),
            const LabelText('지금은 서버 없이, 옆에 있는 사람과 QR·코드를 직접 주고받아 순위에 올려요. 서버가 붙으면 같은 동네 사람들이 자동으로 보여요.'),
          ]),
        )
      else
        DsCard(children: [
          Text('켜면 이름 없이 별명과 셋 데이 수만 근처 사람들에게 보여요. 끄면 바로 사라져요.', style: DsText.body.copyWith(color: c.ink)),
          const LabelText(nearbyUsesLocation
              ? '보이는 것: 익명 별명, 이번 주 셋 데이 수, 연속 일수, 대략 거리(2km 단위) · 보이지 않는 것: 이름, 정확한 위치, 기록 내용'
              : '보이는 것: 익명 별명, 이번 주 셋 데이 수, 연속 일수 · 보이지 않는 것: 이름, 위치, 기록 내용. 지금은 QR을 주고받은 사람만 순위에 올라와요.'),
        ]),
    ]);
  }
}

class _SumBox extends StatelessWidget {
  const _SumBox({required this.label, required this.value, this.small, this.accent = false});
  final String label;
  final String value;
  final String? small;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabelText(label, maxLines: 1),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: value),
            if (small != null) TextSpan(text: small, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.muted)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: accent ? c.accentStrong : c.ink, fontFeatures: DsText.num),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 가까운 사람과 익명 코드 주고받기: 내 QR 보여 주기 + 상대 코드 붙여 넣기
// ---------------------------------------------------------------------------

void _showExchange(BuildContext context, StreakInfo info, String me) =>
    showDsSheet<void>(context, title: '가까운 사람과 주고받기', builder: (_) => _Exchange(info: info, me: me));

enum _Mode { show, scan }

class _Exchange extends StatefulWidget {
  const _Exchange({required this.info, required this.me});
  final StreakInfo info;
  final String me;

  @override
  State<_Exchange> createState() => _ExchangeState();
}

class _ExchangeState extends State<_Exchange> {
  _Mode _mode = _Mode.show;
  final _text = TextEditingController();
  String? _code;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 창을 여는 순간의 기록으로 한 번만 만든다.
    if (_code == null) {
      final store = context.store;
      final s = store.state;
      _code = makeFriendCode(id: s.profile.id, name: widget.me, info: widget.info, now: store.now(), anon: true, cell: s.nearby.cell);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _accept(String raw) {
    final store = context.store;
    final f = readFriendCode(raw, now: store.now());
    if (f == null) {
      context.toast('코드를 찾지 못했어요');
      return;
    }
    haptic(14);
    final r = f.anon ? store.addNearby(f) : store.addFriend(f);
    context.toast(r == AddResult.self
        ? '내 코드예요'
        : f.anon
            ? '${f.name}님이 근처 순위에 올라왔어요'
            : '${f.name}님을 친구 순위에 넣었어요');
    if (r != AddResult.self) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return DsStack(children: [
      Segmented<_Mode>(
        label: '주고받기',
        value: _mode,
        onChanged: (v) => setState(() => _mode = v),
        options: const [SegOption(_Mode.show, '내 QR 보여 주기'), SegOption(_Mode.scan, '상대 QR 받기')],
      ),
      if (_mode == _Mode.show)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: c.pillBg, spreadRadius: 6)],
              ),
              child: QrImageView(
                data: _code!,
                version: QrVersions.auto,
                size: 220,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0D1220)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0D1220)),
                semanticsLabel: '${widget.me}의 익명 코드 QR',
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.me, style: DsText.base.copyWith(fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 8),
            LabelText('이번 주 셋 데이 ${widget.info.weekSetDays}일 · ${widget.info.current}일 연속 · 이름과 정확한 위치는 들어 있지 않아요', align: TextAlign.center),
            const SizedBox(height: 8),
            DsButton('코드 복사', small: true, onPressed: () async {
              final ok = await copyText(_code!);
              if (context.mounted) context.toast(ok ? '코드를 복사했어요' : '복사하지 못했어요');
            }),
          ]),
        )
      else ...[
        const LabelText("카메라로 QR 찍기는 다음 업데이트에서 붙어요. 지금은 상대 화면의 '코드 복사'를 받아 붙여 넣어 주세요."),
        SizedBox(
          height: 96,
          child: TextField(
            controller: _text,
            expands: true,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: dsInput(context, hint: 'DS1-… 코드 붙여 넣기'),
            style: DsText.body.copyWith(color: c.ink),
          ),
        ),
        DsButton.primary('넣기', block: true, onPressed: _text.text.trim().isEmpty ? null : () => _accept(_text.text)),
      ],
    ]);
  }
}
