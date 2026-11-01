// 홈: 오늘 24시간 링, '지금' 버튼 5개, 다음 일정·알람, 코칭 제안, 저녁 확인. 웹 버전 src/ui/screens/Home.tsx와 같은 흐름.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/derive.dart';
import '../../app/state.dart';
import '../../core/model/models.dart';
import '../day_ring.dart';
import '../kit.dart';
import '../preview.dart';
import '../scope.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final store = context.store;
    final ui = context.ui;
    final c = context.ds;
    final now = ui.now;
    final todayKey = dateKey(now);
    final plan = planFor(s, todayKey, now);
    final tomorrow = planFor(s, dateKey(addDays(now, 1)), now);
    final cur = currentLog(s);
    final upcoming = plan.blocks.where((b) => b.start.isAfter(now) && b.activity != Activity.sleep).toList();
    final next = upcoming.firstOrNull;
    final inbox = store.pendingInbox(now);
    final resolved = inbox != null ? null : store.recentResolved(now);
    final woke = wakeRecord(s, todayKey);
    final obs = s.observation;
    final recording = obs?.phase == ObservationPhase.recording;
    // 1일차(관찰한 날)에는 오늘 일정이 없다.
    final observingToday = obs != null && (recording || todayKey.compareTo(obs.day1) <= 0);
    final showEvening = !observingToday && now.hour >= 19 && !s.eveningDone.contains(todayKey);

    // 링: 바깥 = 오늘 자동 일정(관찰 중이면 기록), 안쪽 = 실제 기록
    final day0 = dayStart(now);
    final nowMin = diffMin(now, day0);
    final records = [
      for (final l in s.logs)
        if (l.source != LogSource.estimate) clipSegment(day0, l.start, l.end ?? now, c.activity(l.activity), '${l.activity.label}${l.end != null ? '' : '(지금)'}'),
    ].whereType<RingSegment>().toList();
    final planSegs = observingToday
        ? <RingSegment>[]
        : [
            for (final b in plan.blocks)
              // 이동은 링에 그리지 않는다
              if (!(b.kind == BlockKind.fixed && !b.locked))
                clipSegment(
                  day0,
                  b.start,
                  b.end,
                  b.kind == BlockKind.task || b.kind == BlockKind.fixed ? c.work : c.activity(b.activity ?? Activity.work),
                  b.kind == BlockKind.task ? '할 일 · ${b.title}' : b.kind == BlockKind.fixed ? '일정 · ${b.title}' : b.title,
                ),
            clipSegment(day0, tomorrow.bedTonight, addDays(day0, 1), c.sleep, '수면(오늘 밤)', from: tomorrow.bedTonight, to: tomorrow.wake),
          ].whereType<RingSegment>().toList();
    final ringPlan = observingToday ? records : planSegs;
    final ringRecords = observingToday ? <RingSegment>[] : records;

    // 다음 알람: 오늘 기상 전이면 기상, 아니면 오늘 밤 취침
    final wakeNext = !observingToday && woke == null && now.isBefore(plan.wake);
    final alarmLabel = wakeNext ? '기상 알람' : '취침 알림';
    final alarmAt = wakeNext ? plan.wake : tomorrow.bedTonight;
    final alarmReason = wakeNext ? plan.plan.alarms.first.reason : tomorrow.plan.alarms[1].reason;
    final streak = ui.streak?.current ?? 0;
    final dark = ui.dark;

    return ScreenList(children: [
      Row(children: [
        Flexible(child: Text(koreanDate(now), maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.body.copyWith(color: c.muted, fontWeight: FontWeight.w500))),
        if (!observingToday) ...[
          const SizedBox(width: 10),
          Pressable(
            scale: 0.92,
            semanticLabel: '$streak일 연속 셋 데이, 소셜 보기',
            onTap: () => ui.actions.open(AppPage.social),
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
              decoration: BoxDecoration(color: c.pillBg, borderRadius: BorderRadius.circular(15)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flame(size: 16, color: streak > 0 ? c.accent : c.lineBtn),
                const SizedBox(width: 4),
                Text('$streak', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accentStrong, fontFeatures: DsText.num)),
              ]),
            ),
          ),
        ],
        const Spacer(),
        Pressable(
          semanticLabel: dark ? '밝은 화면으로 바꾸기' : '나이트 화면으로 바꾸기',
          onTap: ui.actions.toggleTheme,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineBtn), borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              DsIcon(dark ? DsIcons.sun : DsIcons.moon, size: 18, color: c.ink),
              const SizedBox(width: 6),
              Text(dark ? '밝게' : '나이트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            ]),
          ),
        ),
      ]),
      Semantics(
        header: true,
        child: Text(recording ? '오늘은 하루를 그대로 기록해요' : observingToday ? '내일 일정을 만들었어요' : '오늘 일정은 자동으로 짜뒀어요',
            style: DsText.title.copyWith(color: c.ink)),
      ),
      const SurveyCard(),
      if (!store.storageAvailable)
        DsBanner(store.storageProblem == SaveResult.quota
            ? '저장 공간이 가득 차 새 기록을 저장하지 못하고 있어요. 설정 → 데이터에서 백업을 내보낸 뒤 가져온 캘린더 연결을 끊거나 기록을 정리해 주세요.'
            : '이 기기에 기록을 저장하지 못하고 있어요. 앱을 닫으면 기록이 사라질 수 있어요.'),
      Semantics(
        container: true,
        label: '오늘 24시간',
        child: Column(children: [
          DayRing(
            plan: ringPlan,
            records: ringRecords,
            recordsOnly: observingToday,
            nowMinutes: nowMin,
            label: '오늘 24시간 링. 지금 ${formatHm(now)}, ${cur != null ? '${cur.activity.label} 중' : '기록 없음'}',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                child: Text('지금 ${formatHm(now)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentInk, fontFeatures: DsText.num)),
              ),
              const SizedBox(height: 6),
              Text(cur != null ? '${cur.activity.label} 중' : '기록 없음',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w700, color: c.ink)),
              Text(cur != null ? '${formatDuration(math.max(0, cur.minutesUntil(now)))}째' : '아래 버튼으로 시작해요',
                  textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
            ]),
          ),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 6, children: [
            for (final a in const [Activity.sleep, Activity.meal, Activity.work, Activity.exercise])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c.activity(a), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(a.label, style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
          ]),
          const SizedBox(height: 8),
          Text(observingToday ? '링은 오늘 기록한 하루예요' : '바깥 링은 자동 일정, 안쪽 선은 실제 기록이에요', style: DsText.small.copyWith(color: c.muted)),
        ]),
      ),
      Semantics(
        container: true,
        label: '지금 상태 바꾸기',
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            // 좁은 화면(360dp 미만)에서는 단추를 조금 줄여 한 줄에 둔다.
            for (final a in Activity.values)
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: _RoundButton(activity: a, on: cur?.activity == a, onTap: () => ui.actions.tapNow(a)))),
          ]),
        ),
      ),
      if (!recording)
        Row(children: [
          Expanded(
            child: _MiniStat(
              label: observingToday ? '내일 기상 알람' : '다음',
              value: observingToday ? formatHm(tomorrow.wake) : next != null ? '${formatHm(next.start)} ${next.title}' : '남은 일정 없음',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Tooltip(message: alarmReason, child: _MiniStat(label: alarmLabel, value: formatHm(alarmAt)))),
        ]),
      if (recording && obs!.day1.compareTo(todayKey) > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            onTap: ui.actions.showGuide,
            semanticLabel: "내일이 1일차예요 · 잘 때 '수면' 누르기",
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: c.pillBg, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(17)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                DsIcon(DsIcons.sleep, size: 16, color: c.accentStrong),
                const SizedBox(width: 6),
                Flexible(
                  child: Text("내일이 1일차예요 · 잘 때 '수면' 누르기",
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentStrong)),
                ),
              ]),
            ),
          ),
        ),
      if (recording && todayKey.compareTo(obs!.day1) >= 0) _RecordingCard(day1: obs.day1, onReview: () => ui.actions.open(AppPage.review)),
      if (inbox != null)
        Semantics(
          container: true,
          label: '코칭 제안',
          child: DsCard(gap: 12, children: [
            _Lead(inbox.message),
            Row(children: [
              if (inbox.kind == InboxKind.coach) ...[
                DsButton.primary('바꾸기', onPressed: () => store.acceptSuggestion(inbox.id)),
                const SizedBox(width: 8),
                DsButton('그대로 두기', onPressed: () => store.keepSuggestion(inbox.id)),
              ] else
                DsButton('확인', onPressed: () => store.keepSuggestion(inbox.id)),
            ]),
          ]),
        ),
      if (resolved?.resultText != null)
        Semantics(
          container: true,
          label: '코칭 결과',
          child: DsCard(children: [
            _Lead(resolved!.resultText!),
            if (resolved.action == 'settings')
              Row(children: [DsButton('설정 열기', small: true, onPressed: () => ui.actions.open(AppPage.settings))]),
          ]),
        ),
      if (showEvening)
        Semantics(
          container: true,
          label: '저녁 확인',
          child: DsCard(children: [
            Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  DsTitle('오늘 하루 확인'),
                  SizedBox(height: 2),
                  LabelText('기록 없는 일정만 골라요 · 1분이면 끝나요'),
                ]),
              ),
              const SizedBox(width: 10),
              DsButton.primary('확인하기', small: true, onPressed: () => ui.actions.open(AppPage.evening)),
            ]),
          ]),
        ),
      if (!observingToday)
        Semantics(
          container: true,
          label: '다음 일정',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(children: [
                const Expanded(child: DsTitle('다음 일정')),
                DsButton('전체 보기', kind: BtnKind.ghost, small: true, onPressed: () => ui.actions.open(AppPage.schedule)),
              ]),
            ),
            if (upcoming.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('오늘 남은 일정이 없어요', textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
              ),
            for (final (i, b) in upcoming.take(3).indexed)
              Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(border: i == math.min(3, upcoming.length) - 1 ? null : Border(bottom: BorderSide(color: c.line))),
                child: Row(children: [
                  SizedBox(
                    width: 44,
                    child: Text(formatHm(b.start), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted, fontFeatures: DsText.num)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.base.copyWith(color: c.ink))),
                  const SizedBox(width: 12),
                  Text(kindLabel(b),
                      style: TextStyle(fontSize: 12, color: b.adjusted ? c.accentStrong : c.muted, fontWeight: b.adjusted ? FontWeight.w700 : FontWeight.w400)),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

/// '지금' 둥근 버튼: 누르면 들어가고, 켜질 때 톡 튀어나온다.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.activity, required this.on, required this.onTap});
  final Activity activity;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: on ? c.accent : c.surface,
        border: Border.all(color: on ? c.accent : c.lineStrong),
        shape: BoxShape.circle,
      ),
      child: Center(child: DsIcon(DsIcons.of(activity), size: 24, color: on ? c.accentInk : c.ink)),
    );
    return Pressable(
      scale: 0.88,
      selected: on,
      semanticLabel: '${activity.label} 시작',
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          reduce || !on
              ? circle
              : TweenAnimationBuilder<double>(
                  key: const ValueKey('on'),
                  tween: Tween(begin: 0.8, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: circle,
                ),
          const SizedBox(height: 6),
          Text(activity.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink)),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabelText(label),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600, fontFeatures: DsText.num)),
      ]),
    );
  }
}

