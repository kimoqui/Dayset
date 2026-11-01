import 'package:flutter/material.dart';

import 'app/state.dart';
import 'app/store.dart';
import 'platform/file_store.dart';
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
  runApp(DaySetApp(store: store, bridge: bridge));
}
