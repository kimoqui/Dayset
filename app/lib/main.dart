import 'package:flutter/material.dart';

import 'app/cloud.dart';
import 'app/cloud_config.dart';
import 'app/cloud_sync.dart';
import 'app/state.dart';
import 'app/store.dart';
import 'platform/device_sync.dart';
import 'platform/file_store.dart';
import 'platform/http_send.dart';
import 'platform/notify.dart';
import 'platform/widget_bridge.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 기기 파일에 저장한다. 폴더를 열 수 없으면(드문 경우) 메모리로 시작하고 저장 문제를 화면에 알린다.
  KeyValueStore kv;
  try {
    kv = await FileStore.open();
  } catch (_) {
    kv = MemoryStore();
  }
  final store = Store(storage: StateStorage(kv));

  WidgetBridge? bridge = WidgetBridge();
  try {
    await bridge.init();
  } catch (_) {
    // 위젯 설정 전(앱 그룹 미설정)에도 앱은 실행된다.
    bridge = null;
  }
  // 계정 동기화(서버 주소가 없으면 '서버 준비 중'으로 보인다).
  final cloud = CloudSync(store: store, client: CloudClient(const CloudConfig(url: cloudUrl, key: cloudKey), ioSend));
  // 휴대폰 알림·알람(앱이 꺼져 있어도 일정 시작 알림과 기상·취침 알람이 울린다).
  final device = DeviceSync(store);
  await device.init();
  notifyPort = device;
  runApp(DaySetApp(store: store, bridge: bridge, cloud: cloud, device: device));
}
