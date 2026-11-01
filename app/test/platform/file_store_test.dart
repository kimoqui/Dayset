import 'dart:io';

import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/platform/file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('기기 파일 저장소', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dayset_fs_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('쓴 값을 다시 열어도 그대로 읽는다', () async {
      final a = await FileStore.open(at: dir);
      expect(a.write('dayset:v1', '{"a":1}'), SaveResult.ok);
      expect(a.write('dayset:kept:123:broken', '깨진 데이터'), SaveResult.ok);
      final b = await FileStore.open(at: dir);
      expect(b.read('dayset:v1'), '{"a":1}');
      expect(b.read('dayset:kept:123:broken'), '깨진 데이터');
      expect(b.keys.toSet(), {'dayset:v1', 'dayset:kept:123:broken'});
    });

    test('지우면 다시 열어도 없다', () async {
      final a = await FileStore.open(at: dir);
      a.write('x', '1');
      a.remove('x');
      final b = await FileStore.open(at: dir);
      expect(b.read('x'), isNull);
    });

    test('쓰다 남은 임시 파일은 읽지 않는다', () async {
      final a = await FileStore.open(at: dir);
      a.write('dayset:v1', 'ok');
      File('${dir.path}/data/zzz.json.tmp').writeAsStringSync('half');
      final b = await FileStore.open(at: dir);
      expect(b.keys.toList(), ['dayset:v1']);
    });

    test('스토어 상태를 저장하고 다시 연다', () async {
      final kv = await FileStore.open(at: dir);
      final store = Store(storage: StateStorage(kv));
      store.setFixedClock(DateTime(2026, 10, 21, 9));
      store.setProfileName('대희');
      final again = Store(storage: StateStorage(await FileStore.open(at: dir)));
      expect(again.state.profile.name, '대희');
      expect(again.state.profile.id, store.state.profile.id);
    });

    test('깨진 저장 데이터는 보관하고 새로 시작한다', () async {
      final kv = await FileStore.open(at: dir);
      kv.write(storageKey, '{not json');
      final store = Store(storage: StateStorage(await FileStore.open(at: dir)));
      expect(store.loadIssue, KeptReason.broken);
      final kept = store.storage.keptBackups();
      expect(kept.length, 1);
      expect(store.storage.kv.read(kept.first.key), '{not json');
      expect(store.state.onboarded, isFalse);
    });
  });
}
