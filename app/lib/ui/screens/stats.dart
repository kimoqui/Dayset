// 기록 탭: 주간(연속 기록·셋 데이·습관별 달성률·날마다 달성률·오늘 기록) / 월간(셋 데이 캘린더·기상 교정·이번 달 달성률).
// 웹 버전 src/ui/screens/Stats.tsx와 같은 화면.

import 'package:flutter/material.dart';

import '../../app/derive.dart';
import '../../app/state.dart';
import '../../core/engine/correction.dart';
import '../../core/model/models.dart';
import '../kit.dart';
import '../scope.dart';
import '../social.dart';
import '../theme.dart';

const _weekHead = ['월', '화', '수', '목', '금', '토', '일'];

enum _View { week, month }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _View _view = _View.week;
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final now = context.ui.now;
    final todayKey = dateKey(now);
    final obs = s.observation;
    final observing = obs != null && (obs.phase == ObservationPhase.recording || todayKey.compareTo(obs.day1) <= 0);
    return ScreenList(children: [
      TopBar(
        title: '기록',
        right: observing ? null : DsButton('오늘 하루 확인', small: true, onPressed: () => context.ui.actions.open(AppPage.evening)),
      ),
      Segmented<_View>(
        label: '기간',
        value: _view,
        onChanged: (v) => setState(() => _view = v),
        options: const [SegOption(_View.week, '주간'), SegOption(_View.month, '월간')],
      ),
      if (_view == _View.week) ...[
        const StreakCard(share: false),
        _Week(s: s, now: now, todayKey: todayKey),
      ] else
        _Month(s: s, now: now, todayKey: todayKey, offset: _monthOffset, setOffset: (n) => setState(() => _monthOffset = n)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 공통: 셋 데이 칸
// ---------------------------------------------------------------------------

class _CalHead extends StatelessWidget {
  const _CalHead();

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: Text(_weekHead[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: context.ds.muted))),
        ],
      ]);
}

/// 일곱 칸 한 줄(빈 칸은 null).
class _CalWeek extends StatelessWidget {
  const _CalWeek(this.cells);
  final List<Widget?> cells;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: Center(child: cells[i] ?? const SizedBox(height: 32))),
        ],
      ]);
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.k, required this.todayKey, required this.isSet, required this.isRest, this.big = false});
  final String k;
  final String todayKey;
  final bool isSet;
  final bool isRest;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final future = k.compareTo(todayKey) > 0;
    final today = k == todayKey;
    final d = fromKey(k);
    final label = '${d.month}월 ${d.day}일 ${isSet ? '셋 데이' : isRest ? '쉬는 날' : future ? '예정' : today ? '오늘' : '일정대로 지내지 못함'}';
    final border = isSet
        ? c.accent
        : today
            ? c.accent
            : future
                ? c.future
                : c.lineStrong;
    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          width: big ? double.infinity : 32,
          height: big ? 40 : 32,
          decoration: BoxDecoration(
            color: isSet ? c.accent : null,
            border: Border.all(color: border, width: today && !isSet ? 2 : 1.5),
            borderRadius: BorderRadius.circular(big ? 10 : 9),
          ),
          child: isRest && !isSet ? Center(child: Container(width: 5, height: 5, decoration: BoxDecoration(color: c.dot, shape: BoxShape.circle))) : null,
        ),
      ),
    );
  }
}

/// '이름 ··· 87% 6/7' 줄.
class _RateLine extends StatelessWidget {
  const _RateLine({required this.label, required this.rate});
  final String label;
  final HabitRateView? rate;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(children: [
      Expanded(child: Text(label, style: DsText.body.copyWith(color: c.ink))),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: pct(rate?.rate), style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: ' ${rate == null ? '' : '${rate!.achieved}/${rate!.counted}'}', style: DsText.label.copyWith(color: c.muted)),
        ]),
        style: DsText.body.copyWith(color: c.ink, fontFeatures: DsText.num),
      ),
    ]);
  }
}

/// 달성률 표시용(엔진 HabitRate를 그대로 감싼다).
class HabitRateView {
  const HabitRateView(this.achieved, this.counted);
  final int achieved;
  final int counted;
  double? get rate => counted == 0 ? null : achieved / counted;
}

HabitRateView? _rateOf(PeriodStats st, RateKey k) {
  final r = st.rates[k];
  return r == null ? null : HabitRateView(r.achieved, r.counted);
}

const _rateRows = [
  ('수면', RateKey.activity(Activity.sleep)),
  ('식사', RateKey.activity(Activity.meal)),
  ('운동', RateKey.activity(Activity.exercise)),
  ('할 일', RateKey.task()),
];

