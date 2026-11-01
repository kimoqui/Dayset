// 앱 셸: 테마, 탭 6개(밀어서 이동), 밀려 들어오는 화면, 알림 띠, 일정 체크 띠, 알람 화면, 관찰 안내, 기념일 축하.
// 웹 버전 src/ui/App.tsx와 같은 흐름이다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/derive.dart';
import '../app/now_check.dart';
import '../app/state.dart';
import '../app/store.dart';
import '../app/streak.dart';
import '../core/model/models.dart';
import '../platform/widget_bridge.dart';
import 'alarm_overlay.dart';
import 'kit.dart';
import 'now_dock.dart';
import 'obs_popup.dart';
import 'preview.dart';
import 'scope.dart';
import 'screens/demo.dart';
import 'screens/evening.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'screens/review.dart';
import 'screens/schedule.dart';
import 'screens/settings.dart';
import 'screens/social_tab.dart';
import 'screens/stats.dart';
import 'screens/tasks.dart';
import 'social.dart';
import 'theme.dart';

const _themeKey = 'dayset:theme';

class DaySetApp extends StatefulWidget {
  const DaySetApp({super.key, required this.store, this.bridge});
  final Store store;

  /// 홈 화면 위젯 연결(없으면 위젯 없이 동작).
  final WidgetBridge? bridge;

  @override
  State<DaySetApp> createState() => _DaySetAppState();
}

class _DaySetAppState extends State<DaySetApp> {
  late final StoreNotifier _notifier = StoreNotifier(widget.store);
  late ThemePref _theme = ThemePref.values.where((t) => t.name == widget.store.storage.kv.read(_themeKey)).firstOrNull ?? ThemePref.dark;
  final _nav = GlobalKey<NavigatorState>();

  void _setTheme(ThemePref t) {
    setState(() => _theme = t);
    widget.store.storage.kv.write(_themeKey, t.name);
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      notifier: _notifier,
      child: MaterialApp(
        title: 'DaySet',
        debugShowCheckedModeBanner: false,
        // 날짜·시각 고르기 창을 한국어로
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: _nav,
        theme: buildTheme(DsColors.light),
        darkTheme: buildTheme(DsColors.night),
        themeMode: switch (_theme) { ThemePref.dark => ThemeMode.dark, ThemePref.light => ThemeMode.light, ThemePref.system => ThemeMode.system },
        builder: (context, child) => _Shell(nav: _nav, theme: _theme, setTheme: _setTheme, bridge: widget.bridge, child: child!),
        home: const _Root(),
      ),
    );
  }
}

/// 처음 화면: 동의가 없으면 동의, 시작 전이면 처음 설정, 아니면 탭.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final c = context.ds;
    Widget body;
    if (s.onboarded && !s.demo && !(s.consent?.health ?? false)) {
      // 동의 없이 쓰던 기록(이전 버전)이면 먼저 동의를 받는다. 예시 데이터는 묻지 않는다.
      body = ConsentPanel(title: '계속 쓰려면 동의가 필요해요', onDone: () => context.toast('동의를 남겼어요'));
    } else if (!s.onboarded) {
      final broken = context.store.loadIssue == KeptReason.broken;
      body = Column(children: [
        if (broken)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DsBanner('저장된 기록을 읽지 못해 새로 시작했어요. 이전 데이터는 지우지 않고 보관했어요(시작한 뒤 설정 → 데이터에서 내려받기).'),
          ),
        const Expanded(child: OnboardingScreen()),
      ]);
    } else {
      return const _Tabs();
    }
    return Scaffold(backgroundColor: c.bg, body: SafeArea(child: body));
  }
}

// ---------------------------------------------------------------------------
// 셸: 시각·알림 띠·알람·팝업. 내비게이터 위에 있어 밀려 들어온 화면에서도 쓴다.
// ---------------------------------------------------------------------------

class _Shell extends StatefulWidget {
  const _Shell({required this.nav, required this.theme, required this.setTheme, required this.bridge, required this.child});
  final GlobalKey<NavigatorState> nav;
  final ThemePref theme;
  final ValueChanged<ThemePref> setTheme;
  final WidgetBridge? bridge;
  final Widget child;

