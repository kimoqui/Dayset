// 화면이 상태와 셸(탭 이동·알림 띠·테마)에 닿는 길.
//
//   context.store  : 동작을 부르는 저장소(듣지 않음)
//   context.app    : 지금 상태(바뀌면 다시 그린다)
//   context.ui     : 지금 시각, 연속 기록, 알림 띠, 화면 이동, 테마

import 'package:flutter/widgets.dart';

import '../app/state.dart';
import '../app/store.dart';
import '../app/streak.dart';
import '../core/model/models.dart';

/// 저장소가 바뀌면 화면에 알린다.
class StoreNotifier extends ChangeNotifier {
  StoreNotifier(this.store) {
    store.addListener(notifyListeners);
  }
  final Store store;

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    super.dispose();
  }
}

class StoreScope extends InheritedNotifier<StoreNotifier> {
  const StoreScope({super.key, required StoreNotifier notifier, required super.child}) : super(notifier: notifier);

  static Store read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!.store;
  static AppState watch(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!.store.state;
}

/// 알림 띠의 되돌리기: 없음, '지금' 기록 되돌리기(5초), 할 일·캘린더 변경 되돌리기(15초).
enum UndoKind { none, tap, plan }

/// 탭 화면과 위로 밀려 들어오는 화면.
enum AppPage {
  home('홈'),
  schedule('일정'),
  tasks('할 일'),
  stats('기록'),
  social('소셜'),
  settings('설정'),
  evening('저녁 확인'),
  review('내 하루 보기'),
  demo('시연');

  const AppPage(this.label);
  final String label;

  bool get isTab => index <= AppPage.settings.index;
  static const tabs = [home, schedule, tasks, stats, social, settings];
}

/// 테마: 나이트(기본), 밝게, 파스텔 다이어리, 기기 설정 따르기.
enum ThemePref {
  dark('나이트'),
  light('밝게'),
  pastel('파스텔'),
  system('기기 설정');

  const ThemePref(this.label);
  final String label;
}

/// 관찰 안내 팝업 종류.
enum ObsPopupKind { intro, late }

/// 셸이 화면에 열어 주는 동작.
abstract class ShellActions {
  void toast(String text, {UndoKind undo = UndoKind.none});

  /// 탭이면 그 탭으로, 아니면 위로 밀려 들어오는 화면으로 연다.
  void open(AppPage page);

  /// 밀려 들어온 화면을 닫는다.
  void back();
  void setTheme(ThemePref t);

  /// 지금 보이는 테마의 반대로 바꾼다(홈의 해·달 단추).
  void toggleTheme();

  /// 설정의 '알람 미리 보기'.
  void testRing();

  /// 관찰 안내 팝업을 다시 보여 준다.
  void showGuide();

  /// 홈의 '지금' 버튼.
  void tapNow(Activity a);

  /// 일정 체크 팝업·알림 버튼에서 기록. [at]이 있으면 그 시각부터(제때 누르지 못했을 때).
  void recordFrom(Activity a, {required String via, DateTime? at});
}

class UiScope extends InheritedWidget {
  const UiScope({super.key, required this.now, required this.streak, required this.theme, required this.dark, required this.actions, required super.child});

  /// 화면이 켜져 있는 동안 15초마다, 상태가 바뀔 때마다 새로 잰 시각.
  final DateTime now;
  final StreakInfo? streak;
  final ThemePref theme;

  /// 지금 보이는 테마가 어두운지.
  final bool dark;
  final ShellActions actions;

  static UiScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<UiScope>()!;

  @override
  bool updateShouldNotify(UiScope old) => old.now != now || old.streak != streak || old.theme != theme || old.dark != dark;
}

extension ScopeX on BuildContext {
  Store get store => StoreScope.read(this);
  AppState get app => StoreScope.watch(this);
  UiScope get ui => UiScope.of(this);
  void toast(String text, {UndoKind undo = UndoKind.none}) => UiScope.of(this).actions.toast(text, undo: undo);
}

/// 할 일·캘린더를 바꾼 뒤 알림: 일정이 바뀌었으면 그렇다고 말하고 되돌리기를 준다.
/// 빈 시간이 모자라 밀려난 일이 있으면 숨기지 않고 알린다.
void notifyPlan(BuildContext context, PlanChange r, String changed, [String? unchanged]) {
  final base = r.replanned ? changed : (unchanged ?? changed);
  final d = r.deferred;
  final late = d.isEmpty ? '' : ' · 빈 시간이 부족해 ${d.take(2).join(', ')}${d.length > 2 ? ' 외 ${d.length - 2}개' : ''}는 다음 날로 넘겼어요';
  context.toast(base + late, undo: UndoKind.plan);
}

/// 탭 화면 아래에 떠 있는 일정 체크 띠의 높이(셸이 잰다). 화면 아래 여백과 알림 띠 위치에 쓴다.
final dockHeight = ValueNotifier<double>(0);

/// 화면 한 장(탭·밀려 들어오는 화면 공통): 위아래 여백과 스크롤.
/// 탭 화면([tab] = true)은 일정 체크 띠에 가리지 않도록 그 높이만큼 더 띄운다.
class ScreenList extends StatelessWidget {
  const ScreenList({super.key, required this.children, this.tab = true, this.controller});
  final List<Widget> children;
  final bool tab;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: dockHeight,
        builder: (context, dock, _) => ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + (tab ? dock : 0)),
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
          ],
        ),
      );
}
