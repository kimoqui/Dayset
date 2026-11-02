// 휴대폰 알림·알람 연결(2·3단계). 무엇을 맡길지는 lib/app/device_plan.dart가 정하고,
// 여기서는 그 목록대로 기기 예약을 맞춘다.
//
// - 알림(flutter_local_notifications)
//   · 지금 일정 알림(번호 1): 앱이 켜져 있는 동안 지금 일정·기록할 때를 보여 준다. '기록하기'·'지금은 안 해요' 버튼.
//   · 일정 시작 알림(예약): 앱이 꺼져 있어도 일정이 시작하면 같은 버튼이 달린 알림이 뜬다.
//   · 버튼을 누르면 앱이 열리고 셸이 기록한다(늦게 누르면 일정 시각부터, 웹 일정 체크와 같은 규칙).
// - 알람(alarm 패키지): 앱이 꺼져 있어도 기상·취침 시각에 울린다(안드로이드 AlarmManager setAlarmClock).
//   · 앱에서 끄기 = 기상 기록. 알림의 '끄기'로 껐으면 앱을 열 때 알람 화면이 이어서 기록을 받는다.
//   · 다시 울림·끄기·일정 변경은 상태에 남고, 상태가 바뀌면 기기 예약을 다시 맞춘다.
//
// 기기 기능을 쓸 수 없는 곳(테스트·데스크톱)에서는 아무것도 하지 않는다.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app/device_plan.dart';
import '../app/now_check.dart';
import '../app/store.dart';
import '../core/model/models.dart';
import 'notify.dart';

/// 알림 버튼을 눌렀을 때 셸에 건네는 것.
class NoticeAction {
  const NoticeAction({required this.action, this.activity, this.blockStart, this.skipId, this.open});

  /// 'record' | 'skip' | 'open'
  final String action;
  final Activity? activity;
  final DateTime? blockStart;
  final String? skipId;

  /// 알림을 눌렀을 때 열 화면('evening').
  final String? open;

  static NoticeAction? parse(String? actionId, String? payload) {
    Map<String, Object?> p = const {};
    try {
      if (payload != null && payload.isNotEmpty) p = (jsonDecode(payload) as Map).cast<String, Object?>();
    } catch (_) {}
    final a = Activity.values.where((x) => x.name == p['a']).firstOrNull;
    final s = p['s'] is num ? DateTime.fromMillisecondsSinceEpoch((p['s'] as num).toInt()) : null;
    return NoticeAction(action: actionId ?? 'open', activity: a, blockStart: s, skipId: p['k'] as String?, open: p['o'] as String?);
  }
}

String _payload(DeviceNotice n) => jsonEncode({
      if (n.activity != null) 'a': n.activity!.name,
      if (n.blockStart != null) 's': n.blockStart!.millisecondsSinceEpoch,
      if (n.skipId != null) 'k': n.skipId,
      if (n.open != null) 'o': n.open,
    });

/// 버튼만 누르고 앱을 열지 않는 경우는 없지만(버튼은 모두 앱을 연다), 플러그인이 요구하는 빈 처리기.
@pragma('vm:entry-point')
void noticeBackgroundTap(NotificationResponse r) {}

const _nowId = 1;

class DeviceSync implements NotifyPort {
  DeviceSync(this.store);
  final Store store;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _actions = StreamController<NoticeAction>.broadcast();
  final _rang = StreamController<void>.broadcast();
  bool _ready = false;
  NoticeAction? _launch;
  Timer? _debounce;
  Timer? _tick;
  String _nowKey = '';
  String _scheduleKey = '';
  Map<int, DateTime> _scheduled = {};
  final Set<int> _expectStop = {};
  Set<int> _ringing = {};

  /// 알림 버튼이 눌렸을 때(앱이 켜져 있을 때).
  Stream<NoticeAction> get actions => _actions.stream;

