// 설정: 시연, 기상·수면·교정, 습관 시간, 준비·이동, 할 일 배치, 캘린더, 알람·알림, 베타 지표, 의견·동의, 화면, 데이터, 시험용 시각.
// 웹 버전 src/ui/screens/Settings.tsx와 같은 구성이다.

import 'package:flutter/material.dart';

import '../../app/duration.dart';
import '../../app/seed.dart';
import '../../app/state.dart';
import '../../core/engine/correction.dart';
import '../../core/model/models.dart';
import '../../platform/notify.dart';
import '../../platform/share.dart';
import '../calendar_connect.dart';
import '../account.dart';
import '../kit.dart';
import '../preview.dart';
import '../scope.dart';
import '../theme.dart';

String _pad(int n) => n.toString().padLeft(2, '0');
String _stamp(DateTime d) => '${d.year}${_pad(d.month)}${_pad(d.day)}-${_pad(d.hour)}${_pad(d.minute)}';

/// 확인 창. 확인하면 true.
Future<bool> _confirm(BuildContext context, {required String title, required String body, required String ok, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.ds;
      return Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: DsText.sub.copyWith(color: c.ink)),
            const SizedBox(height: 8),
            Text(body, style: DsText.body.copyWith(color: c.inkSoft)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              DsButton('취소', small: true, onPressed: () => Navigator.of(ctx).pop(false)),
              const SizedBox(width: 8),
              DsButton(ok, small: true, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () => Navigator.of(ctx).pop(true)),
            ]),
          ]),
        ),
      );
    },
  );
  return r ?? false;
}

