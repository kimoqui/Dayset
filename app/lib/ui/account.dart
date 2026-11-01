// 계정: 로그인·가입 창, 설정의 계정 카드, 기록이 엇갈렸을 때 고르는 창. 웹 버전 src/ui/Account.tsx와 같은 문구.

import 'package:flutter/material.dart';

import '../app/cloud.dart';
import '../app/cloud_sync.dart';
import '../core/model/models.dart';
import 'kit.dart';
import 'scope.dart';
import 'theme.dart';

/// 계정 동기화를 화면에 건넨다(바뀌면 다시 그린다).
class CloudNotifier extends ChangeNotifier {
  CloudNotifier(this.sync) {
    sync.addListener(notifyListeners);
  }
  final CloudSync sync;

  @override
  void dispose() {
    sync.removeListener(notifyListeners);
    super.dispose();
  }
}

class CloudScope extends InheritedNotifier<CloudNotifier> {
  const CloudScope({super.key, required CloudNotifier notifier, required super.child}) : super(notifier: notifier);

  static CloudSync? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CloudScope>()?.notifier?.sync;
  static CloudSync? read(BuildContext context) => context.getInheritedWidgetOfExactType<CloudScope>()?.notifier?.sync;
}

final _emailRe = RegExp(r'^\S+@\S+\.\S+$');

String _ago(int? t) {
  if (t == null) return '아직 맞추지 않음';
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  final m = DateTime.now().difference(d).inMinutes;
  return m < 1 ? '방금 맞춤' : (m < 60 ? '$m분 전에 맞춤' : '${koreanDate(d)} ${formatHm(d)}에 맞춤');
}

/// 로그인·가입 창.
Future<void> showAccountSheet(BuildContext context, {bool signUp = false}) {
  return showDsSheet<void>(context, title: '계정', builder: (ctx) => _AccountForm(signUp: signUp));
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.signUp});
  final bool signUp;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late bool _up = widget.signUp;
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  bool get _valid => _emailRe.hasMatch(_email.text.trim()) && _pw.text.length >= 6;

  Future<void> _submit() async {
    final sync = CloudScope.read(context);
    if (sync == null || !_valid || _busy) return;
    final toast = context.ui.actions.toast;
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      if (!_up) {
        await sync.signIn(_email.text, _pw.text);
        toast('로그인했어요. 기록을 계정과 맞췄어요');
        nav.pop();
      } else {
        final ok = await sync.signUp(_email.text, _pw.text);
        if (!ok) {
          if (mounted) setState(() => _msg = '메일함에서 가입 확인 링크를 누른 뒤 로그인해 주세요');
        } else {
          toast('계정을 만들었어요. 이 기기 기록을 계정에 올렸어요');
          nav.pop();
        }
      }
      haptic(12);
    } catch (e) {
      if (mounted) setState(() => _msg = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final sync = CloudScope.maybeOf(context);
    final ready = sync?.ready ?? false;
    return DsStack(gap: 12, children: [
      DsTitle(_up ? '계정 만들기' : '로그인', style: DsText.h2),
      if (!ready) const DsBanner('계정 서버를 준비하고 있어요. 준비되면 여기서 로그인할 수 있어요.'),
      const LabelText('계정에 기록을 두면 웹과 안드로이드 앱, 다른 휴대폰에서 같은 기록을 이어서 써요.'),
      DsField(
        label: '이메일',
        child: TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: DsText.base.copyWith(color: c.ink),
          decoration: dsInput(context, hint: 'name@example.com'),
          onChanged: (_) => setState(() {}),
        ),
      ),
      DsField(
        label: '비밀번호 (6자 이상)',
        child: TextField(
          controller: _pw,
          obscureText: true,
          autofillHints: [_up ? AutofillHints.newPassword : AutofillHints.password],
          style: DsText.base.copyWith(color: c.ink),
          decoration: dsInput(context),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
      ),
      if (_msg != null) Semantics(liveRegion: true, child: LabelText(_msg!, color: c.miss)),
      DsButton.primary(_busy ? '잠시만요…' : (_up ? '계정 만들기' : '로그인'), block: true, onPressed: _valid && !_busy && ready ? _submit : null),
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
        DsButton(_up ? '이미 계정이 있어요 · 로그인' : '처음이에요 · 계정 만들기', kind: BtnKind.ghost, small: true, onPressed: () => setState(() {
              _up = !_up;
              _msg = null;
            })),
        if (!_up)
          DsButton('비밀번호 찾기', kind: BtnKind.ghost, small: true, onPressed: !_emailRe.hasMatch(_email.text.trim()) || !ready || sync == null
              ? null
              : () async {
                  try {
                    await sync.resetPassword(_email.text);
                    if (mounted) setState(() => _msg = '비밀번호를 바꾸는 메일을 보냈어요. 메일함을 확인해 주세요');
                  } catch (e) {
                    if (mounted) setState(() => _msg = errorText(e));
                  }
                }),
      ]),
    ]);
  }
}