/// 1일차: 설정 없이 기록만 한다. 저녁에 기록한 하루를 보고 내일 일정을 정한다.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.day1, required this.onReview});
  final String day1;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final now = context.ui.now;
    final c = context.ds;
    final todayKey = dateKey(now);
    if (todayKey.compareTo(day1) < 0) {
      return Semantics(
        container: true,
        label: '관찰 안내',
        child: DsCard(tint: true, children: [
          const DsTitle('내일 하루를 그대로 기록해요'),
          Text("오늘 밤 잘 때 '수면'을 눌러 주세요. 내일은 식사·업무·운동을 시작할 때마다 버튼만 누르면 돼요. 내일 저녁에 기록한 하루를 보고 일정을 같이 정해요.",
              style: DsText.body.copyWith(color: c.ink)),
        ]),
      );
    }
    final o = observedDay(s, day1, now);
    final meals = o.meals.length;
    final chips = [
      ('기상', o.wakeAt != null),
      ('식사 $meals번', meals > 0),
      (o.work != null ? '업무 ${formatDuration(o.work!.minutes)}' : '업무', o.work != null),
      ('운동', o.exercise != null),
    ];
    final after = todayKey.compareTo(day1) > 0;
    final late = after || now.hour >= 18;
    return Semantics(
      container: true,
      label: '1일차 기록',
      child: DsCard(tint: true, children: [
        Row(children: [
          Expanded(child: DsTitle(after ? '어제 기록으로 일정을 만들어요' : '1일차 · 오늘은 기록만 해요')),
          const SizedBox(width: 8),
          const Pill('관찰'),
        ]),
        ChipWrap(children: [
          for (final (label, done) in chips)
            Semantics(
              label: '$label ${done ? '기록됨' : '기록 없음'}',
              excludeSemantics: true,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: done ? c.pillBg : Colors.transparent,
                  border: Border.all(color: done ? c.accent : c.lineStrong, width: 1.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (done) ...[DsIcon(DsIcons.check, size: 14, stroke: 2.6, color: c.ink), const SizedBox(width: 4)],
                  Text(label, style: TextStyle(fontSize: 14, fontWeight: done ? FontWeight.w700 : FontWeight.w400, color: c.ink)),
                ]),
              ),
            ),
        ]),
        if (late)
          DsButton.primary(after ? '어제 하루 정리하기' : '오늘 하루 정리하고 내일 일정 만들기', block: true, onPressed: onReview)
        else
          const LabelText('설정은 필요 없어요. 저녁에 기록한 하루를 보고, 바꾸고 싶은 시각만 고치면 내일부터 일정이 자동으로 짜여요.'),
        if (!late && o.logCount > 0)
          Align(alignment: Alignment.centerLeft, child: DsButton('지금 정리하기', kind: BtnKind.ghost, small: true, onPressed: onReview)),
      ]),
    );
  }
}

/// 첫 문장을 굵게: "어젯밤 5시간 40분 잤어요. 오늘 운동을…"
class _Lead extends StatelessWidget {
  const _Lead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final base = DsText.body.copyWith(color: c.ink);
    final i = text.indexOf('. ');
    if (i < 0) return Text(text, style: base);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: text.substring(0, i + 1), style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: text.substring(i + 1)),
    ]));
  }
}