  /// 기기 알람이 울리기 시작했을 때(앱이 켜져 있으면 알람 화면을 바로 띄운다).
  Stream<void> get rang => _rang.stream;

  static bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_mobile) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          final a = NoticeAction.parse(r.actionId, r.payload);
          if (a != null) _actions.add(a);
        },
        onDidReceiveBackgroundNotificationResponse: noticeBackgroundTap,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && r != null) _launch = NoticeAction.parse(r.actionId, r.payload);
      _ready = true;
    } catch (e) {
      debugPrint('알림 준비 실패: $e');
    }
    try {
      await Alarm.init();
      Alarm.ringing.listen(_onRinging);
    } catch (e) {
      debugPrint('알람 준비 실패: $e');
    }
    store.addListener(_onStore);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _applyNow());
    unawaited(apply());
  }

  /// 알림 버튼으로 앱이 열렸으면 그 버튼(한 번만 돌려준다).
  NoticeAction? takeLaunchAction() {
    final a = _launch;
    _launch = null;
    return a;
  }

  void dispose() {
    _debounce?.cancel();
    _tick?.cancel();
    store.removeListener(_onStore);
  }

  void _onStore() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(apply()));
  }

  /// 상태대로 기기 알림·알람을 맞춘다.
  Future<void> apply() async {
    await _applyAlarms();
    await _applySchedule();
    await _applyNow();
  }

  // ---------------------------------------------------------------- 알림

  @override
  bool get available => _mobile && _ready;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> request() async {
    if (!available) return false;
    if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? false;
    return await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
  }

  @override
  Future<bool> granted() async {
    if (!available) return false;
    if (Platform.isAndroid) return await _android?.areNotificationsEnabled() ?? false;
    return store.state.notify.enabled;
  }

  NotificationDetails _details(DeviceNotice n, {required bool ongoing, required bool alert}) {
    final actions = n.activity == null
        ? null
        : const [
            AndroidNotificationAction('record', '기록하기', showsUserInterface: true),
            AndroidNotificationAction('skip', '지금은 안 해요', showsUserInterface: true),
          ];
    final timeout = n.until == null ? null : n.until!.difference(DateTime.now()).inMilliseconds;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        alert ? 'dayset_check' : 'dayset_now',
        alert ? '일정 체크' : '지금 일정',
        channelDescription: alert ? '일정이 시작했는데 기록이 없을 때 알려요' : '지금 일정과 다음 일정을 띄워 둬요',
        importance: alert ? Importance.high : Importance.low,
        priority: alert ? Priority.high : Priority.low,
        category: AndroidNotificationCategory.reminder,
        ongoing: ongoing,
        autoCancel: !ongoing,
        onlyAlertOnce: true,
        silent: !alert || n.silent,
        timeoutAfter: timeout != null && timeout > 0 ? timeout : null,
        actions: actions,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: alert && !n.silent),
    );
  }

  /// 지금 일정 알림(번호 1). 웹 App.tsx의 '지금 일정' 알림과 같은 규칙.
  Future<void> _applyNow() async {
    if (!available) return;
    final s = store.state;
    final check = nowCheck(s, store.now());
    final alertNow = (check.kind == CheckKind.due || check.kind == CheckKind.over) && !check.skipped;
    final n = s.notify.enabled ? nowNotice(check) : null;
    final key = '${check.key}|${check.skipped}|${check.current?.name}|${s.notify.enabled}|${s.notify.sticky}|${s.notify.remind}';
    if (key == _nowKey) return;
    _nowKey = key;
    try {
      if (n == null || (alertNow ? !s.notify.remind && !s.notify.sticky : !s.notify.sticky)) {
        await _plugin.cancel(id: _nowId);
        return;
      }
      // 이미 울린 일정 시작 알림은 거두고 지금 일정 알림 하나만 남긴다.
      final now = store.now();
      for (final e in _scheduled.entries.where((e) => !e.value.isAfter(now)).toList()) {
        await _plugin.cancel(id: e.key);
        _scheduled.remove(e.key);
      }
      final alert = alertNow && s.notify.remind;
      await _plugin.show(id: _nowId, title: n.title, body: n.body, notificationDetails: _details(n, ongoing: s.notify.sticky || alertNow, alert: alert), payload: _payload(n));
    } catch (e) {
      debugPrint('지금 일정 알림 실패: $e');
    }
  }

  /// 일정 시작 알림 예약(앱이 꺼져 있어도 뜬다).
  Future<void> _applySchedule() async {
    if (!available) return;
    final list = scheduledNotices(store.state, store.now());
    final key = list.map((x) => '${x.id}@${x.at.millisecondsSinceEpoch}:${x.notice.signature}').join(',');
    if (key == _scheduleKey) return;
    _scheduleKey = key;
    try {
      await _plugin.cancelAllPendingNotifications();
      var mode = AndroidScheduleMode.inexactAllowWhileIdle;
      if (!kIsWeb && Platform.isAndroid && (await _android?.canScheduleExactNotifications() ?? false)) mode = AndroidScheduleMode.exactAllowWhileIdle;
      final next = <int, DateTime>{};
      for (final x in list) {
        await _plugin.zonedSchedule(
          id: x.id,
          scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, x.at.millisecondsSinceEpoch),
          notificationDetails: _details(x.notice, ongoing: false, alert: true),
          androidScheduleMode: mode,
          title: x.notice.title,
          body: x.notice.body,
          payload: _payload(x.notice),
        );
        next[x.id] = x.at;
      }
      _scheduled = next;
    } catch (e) {
      _scheduleKey = '';
      debugPrint('일정 알림 예약 실패: $e');
    }
  }

  // ---------------------------------------------------------------- 알람

  Future<void> _applyAlarms() async {
    if (!_mobile) return;
    final want = deviceAlarms(store.state, store.now());
    try {
      final have = {for (final a in await Alarm.getAlarms()) a.id: a};
      for (final id in have.keys) {
        if (want.any((w) => w.id == id)) continue;
        _expectStop.add(id);
        await Alarm.stop(id);
      }
      for (final w in want) {
        final cur = have[w.id];
        if (cur != null && cur.dateTime.isAtSameMomentAs(w.at)) continue;
        if (cur != null) _expectStop.add(w.id);
        await Alarm.set(
          alarmSettings: AlarmSettings(
            id: w.id,
            dateTime: w.at,
            assetAudioPath: null, // 기기 기본 알람 소리
            loopAudio: true,
            vibrate: true,
            warningNotificationOnKill: false,
            androidFullScreenIntent: true,
            payload: w.key,
            // const로 만들면 패키지 안 assert가 상수 계산에서 실패한다.
            // ignore: prefer_const_constructors
            volumeSettings: VolumeSettings.fade(fadeDuration: const Duration(seconds: 8)),
            notificationSettings: NotificationSettings(title: w.title, body: w.body, stopButton: w.kind == RingKind.wake ? '일어났어요' : '확인'),
          ),
        );
      }
    } catch (e) {
      debugPrint('알람 예약 실패: $e');
    }
  }

  /// 알람이 울리기 시작하면 앱 화면에 알리고, 알림에서 껐으면(앱은 켜져 있을 때) 기상으로 기록한다.
  void _onRinging(AlarmSet set) {
    final ids = <int>{for (final a in set.alarms) a.id};
    final started = ids.difference(_ringing);
    final stopped = _ringing.difference(ids);
    _ringing = ids;
    if (started.isNotEmpty) _rang.add(null);
    for (final id in stopped) {
      if (_expectStop.remove(id)) continue;
      // 알림의 '일어났어요'로 껐다: 아직 기록하지 않은 기상이면 기록한다.
      final ring = store.dueAlarms().ring;
      if (ring != null && ring.kind == RingKind.wake) store.dismissWake(ring);
    }
  }
}