/// 두 칸씩 나란히(웹 .field-row).
class _Grid extends StatelessWidget {
  const _Grid(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: children[i]),
        const SizedBox(width: 10),
        Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
      ]));
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// 왼쪽에 붙은(늘어나지 않는) 단추.
Widget _left(Widget w) => Align(alignment: Alignment.centerLeft, child: w);

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: context.ds.line);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _usual;
  String? _msg;
  DateTime? _clockValue;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final store = context.store;
    final ui = context.ui;
    final c = context.ds;
    final g = s.goals;
    final st = s.settings;
    final now = ui.now;
    final usual = _usual ?? s.correction?.plan.baseline ?? g.wake.minutes;
    final durCount = s.durations.samples.where((x) => !x.outlier).length;
    final durByType = [
      for (final t in TaskType.values)
        if (calibrationFor(s.durations, type: t, title: '') case final cal?) '${t.label} ${_ratio(cal.ratio)}배',
    ];
    final kept = store.storage.keptBackups();

    void setGoals(HabitGoals next) => store.updateGoals(next);
    void setMeal(int i, HabitSlot m) => setGoals(g.copyWith(meals: [for (var j = 0; j < g.meals.length; j++) j == i ? m : g.meals[j]]));
    void setSt(PersonalSettings next) => store.updateSettings(next);

    final problem = store.storageProblem;

    return ScreenList(children: [
      const TopBar(title: '설정'),
      const AccountCard(),

      if (problem != SaveResult.ok)
        DsBanner(problem == SaveResult.quota
            ? '저장 공간이 가득 찼어요. 기기 저장 공간을 비우거나 아래에서 백업을 내려받아 두세요. 그동안 새 기록은 저장되지 않을 수 있어요.'
            : '기록을 기기에 저장하지 못하고 있어요. 앱을 다시 열어 보고, 계속되면 백업을 내려받아 두세요.'),

      if (s.demo)
        DsCard(tint: true, children: [
          Text('예시 데이터로 보는 중이에요. 내 정보로 시작하면 예시 기록은 지워져요.', style: DsText.body.copyWith(color: c.ink)),
          DsButton.primary('내 정보로 새로 시작', onPressed: store.resetAll),
        ]),

      // 시연
      DsCard(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('일정 자동 생성 시연', style: DsText.h2.copyWith(color: c.ink)),
              const SizedBox(height: 2),
              const LabelText('발표용 · 엔진이 일정을 짜는 과정을 단계별로 보여 줘요'),
            ]),
          ),
          const SizedBox(width: 10),
          DsButton.primary('열기', small: true, onPressed: () => ui.actions.open(AppPage.demo)),
        ]),
      ]),

      // 기상과 수면
      DsCard(gap: 14, children: [
        Text('기상과 수면', style: DsText.h2.copyWith(color: c.ink)),
        _Grid([
          TimeField(label: '목표 기상', value: g.wake.minutes, onChanged: (v) => setGoals(g.copyWith(wake: ClockTime(v)))),
          NumberField(label: '수면 시간', value: g.sleepMinutes, step: 30, min: 240, max: 720, onChanged: (v) => setGoals(g.copyWith(sleepMinutes: v))),
        ]),
        const _Divider(),
        Text('단계적 교정', style: DsText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
        if (s.correction != null && s.correction!.plan.status == CorrectionStatus.active)
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '이번 주 기상 목표 '),
              TextSpan(text: formatClock(s.correction!.plan.weekTarget), style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: ' → 최종 ${formatClock(s.correction!.plan.target)}'),
            ]),
            style: DsText.body.copyWith(color: c.ink),
          )
        else
          const LabelText('지금 기상 시각과 목표가 30분 넘게 차이 나면, 매주 30분씩 단계적으로 당겨요.'),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TimeField(label: '지금 보통 일어나는 시각', value: usual, onChanged: (v) => setState(() => _usual = v))),
          const SizedBox(width: 10),
          DsButton(s.correction != null ? '다시 만들기' : '교정 시작', onPressed: () => store.setCorrection(usual)),
        ]),
        if (s.correction != null)
          _left(DsButton('교정 끄기 · 목표 기상을 바로 쓰기', kind: BtnKind.ghost, small: true, onPressed: () => store.setCorrection(null))),
      ]),

      // 습관 시간
      DsCard(gap: 14, children: [
        Text('습관 시간', style: DsText.h2.copyWith(color: c.ink)),
        for (var i = 0; i < g.meals.length; i++)
          _Grid([
            TimeField(label: g.meals[i].title, value: g.meals[i].start.minutes, onChanged: (v) => setMeal(i, g.meals[i].copyWith(start: ClockTime(v)))),
            NumberField(label: '걸리는 시간', value: g.meals[i].minutes, min: 10, max: 120, onChanged: (v) => setMeal(i, g.meals[i].copyWith(minutes: v))),
          ]),
        DsSwitch(
          value: g.exercise != null,
          onChanged: (v) => setGoals(v
              ? g.copyWith(exercise: const HabitSlot(title: '운동', activity: Activity.exercise, start: ClockTime(20 * 60 + 30), minutes: 30))
              : g.copyWith(clearExercise: true)),
          label: '운동 넣기',
          onText: '넣기',
          offText: '빼기',
        ),
        if (g.exercise != null)
          _Grid([
            TimeField(label: '운동', value: g.exercise!.start.minutes, onChanged: (v) => setGoals(g.copyWith(exercise: g.exercise!.copyWith(start: ClockTime(v))))),
            NumberField(label: '걸리는 시간', value: g.exercise!.minutes, min: 5, max: 180, onChanged: (v) => setGoals(g.copyWith(exercise: g.exercise!.copyWith(minutes: v)))),
          ]),
      ]),

      // 준비와 이동
      DsCard(gap: 14, children: [
        Text('준비와 이동', style: DsText.h2.copyWith(color: c.ink)),
        const LabelText('첫 일정이 이르면 기상 = 첫 일정 − 준비 − 이동으로 알람을 당겨요.'),
        _Grid([
          NumberField(label: '아침 준비', value: st.prepMinutes, onChanged: (v) => setSt(st.copyWith(prepMinutes: v))),
          NumberField(label: '이동', value: st.travelMinutes, onChanged: (v) => setSt(st.copyWith(travelMinutes: v))),
          NumberField(label: '잠들기까지', value: st.sleepLatencyMinutes, max: 90, onChanged: (v) => setSt(st.copyWith(sleepLatencyMinutes: v))),
          NumberField(label: '취침 전 마무리', value: st.windDownMinutes, max: 120, onChanged: (v) => setSt(st.copyWith(windDownMinutes: v))),
        ]),
        if (st.bedEarlierMinutes > 0)
          Row(children: [
            Expanded(child: Text('코칭으로 취침 ${st.bedEarlierMinutes}분 앞당김', style: DsText.body.copyWith(color: c.ink))),
            DsButton('되돌리기', small: true, onPressed: () => setSt(st.copyWith(bedEarlierMinutes: 0))),
          ]),
      ]),

      // 할 일 배치
      DsCard(gap: 14, children: [
        Text('할 일 배치', style: DsText.h2.copyWith(color: c.ink)),
        _Grid([
          TimeField(label: '집중 시간 시작', value: st.focusStart.minutes, onChanged: (v) => setSt(st.copyWith(focusStart: ClockTime(v)))),
          TimeField(label: '집중 시간 끝', value: st.focusEnd.minutes, onChanged: (v) => setSt(st.copyWith(focusEnd: ClockTime(v)))),
          NumberField(label: '한 조각', value: st.chunkMinutes, min: 15, max: 120, onChanged: (v) => setSt(st.copyWith(chunkMinutes: v))),
          NumberField(label: '조각 사이 휴식', value: st.restMinutes, max: 30, onChanged: (v) => setSt(st.copyWith(restMinutes: v))),
        ]),
        DsSwitch(
          value: s.durations.on,
          onChanged: (on) => notifyPlan(
            context,
            store.setDurationAuto(on),
            on ? '걸리는 시간 보정을 켜고 남은 일정을 다시 짰어요' : '보정을 끄고 적은 시간 그대로 다시 짰어요',
            on ? '걸리는 시간 보정을 켰어요' : '걸리는 시간 보정을 껐어요',
          ),
          label: '걸리는 시간 자동 보정',
          sub: durByType.isNotEmpty
              ? '지금 보정: ${durByType.join(' · ')} (끝낸 할 일 $durCount개 기준)'
              : '끝낸 할 일 $durCount개 기록 · 같은 종류 $minTypeSamples개부터 실제 걸린 시간으로 일정을 잡아요',
          onText: '켬',
          offText: '끔',
        ),
      ]),

      // 캘린더 연결
      DsCard(gap: 14, children: [
        Row(children: [
          Expanded(child: Text('캘린더 연결', style: DsText.h2.copyWith(color: c.ink))),
          DsButton.primary(s.calendars.isNotEmpty ? '관리' : '연결하기', small: true, onPressed: () => showCalendarSheet(context)),
        ]),
        if (s.calendars.isEmpty)
          const LabelText('.ics 파일을 가져오면 수업·회의 같은 일정이 자동으로 들어와요.')
        else
          for (final cal in s.calendars)
            LabelText(
              '${cal.name} · ${cal.count}개 · ${koreanDate(cal.lastSync)} ${formatHm(cal.lastSync)}${cal.error != null ? ' · ${cal.error}' : ''}',
              color: cal.error != null ? c.miss : null,
            ),
      ]),

      _NotifyCard(s: s),

      const MetricsCard(),

      // 의견과 동의
      DsCard(gap: 14, children: [
        Text('의견과 동의', style: DsText.h2.copyWith(color: c.ink)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          DsButton('불편 신고·의견 남기기', onPressed: () => showReportSheet(context, page: '설정')),
          DsButton('동의 다시 보기', onPressed: () => _openConsent(context)),
        ]),
        LabelText(
          '${s.consent != null ? '생활 기록 동의 ${s.consent!.health ? '함' : '안 함'} · 베타 지표 내보내기 ${s.consent!.metrics ? '동의' : '동의 안 함'} · ${koreanDate(s.consent!.at)}' : '예시 데이터예요'}'
          '${s.feedback.reports.isNotEmpty ? ' · 남긴 의견 ${s.feedback.reports.length}건' : ''}',
        ),
        _left(DsButton('생활 기록 동의 거두기', kind: BtnKind.ghost, small: true, onPressed: () async {
          final ok = await _confirm(context,
              title: '동의를 거둘까요?', body: '동의를 거두면 이 기기에 남긴 생활 기록을 모두 지우고 처음 화면으로 돌아가요.', ok: '동의 거두고 기록 지우기', danger: true);
          if (ok) store.resetAll();
        })),
      ]),

      // 화면
      DsCard(gap: 14, children: [
        Text('화면', style: DsText.h2.copyWith(color: c.ink)),
        Segmented<ThemePref>(
          label: '테마',
          value: ui.theme,
          onChanged: ui.actions.setTheme,
          options: const [SegOption(ThemePref.dark, '나이트'), SegOption(ThemePref.light, '밝게'), SegOption(ThemePref.system, '기기 설정')],
        ),
      ]),

      // 데이터
      DsCard(gap: 14, children: [
        Text('데이터', style: DsText.h2.copyWith(color: c.ink)),
        const LabelText('기록은 이 기기에만 저장돼요. 다른 기기로 옮기거나 웹 버전과 주고받을 때 백업 파일을 쓰세요. 웹 버전 백업도 그대로 불러와요.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          DsButton('백업 내려받기', icon: DsIcons.download, onPressed: () => _export(context)),
          DsButton('백업 불러오기', icon: DsIcons.upload, onPressed: () => _import(context)),
          DsButton('예시 데이터 넣기', onPressed: () async {
            final ok = await _confirm(context, title: '예시 데이터를 넣을까요?', body: '지금 데이터는 지우지 않고 따로 보관해요. 아래 보관 목록에서 되돌릴 수 있어요.', ok: '넣기');
            if (!ok || !context.mounted) return;
            store.loadDemo(demoState(context.ui.now));
            setState(() => _msg = '예시 데이터를 넣었어요. 이전 기록은 아래에 보관했어요');
          }),
        ]),
        if (_msg != null) LabelText(_msg!),
        if (kept.isNotEmpty) ...[
          const LabelText('보관한 이전 데이터 · 최근 3개까지'),
          for (final k in kept)
            Row(children: [
              Expanded(
                child: LabelText('${koreanDate(k.at)} ${formatHm(k.at)} · ${k.reason == KeptReason.broken ? '읽지 못한 데이터' : '불러오기 전 기록'}'),
              ),
              const SizedBox(width: 6),
              DsButton('내려받기', small: true, onPressed: () async {
                final text = store.storage.kv.read(k.key) ?? '';
                final r = await shareTextFile('dayset-kept-${k.at.millisecondsSinceEpoch}.json', text);
                if (context.mounted && r == ShareOutcome.failed) context.toast(r.text);
              }),
              if (k.reason == KeptReason.beforeImport) ...[
                const SizedBox(width: 6),
                DsButton('되돌리기', small: true, onPressed: () => _restore(context, k)),
              ],
            ]),
        ],
        _left(DsButton('모든 기록 지우기', kind: BtnKind.danger, onPressed: () async {
          final ok = await _confirm(context, title: '모든 기록을 지울까요?', body: '이 기기에 남긴 기록·일정·설정을 모두 지우고 처음 화면으로 돌아가요. 되돌릴 수 없어요.', ok: '정말 모두 지우기', danger: true);
          if (ok) store.resetAll();
        })),
      ]),

      // 시험용 시각
      DsCard(gap: 14, children: [
        Text('시험용 시각', style: DsText.h2.copyWith(color: c.ink)),
        const LabelText('알람·저녁 확인 흐름을 미리 보려면 앱 안의 시각을 옮겨요. 기록도 이 시각으로 남으니 시험 뒤 되돌려 주세요.'),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: DsField(
              label: '앱 시각',
              child: Pressable(
                scale: 0.98,
                semanticLabel: '앱 시각 고르기',
                onTap: () => _pickClock(context, _clockValue ?? now),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    _fmtClock(_clockValue ?? now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DsButton('적용', onPressed: () {
            final target = _clockValue;
            if (target == null) return;
            // 실제 시각 = 지금 앱 시각 − 지금 옮긴 만큼
            final wall = store.now().subtract(store.clockOffset);
            store.clockOffset = target.difference(wall);
            context.toast('앱 시각을 ${_fmtClock(target)}로 옮겼어요');
          }),
        ]),
        if (store.clockOffset != Duration.zero)
          _left(DsButton('실제 시각으로 되돌리기', small: true, onPressed: () {
            store.clockOffset = Duration.zero;
            setState(() => _clockValue = null);
            context.toast('실제 시각으로 되돌렸어요');
          })),
      ]),

      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LabelText('DaySet 0.9.0 · 앱 1단계 · 서버 없이 기기 안에서 동작해요', align: TextAlign.center),
      ),
    ]);
  }

  static String _ratio(double r) {
    final x = (r * 100).round() / 100;
    return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
  }

  static String _fmtClock(DateTime d) => '${d.year}. ${d.month}. ${d.day}. ${formatHm(d)}';

  Future<void> _pickClock(BuildContext context, DateTime from) async {
    final day = await showDatePicker(
      context: context,
      initialDate: from,
      firstDate: DateTime(from.year - 1),
      lastDate: DateTime(from.year + 1, 12, 31),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: from.hour, minute: from.minute),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (time == null || !mounted) return;
    setState(() => _clockValue = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _export(BuildContext context) async {
    final store = context.store;
    final r = await shareTextFile('dayset-backup-${_stamp(context.ui.now)}.json', store.exportBackup());
    if (!context.mounted) return;
    if (r == ShareOutcome.failed) {
      context.toast('백업 파일을 만들지 못했어요');
    } else if (r == ShareOutcome.shared) {
      store.track('backup_export');
    }
  }

  Future<void> _import(BuildContext context) async {
    final ok = await _confirm(context,
        title: '백업을 불러올까요?', body: '지금 데이터는 지우지 않고 따로 보관해요. 잘못 불러와도 아래 보관 목록에서 되돌릴 수 있어요.', ok: '불러오기');
    if (!ok || !context.mounted) return;
    final how = await showDsSheet<String>(
      context,
      title: '백업 불러오기',
      builder: (ctx) => DsStack(children: [
        const LabelText('웹 버전·앱에서 내려받은 dayset-backup 파일을 고르거나, 파일 내용을 붙여 넣어 주세요.'),
        DsButton.primary('파일 고르기', block: true, icon: DsIcons.upload, onPressed: () => Navigator.of(ctx).pop('file')),
        DsButton('내용 붙여 넣기', block: true, onPressed: () => Navigator.of(ctx).pop('paste')),
      ]),
    );
    if (!context.mounted || how == null) return;
    String? text;
    if (how == 'file') {
      try {
        text = (await pickTextFile(['json']))?.text;
      } catch (_) {
        if (context.mounted) setState(() => _msg = '불러오지 못했어요: 파일을 읽지 못했어요');
        return;
      }
    } else {
      text = await showDsSheet<String>(context, title: '백업 내용 붙여 넣기', builder: (ctx) => const _PasteBox());
    }
    if (text == null || text.trim().isEmpty || !context.mounted) return;
    _apply(context, text, '백업을 불러왔어요. 불러오기 전 기록은 아래에 보관했어요');
  }

  Future<void> _restore(BuildContext context, KeptBackup k) async {
    final ok = await _confirm(context, title: '불러오기 전 기록으로 되돌릴까요?', body: '지금 데이터는 지우지 않고 따로 보관해요.', ok: '되돌리기');
    if (!ok || !context.mounted) return;
    final text = context.store.storage.kv.read(k.key);
    if (text == null) {
      setState(() => _msg = '되돌리지 못했어요: 보관한 데이터를 찾지 못했어요');
      return;
    }
    _apply(context, text, '불러오기 전 기록으로 되돌렸어요', fail: '되돌리지 못했어요');
  }

  void _apply(BuildContext context, String text, String done, {String fail = '불러오지 못했어요'}) {
    try {
      context.store.importBackup(text);
      setState(() => _msg = done);
      context.toast(done);
    } on FormatException catch (e) {
      setState(() => _msg = '$fail: ${e.message}');
    } catch (_) {
      setState(() => _msg = '$fail: 백업 파일을 읽지 못했어요');
    }
  }

  void _openConsent(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: ctx.ds.bg,
        body: SafeArea(
          child: ConsentPanel(
            title: '동의 다시 보기',
            onBack: () => Navigator.of(ctx).pop(),
            onDone: () {
              Navigator.of(ctx).pop();
              context.toast('동의를 바꿨어요');
            },
          ),
        ),
      ),
    ));
  }
}

