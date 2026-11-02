import 'package:home_widget/home_widget.dart';

import '../core/model/models.dart';
import 'widget_events.dart';

/// 앱 ↔ 홈 화면 위젯 연결(기술 검증 1번).
///
/// 위젯 버튼은 앱을 열지 않고 네이티브 코드로 공유 저장소에 탭을 쌓는다.
/// 앱은 켜지거나 앞으로 올 때 [takePendingEvents]로 가져가 기록에 반영하고,
/// 현재 상태를 [publishCurrent]로 위젯에 다시 알려준다.
class WidgetBridge {
  static const appGroupId = 'group.com.dayset.dayset';
  static const iOSWidgetKind = 'NowWidget';
  static const androidProvider = 'com.dayset.dayset.NowWidgetProvider';

  static const keyPending = 'pending_events';
  static const keyCurrent = 'current_activity';
  static const keySince = 'current_since';
  static const keyLine = 'widget_line';

  Future<void> init() => HomeWidget.setAppGroupId(appGroupId);

  /// 쌓인 탭을 읽고 비운다.
  ///
  /// 기술 검증 단계의 단순한 방식이다. 읽기와 비우기 사이에 위젯 탭이 들어오면
  /// 하나를 놓칠 수 있으므로, 본개발에서는 네이티브 쪽에서 '가져간 시각'을
  /// 기준으로 지우는 방식으로 바꾼다.
  Future<List<({Activity activity, DateTime at})>> takePendingEvents() async {
    final raw = await HomeWidget.getWidgetData<String>(keyPending);
    final events = parsePendingEvents(raw);
    if (raw != null && raw != '[]') {
      await HomeWidget.saveWidgetData<String>(keyPending, '[]');
    }
    return events;
  }

  /// 지금 상태와 둘째 줄(다음 일정·오늘 진행도)을 위젯에 알린다.
  Future<void> publishCurrent(ActivityLog? current, {String line = ''}) async {
    await HomeWidget.saveWidgetData<String>(keyLine, line);
    await HomeWidget.saveWidgetData<String>(keyCurrent, current?.activity.name ?? '');
    await HomeWidget.saveWidgetData<String>(
        keySince, current?.start.toIso8601String() ?? '');
    await HomeWidget.updateWidget(
      iOSName: iOSWidgetKind,
      qualifiedAndroidName: androidProvider,
    );
  }
}