// ---------------------------------------------------------------------------
// 주간
// ---------------------------------------------------------------------------

class _Week extends StatelessWidget {
  const _Week({required this.s, required this.now, required this.todayKey});
  final AppState s;
  final DateTime now;
  final String todayKey;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final keys = weekKeys(now);
    final stats = periodStats(s, keys, now);
    final byKey = {for (final d in stats.days) d.key: d};
    final todayStart = fromKey(todayKey);
    final todayLogs = logsAround(s, todayKey).where((l) => l.end == null || !l.end!.isBefore(todayStart)).toList();
    final shown = todayLogs.where((l) => !l.isEstimate).toList();

    return DsStack(children: [
      Semantics(
        container: true,
        label: '이번 주 셋 데이',
        child: DsCard(children: [
          const Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: DsTitle('이번 주 셋 데이')),
            LabelText('일정대로 지낸 날'),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('${stats.setDays}', style: DsText.display.copyWith(color: c.accentStrong, fontFeatures: DsText.num)),
            const SizedBox(width: 6),
            Text('일 / 7일', style: DsText.base.copyWith(color: c.muted)),
          ]),
          const _CalHead(),
          _CalWeek([
            for (final k in keys) _DayCell(k: k, todayKey: todayKey, isSet: byKey[k]?.isSetDay ?? false, isRest: s.restDays.contains(k), big: true),
          ]),
          const LabelText('셋 데이 = 기상 알람 ±30분 안에 일어나고, 그날 습관을 70% 이상 지킨 날'),
        ]),
      ),
      Semantics(
        container: true,
        label: '습관별 달성률',
        child: DsCard(children: [
          const Row(children: [
            Expanded(child: DsTitle('습관별 달성률')),
            LabelText('이번 주 · 추정 기록 제외'),
          ]),
          for (final (label, key) in _rateRows)
            Builder(builder: (context) {
              final rate = _rateOf(stats, key);
              final color = key.task ? c.task : c.activity(key.activity);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _RateLine(label: label, rate: rate),
                const SizedBox(height: 4),
                Semantics(label: '$label 달성률 ${pct(rate?.rate)}', child: Meter(value: rate?.rate ?? 0, color: color)),
              ]);
            }),
        ]),
      ),
      Semantics(
        container: true,
        label: '날마다 습관 달성률',
        child: DsCard(children: [
          const DsTitle('날마다 습관 달성률'),
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < keys.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Bar(k: keys[i], todayKey: todayKey, day: byKey[keys[i]])),
              ],
            ]),
          ),
          const LabelText('진한 막대가 셋 데이예요'),
        ]),
      ),
      Semantics(
        container: true,
        label: '오늘 기록',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: const Row(children: [
              Expanded(child: DsTitle('오늘 기록')),
              Flexible(child: LabelText('잘못 누른 기록은 지울 수 있어요', align: TextAlign.right)),
            ]),
          ),
          const SizedBox(height: 6),
          DsCard(list: true, children: [
            if (todayLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text("아직 기록이 없어요. 홈의 '지금' 버튼을 눌러 보세요.", textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
              ),
            for (var i = 0; i < shown.length; i++) _LogRow(log: shown[i], last: i == shown.length - 1),
          ]),
        ]),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.k, required this.todayKey, required this.day});
  final String k;
  final String todayKey;
  final DayView? day;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final v = day?.rate;
    final wd = weekdayLabel(fromKey(k));
    final today = k == todayKey;
    return Tooltip(
      message: '$wd ${pct(v)}',
      child: LayoutBuilder(builder: (context, box) {
        // 숫자·요일 글자(각 14)와 간격(4·4)을 뺀 높이가 막대의 100%다.
        final maxH = (box.maxHeight - 36).clamp(0.0, double.infinity);
        final frac = ((v ?? 0.04) * 100).round().clamp(4, 100) / 100;
        return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text(v == null ? '' : '${(v * 100).round()}', style: DsText.small.copyWith(color: c.muted, fontFeatures: DsText.num)),
          const SizedBox(height: 4),
          Opacity(
            opacity: day?.isSetDay ?? false ? 1 : 0.55,
            child: Container(
              width: 26,
              constraints: const BoxConstraints(minHeight: 2),
              height: maxH * frac,
              decoration: BoxDecoration(
                color: v == null ? c.future : c.accent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(wd, style: DsText.small.copyWith(color: today ? c.accent : c.muted, fontWeight: today ? FontWeight.w600 : FontWeight.w500)),
        ]);
      }),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.last});
  final ActivityLog log;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final l = log;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Container(width: 4, height: 24, decoration: BoxDecoration(color: c.activity(l.activity), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Text(l.activity.label, style: DsText.base.copyWith(color: c.ink))),
        const SizedBox(width: 12),
        Text('${formatHm(l.start)}–${l.end != null ? formatHm(l.end!) : '지금'}', style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num)),
        const SizedBox(width: 12),
        SizedBox(width: 30, child: Text(l.source.label, textAlign: TextAlign.right, style: DsText.small.copyWith(color: c.muted))),
        Transform.translate(
          offset: const Offset(10, 0),
          child: DsIconButton(DsIcons.trash, onPressed: () => context.store.deleteLog(l.id), label: '${l.activity.label} 기록 지우기', iconSize: 16),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 월간
// ---------------------------------------------------------------------------

class _Month extends StatelessWidget {
  const _Month({required this.s, required this.now, required this.todayKey, required this.offset, required this.setOffset});
  final AppState s;
  final DateTime now;
  final String todayKey;
  final int offset;
  final ValueChanged<int> setOffset;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final base = DateTime(now.year, now.month + offset, 1);
    final keys = monthKeys(base.year, base.month);
    final stats = periodStats(s, keys, now);
    final setKeys = {for (final d in stats.days) if (d.isSetDay) d.key};
    final lead = fromKey(keys.first).weekday - 1;
    final cells = <String?>[...List<String?>.filled(lead, null), ...keys];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
    final corr = s.correction;

    return DsStack(children: [
      Semantics(
        container: true,
        label: '셋 데이 캘린더',
        child: DsCard(gap: 8, children: [
          Row(children: [
            Transform.translate(offset: const Offset(-12, 0), child: DsIconButton(DsIcons.back, onPressed: () => setOffset(offset - 1), label: '이전 달', iconSize: 18)),
            Transform.translate(offset: const Offset(-12, 0), child: DsTitle('${base.month}월 셋 데이')),
            Transform.translate(
              offset: const Offset(-12, 0),
              child: DsIconButton(DsIcons.forward, onPressed: offset >= 0 ? null : () => setOffset(offset + 1), label: '다음 달', iconSize: 18),
            ),
            const Spacer(),
            const LabelText('일정대로 지낸 날'),
          ]),
          const _CalHead(),
          for (final w in weeks)
            _CalWeek([
              for (final k in w) k == null ? null : _DayCell(k: k, todayKey: todayKey, isSet: setKeys.contains(k), isRest: s.restDays.contains(k)),
            ]),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${offset == 0 ? '이번 달' : '${base.month}월'} 셋 데이 '),
                TextSpan(text: '${setKeys.length}일', style: TextStyle(fontWeight: FontWeight.w700, color: c.accentStrong)),
              ]),
              style: DsText.body.copyWith(color: c.ink),
            ),
          ),
          const LabelText('채운 칸은 셋 데이, 점은 쉬는 날이에요'),
        ]),
      ),
      if (corr != null)
        Semantics(
          container: true,
          label: '기상 교정',
          child: DsCard(children: [
            Row(children: [
              const Expanded(child: DsTitle('기상 단계적 교정')),
              Pill(corr.plan.status == CorrectionStatus.done ? '완료' : '${corr.plan.currentStep + 1}/${corr.plan.totalWeeks + 1}단계'),
            ]),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: '이번 주 기상 목표 '),
                TextSpan(text: formatClock(corr.plan.weekTarget), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' → 최종 ${formatClock(corr.plan.target)} · 한 번에 ${corr.plan.stepSize}분씩'),
              ]),
              style: DsText.body.copyWith(color: c.ink),
            ),
            for (final h in corr.history.length > 4 ? corr.history.sublist(corr.history.length - 4) : corr.history)
              LabelText('${h.week.length >= 5 ? h.week.substring(5).replaceFirst('-', '/') : h.week} 주: 기상 달성 ${pct(h.rate)} → ${formatClock(h.target)}'),
            const LabelText('지난주 기상 달성률이 80% 이상이면 한 단계 당기고, 50% 미만이면 한 단계 늦춰요.'),
          ]),
        ),
      Semantics(
        container: true,
        label: '이번 달 습관 달성률',
        child: DsCard(children: [
          const DsTitle('이번 달 습관 달성률'),
          for (final (label, key) in _rateRows) _RateLine(label: label, rate: _rateOf(stats, key)),
        ]),
      ),
    ]);
  }
}
