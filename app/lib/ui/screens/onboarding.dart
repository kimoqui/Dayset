// 처음 화면: 소개 → 목표 정하기 → 동의 → 알림 → (기록부터 시작) 또는 (바로 설정 1/2·2/2).
// 웹 버전 src/ui/screens/Onboarding.tsx와 같은 흐름이다.

import 'package:flutter/material.dart';

import '../../app/seed.dart';
import '../../app/state.dart';
import '../../core/model/models.dart';
import '../kit.dart';
import '../preview.dart';
import '../scope.dart';
import '../theme.dart';

enum _Step { hero, goal, consent, notify, set1, set2 }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.hero;

  /// true = 첫날 기록부터, false = 기록 없이 바로 설정.
  bool _obs = true;
  HabitGoals _goals = defaultGoals;
  int _usual = 7 * 60 + 40;
  int _prep = 50;
  int _travel = 40;

  void _go(_Step s) => setState(() => _step = s);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
      child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final store = context.store;
    switch (_step) {
      case _Step.goal:
        return GoalStep(onBack: () => _go(_Step.hero), onNext: () => _go(_Step.consent));
      case _Step.consent:
        return ConsentPanel(onBack: () => _go(_Step.goal), onDone: () => _go(_Step.notify));
      case _Step.notify:
        return NotifyStep(
          onBack: () => _go(_Step.consent),
          onDone: () {
            if (_obs) {
              store.startObservation();
              return;
            }
            // 처음 고른 목표를 바로 설정 화면의 기본값으로
            final i = store.state.intent;
            if (i != null) {
              final ex = i.focus.contains(GoalFocus.exercise) ? (_goals.exercise ?? defaultGoals.exercise!).copyWith(minutes: i.exerciseMinutes) : _goals.exercise;
              _goals = HabitGoals(wake: ClockTime(i.wake), sleepMinutes: i.sleepMinutes, meals: _goals.meals, exercise: ex);
            }
            _go(_Step.set1);
          },
        );
      case _Step.hero:
        return _hero(context);
      case _Step.set1:
        return _set1(context);
      case _Step.set2:
        return _set2(context);
    }
  }

  Widget _hero(BuildContext context) {
    final c = context.ds;
    const items = [
      (DsIcons.sun, '바꾸고 싶은 것(기상·수면·아침·운동·할 일)만 골라요'),
      (DsIcons.check, "첫날은 '지금' 버튼으로 하루를 그대로 기록해요"),
      (DsIcons.calendar, '저녁에 기록한 하루를 보고 바꾸고 싶은 시각만 고쳐요'),
      (DsIcons.bell, '다음 날부터 일정과 알람을 매일 자동으로 짜요'),
    ];
    return StepPage(
      top: 48,
      children: [
        const Align(alignment: Alignment.centerLeft, child: Pill('DaySet')),
        Semantics(header: true, child: Text('자동으로 짜주는 일정으로\n편하게 생활습관 잡기', style: DsText.hero.copyWith(color: c.ink))),
        DsCard(gap: 14, children: [
          for (final (icon, text) in items)
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.tint, shape: BoxShape.circle),
                child: Center(child: DsIcon(icon, size: 18, color: c.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(child: bodyText(context, text)),
            ]),
        ]),
        const LabelText('기록은 이 기기에만 저장되고 서버로 보내지 않아요.'),
      ],
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DsButton.primary('시작하기 · 목표만 고르고 기록부터', block: true, onPressed: () {
          _obs = true;
          _go(_Step.goal);
        }),
        const SizedBox(height: 10),
        DsButton('예시 데이터로 둘러보기', block: true, onPressed: () {
          final store = context.store;
          store.loadDemo(demoState(store.now()));
          store.ensureDay();
        }),
        const SizedBox(height: 10),
        Center(
          child: DsButton('기록 없이 바로 설정하기', kind: BtnKind.ghost, small: true, onPressed: () {
            _obs = false;
            _go(_Step.goal);
          }),
        ),
      ]),
    );
  }

  Widget _set1(BuildContext context) {
    final g = _goals;
    final gap = (_usual - g.wake.minutes).abs();
    final weeks = (gap / 30).ceil();
    return StepPage(
      children: [
        const StepHead(step: '1 / 2', title: '언제 일어나고 싶어요?'),
        DsCard(gap: 14, children: [
          TimeField(label: '목표 기상 시각', value: g.wake.minutes, onChanged: (v) => setState(() => _goals = g.copyWith(wake: ClockTime(v)))),
          TimeField(label: '지금 보통 일어나는 시각', value: _usual, onChanged: (v) => setState(() => _usual = v)),
          HoursField(label: '목표 수면 시간', minutes: g.sleepMinutes, onChanged: (v) => setState(() => _goals = g.copyWith(sleepMinutes: v))),
        ]),
        DsCard(tint: true, children: [
          gap > 30
              ? richBody(context,
                  '지금보다 $gap분 ${_usual > g.wake.minutes ? '일찍' : '늦게'} 일어나야 해요. 한 번에 바꾸지 않고 **$weeks주**에 걸쳐 매주 30분씩 옮겨요. 이번 주 기상 목표는 **${formatClock(_usual)}**이에요.')
              : bodyText(context, '지금 기상 시각과 가까워서 바로 ${formatClock(g.wake.minutes)} 알람으로 시작해요.'),
        ]),
      ],
      footer: BackNextRow(onBack: () => _go(_Step.notify), nextLabel: '다음', onNext: () => _go(_Step.set2)),
    );
  }

  Widget _set2(BuildContext context) {
    final g = _goals;
    final ex = g.exercise;
    return StepPage(
      children: [
        const StepHead(step: '2 / 2', title: '식사·운동 시간을 알려 주세요', desc: '매일 일정의 뼈대가 돼요. 회의와 겹치면 2시간 안에서 자동으로 옮겨요.'),
        DsCard(gap: 14, children: [
          for (var i = 0; i < g.meals.length; i++)
            TimeField(
              label: g.meals[i].title,
              value: g.meals[i].start.minutes,
              onChanged: (v) => setState(() => _goals = g.copyWith(meals: [
                    for (var j = 0; j < g.meals.length; j++) j == i ? g.meals[j].copyWith(start: ClockTime(v)) : g.meals[j],
                  ])),
            ),
          DsSwitch(
            value: ex != null,
            onChanged: (v) => setState(() => _goals = v ? g.copyWith(exercise: defaultGoals.exercise) : g.copyWith(clearExercise: true)),
            label: '운동도 넣기',
            onText: '넣기',
            offText: '빼기',
          ),
          if (ex != null)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: TimeField(label: '운동 시각', value: ex.start.minutes, onChanged: (v) => setState(() => _goals = g.copyWith(exercise: ex.copyWith(start: ClockTime(v)))))),
              const SizedBox(width: 10),
              Expanded(
                child: NumberField(label: '운동 시간', value: ex.minutes, min: 5, max: 180, onChanged: (v) => setState(() => _goals = g.copyWith(exercise: ex.copyWith(minutes: v)))),
              ),
            ]),
        ]),
        DsCard(gap: 14, children: [
          Text('아침 준비와 이동', style: DsText.body.copyWith(fontWeight: FontWeight.w600, color: context.ds.ink)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: NumberField(label: '아침 준비', value: _prep, onChanged: (v) => setState(() => _prep = v))),
            const SizedBox(width: 10),
            Expanded(child: NumberField(label: '이동', value: _travel, onChanged: (v) => setState(() => _travel = v))),
          ]),
        ]),
      ],
      footer: BackNextRow(
        onBack: () => _go(_Step.set1),
        nextLabel: '시작하기',
        onNext: () => context.store.completeOnboarding(
          goals: _goals,
          settings: const PersonalSettings().copyWith(prepMinutes: _prep, travelMinutes: _travel),
          usualWake: _usual,
        ),
      ),
    );
  }
}