/// 백업 내용 붙여 넣기 칸.
class _PasteBox extends StatefulWidget {
  const _PasteBox();

  @override
  State<_PasteBox> createState() => _PasteBoxState();
}

class _PasteBoxState extends State<_PasteBox> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DsStack(gap: 10, children: [
        TextField(
          controller: _ctrl,
          minLines: 5,
          maxLines: 8,
          style: TextStyle(fontSize: 13, color: context.ds.ink),
          decoration: dsInput(context, hint: '{"version":1, … } 백업 파일 내용'),
          onChanged: (_) => setState(() {}),
        ),
        DsButton.primary('불러오기', block: true, onPressed: _ctrl.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_ctrl.text)),
      ]);
}

/// 알람과 알림. 휴대폰 알림을 쓸 수 없는 빌드(notifyPort.available = false)에서는 설정만 저장한다.
class _NotifyCard extends StatefulWidget {
  const _NotifyCard({required this.s});
  final AppState s;

  @override
  State<_NotifyCard> createState() => _NotifyCardState();
}

class _NotifyCardState extends State<_NotifyCard> {
  bool _denied = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final store = context.store;
    final c = context.ds;
    final available = notifyPort.available;
    final on = s.notify.enabled;
    return DsCard(gap: 14, children: [
      Text('알람과 알림', style: DsText.h2.copyWith(color: c.ink)),
      LabelText(available
          ? "지금 일정을 알림에 띄워 두고, 일정이 시작됐는데 기록이 없으면 앱이 꺼져 있어도 알려요. 알림의 '기록하기'로 바로 기록돼요. 기상·취침 알람은 휴대폰 알람처럼 울려요."
          : '잠금화면 알림은 다음 업데이트에서 켜져요. 지금은 앱이 열려 있을 때 화면 안 일정 체크 띠와 알림 띠로 알려 드려요. 아래 설정은 저장해 두었다가 알림이 켜지면 그대로 써요.'),
      if (available && on) ...[
        _switches(s),
      ] else ...[
        DsButton.primary('알림 켜기', icon: DsIcons.bell, onPressed: () async {
          if (!available) {
            store.setNotify((n) => n.copyWith(enabled: false));
            store.track('notify_enable', 'unavailable');
            context.toast('잠금화면 알림은 다음 업데이트에서 켜져요');
            return;
          }
          final ok = await notifyPort.request();
          if (!context.mounted) return;
          store.setNotify((n) => n.copyWith(enabled: ok));
          store.track('notify_enable', ok ? 'granted' : 'denied');
          setState(() => _denied = !ok);
          context.toast(ok ? '알림을 켰어요' : '알림이 허용되지 않았어요');
        }),
        if (!available) _switches(s),
      ],
      if (_denied) LabelText('기기 설정에서 DaySet 알림이 막혀 있어요. 허용한 뒤 다시 눌러 주세요', color: c.miss),
      _left(DsButton('알람 미리 울려보기', onPressed: context.ui.actions.testRing)),
    ]);
  }

  Widget _switches(AppState s) {
    final store = context.store;
    final available = notifyPort.available;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DsSwitch(
        value: s.notify.sticky,
        onChanged: (v) => store.setNotify((n) => n.copyWith(sticky: v)),
        label: '지금 일정 알림 띄워 두기',
        sub: available ? '알림 목록에 지금·다음 일정을 계속 보여 줘요' : '알림이 켜지면 잠금화면에 지금·다음 일정을 계속 보여 줘요',
        onText: '켬',
        offText: '끔',
      ),
      DsSwitch(
        value: s.notify.remind,
        onChanged: (v) => store.setNotify((n) => n.copyWith(remind: v)),
        label: '기록할 때 알리기',
        sub: available ? '일정이 시작됐는데 기록이 없으면 소리·진동으로 알려요' : '일정이 시작됐는데 기록이 없으면 알려요(지금은 앱 안에서만)',
        onText: '켬',
        offText: '끔',
      ),
    ]);
  }
}