/// 설정의 계정 카드.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _confirmDelete = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final sync = CloudScope.maybeOf(context);
    if (sync == null) return const SizedBox.shrink();
    final s = sync.session;
    final status = switch (sync.status) {
      CloudStatus.syncing => '맞추는 중…',
      CloudStatus.offline => '인터넷이 끊겨 기다리는 중 · 기록은 이 기기에 저장돼요',
      CloudStatus.error => sync.message ?? '맞추지 못했어요',
      CloudStatus.conflict => '기록이 엇갈렸어요 · 고르기를 기다려요',
      _ => '${_ago(sync.meta.syncedAt)}${sync.meta.dirty ? ' · 올릴 변경 있음' : ''}',
    };
    return DsCard(children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const DsTitle('계정'),
            LabelText(s?.email ?? '웹·앱·다른 휴대폰에서 같은 기록을 이어 써요', maxLines: 1),
          ]),
        ),
        const SizedBox(width: 8),
        if (s == null)
          DsButton.primary('로그인', small: true, onPressed: () => showAccountSheet(context))
        else
          DsButton('지금 맞추기', small: true, icon: DsIcons.refresh, onPressed: sync.status == CloudStatus.syncing
              ? null
              : () async {
                  final toast = context.ui.actions.toast;
                  await sync.syncNow();
                  toast(sync.status == CloudStatus.idle ? '계정과 맞췄어요' : (sync.message ?? '맞추지 못했어요'));
                }),
      ]),
      if (s != null) ...[
        Semantics(liveRegion: true, child: LabelText(status, color: sync.status == CloudStatus.error ? c.miss : null)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          DsButton('로그아웃', small: true, onPressed: () async {
            final toast = context.ui.actions.toast;
            await sync.signOut();
            toast('로그아웃했어요. 이 기기 기록은 그대로 있어요');
          }),
          DsButton(_confirmDelete ? '정말 지우기' : '계정에 저장된 기록 지우기', small: true, kind: BtnKind.danger, onPressed: () async {
            if (!_confirmDelete) {
              setState(() => _confirmDelete = true);
              return;
            }
            final toast = context.ui.actions.toast;
            try {
              await sync.deleteRemote();
              toast('계정에 저장된 기록을 지웠어요. 이 기기 기록은 그대로 있어요');
            } catch (e) {
              toast(errorText(e));
            }
            if (mounted) setState(() => _confirmDelete = false);
          }),
        ]),
      ] else if (sync.message != null)
        LabelText(sync.message!, color: c.miss),
    ]);
  }
}

/// 기록이 엇갈렸을 때 고르는 창. 셸이 연다(닫기 단추 없이 둘 중 하나를 고른다).
Future<void> showConflictSheet(BuildContext context, CloudSync sync) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.ds.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => PopScope(canPop: false, child: _ConflictBody(sync: sync)),
  );
}

class _ConflictBody extends StatefulWidget {
  const _ConflictBody({required this.sync});
  final CloudSync sync;

  @override
  State<_ConflictBody> createState() => _ConflictBodyState();
}

class _ConflictBodyState extends State<_ConflictBody> {
  bool _busy = false;

  Future<void> _pick(bool useRemote) async {
    final toast = context.ui.actions.toast;
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    await widget.sync.resolveConflict(useRemote: useRemote);
    nav.pop();
    toast(useRemote ? '계정 기록으로 바꿨어요. 이 기기 기록은 설정 → 데이터에 보관했어요' : '이 기기 기록을 계정에 올렸어요');
  }

  @override
  Widget build(BuildContext context) {
    final cf = widget.sync.conflict;
    if (cf == null) return const SizedBox(height: 120);
    final remote = summarizeState(cf.remote.state);
    final when = DateTime.tryParse(cf.remote.updatedAt)?.toLocal();
    final device = cf.remote.device == null ? '' : (cf.remote.device == 'android' ? ' (안드로이드 앱)' : ' (웹)');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: DsStack(gap: 12, children: [
        DsTitle(cf.first ? '어느 기록으로 이어 쓸까요?' : '기록이 엇갈렸어요', style: DsText.sub),
        Text(
          cf.first ? '이 기기와 계정에 모두 기록이 있어요. 하나를 골라 주세요.' : '다른 기기에서 바뀐 기록과 이 기기에서 바뀐 기록이 둘 다 있어요. 하나를 골라 주세요.',
          style: DsText.body.copyWith(color: context.ds.ink),
        ),
        DsCard(children: [
          const DsTitle('계정에 저장된 기록'),
          LabelText([
            remote == null ? '읽지 못한 기록' : '기록 ${remote.logs}개 · 할 일 ${remote.tasks}개${remote.lastLog != null ? ' · 마지막 기록 ${koreanDate(remote.lastLog!)}' : ''}',
            if (when != null) ' · ${koreanDate(when)} ${formatHm(when)} 저장',
            device,
          ].join()),
          DsButton.primary('계정 기록 쓰기', block: true, onPressed: _busy || remote == null ? null : () => _pick(true)),
        ]),
        DsCard(children: [
          const DsTitle('이 기기 기록'),
          DsButton('이 기기 기록으로 계정 덮기', block: true, onPressed: _busy ? null : () => _pick(false)),
        ]),
        const LabelText('고르지 않은 쪽은 지우지 않아요. 계정 기록을 고르면 이 기기 기록은 설정 → 데이터에 보관해요.'),
      ]),
    );
  }
}