  @override
  State<_Shell> createState() => _ShellState();
}

class _Toast {
  _Toast(this.text, this.undo, this.id);
  final String text;
  final UndoKind undo;
  final int id;
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver implements ShellActions {
  /// 저장소는 바뀌지 않으므로 처음 한 번 잡아 둔다(dispose에서 context를 쓰지 않도록).
  late final Store store = StoreScope.read(context);

  late DateTime _now;
  Timer? _tick;
  Timer? _toastTimer;
  _Toast? _toast;
  ({Ring ring, bool test})? _ring;
  bool _popup = false;
  bool _celebrating = false;
  int _pushed = 0;
  StreakInfo? _streak;
  AppState? _streakFor;
  DateTime? _streakAt;
  String? _publishedCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _now = store.now();
      store.addListener(_onState);
      _pullWidgetTaps();
      _refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    store; // 여기서 잡아 둔다
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onState);
    _tick?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pullWidgetTaps();
      _refresh();
    }
  }

  /// 위젯·단축어에서 누른 기록을 가져와 반영한다.
  Future<void> _pullWidgetTaps() async {
    final b = widget.bridge;
    if (b == null) return;
    try {
      final events = await b.takePendingEvents();
      if (!mounted) return;
      final n = store.applyExternalTaps(events);
      if (n > 0) toast('위젯에서 누른 기록 $n개를 반영했어요');
    } catch (_) {
      // 위젯을 설정하기 전(앱 그룹 없음)에도 앱은 동작한다.
    }
  }

  /// 상태가 바뀌면 지금 시각을 다시 재고, 위젯에 지금 상태를 알린다.
  void _onState() {
    if (!mounted) return;
    setState(() => _now = store.now());
    final cur = currentLog(store.state);
    final sig = cur == null ? '' : '${cur.activity.name}@${cur.start.millisecondsSinceEpoch}';
    if (sig != _publishedCurrent) {
      _publishedCurrent = sig;
      widget.bridge?.publishCurrent(cur).catchError((_) {});
    }
    _check();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _now = store.now());
    _check();
  }

  /// 하루 시작 처리, 알람·알림, 관찰 안내, 기념일.
  void _check() {
    final s = store.state;
    if (!s.onboarded) return;
    final t = _now;
    store.markOpen(t);
    store.ensureDay(t);
    if (_ring == null) {
      final due = store.dueAlarms(t);
      if (due.ring != null) setState(() => _ring = (ring: due.ring!, test: false));
      if (due.nudges.isNotEmpty) {
        final n = due.nudges.first;
        toast('${n.title} · ${n.body}');
        store.markNudged([for (final x in due.nudges) x.key]);
      }
    }
    if (_ring != null || _popup || _celebrating) return;

    // 관찰 준비일(1일차 전날) 안내: 처음 한 번, 밤 10시가 넘으면 한 번 더.
    final obs = s.observation;
    if (obs != null && obs.phase == ObservationPhase.recording && dateKey(t).compareTo(obs.day1) < 0) {
      final introAt = s.asked.obsIntroAt;
      if (introAt == null) {
        store.markAsked((a) => a.copyWith(obsIntroAt: t));
        _openPopup(ObsPopupKind.intro);
        return;
      }
      final late = t.hour >= 22 || t.hour < 3;
      if (late && !s.asked.obsLate && t.difference(introAt).inMinutes >= 30 && currentLog(s)?.activity != Activity.sleep) {
        store.markAsked((a) => a.copyWith(obsLate: true));
        _openPopup(ObsPopupKind.late);
        return;
      }
    }

    // 기념일(3·7·14·30일…) 축하: 그날 처음 도달했을 때 한 번
    final info = _streakInfo(s, t);
    final hit = info == null ? null : reachedMilestone(info, dateKey(t), s.asked.celebrated);
    if (hit != null) {
      store.markAsked((a) => a.copyWith(celebrated: '$hit@${dateKey(t)}'));
      haptic(20);
      final ctx = widget.nav.currentContext;
      if (ctx != null) {
        _celebrating = true;
        showCelebrate(ctx, info!, hit).whenComplete(() => _celebrating = false);
      }
    }
  }

  StreakInfo? _streakInfo(AppState s, DateTime t) {
    if (!s.onboarded) return null;
    if (!identical(_streakFor, s) || _streakAt != t) {
      _streak = computeStreak(s, t);
      _streakFor = s;
      _streakAt = t;
    }
    return _streak;
  }

  void _openPopup(ObsPopupKind kind) {
    final ctx = widget.nav.currentContext;
    if (ctx == null) return;
    _popup = true;
    showObsPopup(ctx, kind, onSleep: () => tapNow(Activity.sleep)).whenComplete(() => _popup = false);
  }

  bool get _dark => switch (widget.theme) {
        ThemePref.dark => true,
        ThemePref.light => false,
        ThemePref.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      };

  // ---- ShellActions ----

  @override
  void toast(String text, {UndoKind undo = UndoKind.none}) {
    _toastTimer?.cancel();
    setState(() => _toast = _Toast(text, undo, DateTime.now().microsecondsSinceEpoch));
    _toastTimer = Timer(Duration(milliseconds: switch (undo) { UndoKind.plan => 6500, UndoKind.tap => 5000, UndoKind.none => 4000 }), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void open(AppPage page) {
    if (page.isTab) {
      while (_pushed > 0 && (widget.nav.currentState?.canPop() ?? false)) {
        widget.nav.currentState!.pop();
        _pushed--;
      }
      _Tabs.go?.call(page);
      return;
    }
    final Widget screen = switch (page) {
      AppPage.evening => EveningScreen(key: ValueKey(dateKey(_now))),
      AppPage.review => const ReviewScreen(),
      AppPage.demo => const DemoScreen(),
      _ => const SizedBox(),
    };
    _pushed++;
    widget.nav.currentState?.push(_PushRoute(screen)).whenComplete(() {
      if (_pushed > 0) _pushed--;
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  void back() => widget.nav.currentState?.maybePop();

  @override
  void setTheme(ThemePref t) => widget.setTheme(t);

  @override
  void toggleTheme() => widget.setTheme(_dark ? ThemePref.light : ThemePref.dark);

  @override
  void testRing() => setState(() => _ring = (ring: Ring(kind: RingKind.wake, key: 'test', at: store.now()), test: true));

  @override
  void showGuide() => _openPopup(ObsPopupKind.intro);

  @override
  void tapNow(Activity a) {
    final r = store.tap(a);
    if (!r.changed) return;
    haptic(10);
    toast(r.merged ? '${a.label} 기록에 이어 붙였어요' : '${a.label} 시작을 기록했어요', undo: UndoKind.tap);
  }

  @override
  void recordFrom(Activity a, {required String via}) {
    final r = store.tap(a);
    haptic(12);
    store.track(via == 'popup' ? 'check_record' : 'notify_record', a.name);
    toast(r.changed ? '${a.label} 시작을 기록했어요' : '이미 ${a.label} 기록 중이에요', undo: r.changed ? UndoKind.tap : UndoKind.none);
  }

  void _undo() {
    final t = _toast;
    if (t == null) return;
    final ok = t.undo == UndoKind.plan ? store.canUndoPlan() && store.undoPlanChange() : store.canUndo() && store.undoTap();
    if (ok) {
      toast('되돌렸어요');
    } else {
      setState(() => _toast = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.watch(context);
    final info = _streakInfo(s, _now);
    final onTabs = _pushed == 0 && s.onboarded;
    final media = MediaQuery.of(context);
    final c = _dark ? DsColors.night : DsColors.light;
    final t = _toast;
    return UiScope(
      now: _now,
      streak: info,
      theme: widget.theme,
      dark: _dark,
      actions: this,
      child: Stack(children: [
        widget.child,
        if (t != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + (onTabs ? 86 + dockHeight.value : 24),
            child: _ToastView(key: ValueKey(t.id), text: t.text, undo: t.undo != UndoKind.none ? _undo : null, colors: c),
          ),
        if (_ring != null)
          Positioned.fill(
            child: Theme(
              data: buildTheme(c),
              child: AlarmOverlay(ring: _ring!.ring, test: _ring!.test, onDone: () => setState(() => _ring = null)),
            ),
          ),
      ]),
    );
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.text, required this.undo, required this.colors});
  final String text;
  final VoidCallback? undo;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child)),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 398),
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineStrong),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Row(children: [
              Expanded(child: Text(text, style: TextStyle(fontFamily: 'Pretendard', fontSize: 14, height: 20 / 14, color: c.ink))),
              if (undo != null)
                GestureDetector(
                  onTap: undo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text('되돌리기', style: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w700, color: c.accentStrong)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 밀려 들어오는 화면(저녁 확인·내 하루 보기·시연).
class _PushRoute extends PageRouteBuilder<void> {
  _PushRoute(Widget screen)
      : super(
          transitionDuration: const Duration(milliseconds: 360),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, a, b) => Scaffold(backgroundColor: context.ds.bg, body: SafeArea(child: screen)),
          transitionsBuilder: (context, a, b, child) {
            final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
            if (reduce) return child;
            final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            return SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curve), child: child);
          },
        );
}

// ---------------------------------------------------------------------------
// 탭 6개 + 일정 체크 띠 + 아래 탭 막대
// ---------------------------------------------------------------------------

class _Tabs extends StatefulWidget {
  const _Tabs();

  /// 셸에서 탭을 바꿀 때 쓴다(화면이 하나뿐이라 정적으로 둔다).
  static void Function(AppPage page)? go;


  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  final _pages = PageController();
  int _index = 0;
  final _dockKey = GlobalKey();

  static const _icons = [DsIcons.home, DsIcons.calendar, DsIcons.tasks, DsIcons.stats, DsIcons.users, DsIcons.settings];

  @override
  void initState() {
    super.initState();
    _Tabs.go = _go;
  }

  @override
  void dispose() {
    if (_Tabs.go == _go) _Tabs.go = null;
    _pages.dispose();
    super.dispose();
  }

  void _go(AppPage p) {
    final i = AppPage.tabs.indexOf(p);
    if (i < 0) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || (i - _index).abs() > 1) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  void _measureDock() {
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.hasSize == true ? box!.size.height + 8 : 0.0;
    if (dockHeight.value != h) dockHeight.value = h;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = context.app;
    final ui = context.ui;
    final check = nowCheck(s, ui.now);
    final showDock = check.kind != CheckKind.none;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureDock());
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          PageView(
            controller: _pages,
            onPageChanged: (i) {
              haptic(6);
              setState(() => _index = i);
            },
            children: const [
              _KeepAlive(HomeScreen()),
              _KeepAlive(ScheduleScreen()),
              _KeepAlive(TasksScreen()),
              _KeepAlive(StatsScreen()),
              _KeepAlive(SocialScreen()),
              _KeepAlive(SettingsScreen()),
            ],
          ),
          if (showDock)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: KeyedSubtree(
                key: _dockKey,
                child: NowDock(check: check, onRecord: (a) => ui.actions.recordFrom(a, via: 'popup'), onSkip: context.store.skipCheck),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: c.nav, border: Border(top: BorderSide(color: c.line))),
        padding: EdgeInsets.fromLTRB(4, 6, 4, 8 + MediaQuery.paddingOf(context).bottom),
        child: Row(children: [
          for (var i = 0; i < AppPage.tabs.length; i++)
            Expanded(
              child: Semantics(
                selected: i == _index,
                button: true,
                label: AppPage.tabs[i].label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _go(AppPage.tabs[i]),
                  child: SizedBox(
                    height: 56,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedScale(
                        scale: i == _index ? 1.08 : 1,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        child: DsIcon(_icons[i], size: 22, color: i == _index ? c.accentStrong : c.muted),
                      ),
                      const SizedBox(height: 3),
                      Text(AppPage.tabs[i].label,
                          style: TextStyle(fontSize: 10.5, fontWeight: i == _index ? FontWeight.w700 : FontWeight.w500, color: i == _index ? c.accentStrong : c.muted)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// 탭을 옮겨도 스크롤 위치·입력 상태를 지킨다.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
