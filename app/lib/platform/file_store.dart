// 기기 파일에 저장하는 KeyValueStore. 키마다 파일 하나(앱 전용 폴더).
// 시작할 때 한 번 모두 읽어 메모리에 두고, 쓸 때는 임시 파일에 쓴 뒤 바꿔 끼운다(쓰다가 꺼져도 이전 파일이 남는다).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../app/state.dart';

class FileStore implements KeyValueStore {
  FileStore._(this.dir, this._data);

  final Directory dir;
  final Map<String, String> _data;

  static String _fileName(String key) => '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json';
  static String? _keyOf(String name) {
    if (!name.endsWith('.json')) return null;
    final b = name.substring(0, name.length - 5);
    try {
      return utf8.decode(base64Url.decode(b + '=' * ((4 - b.length % 4) % 4)));
    } catch (_) {
      return null;
    }
  }

  /// 앱 전용 폴더의 data 폴더를 연다. 읽지 못한 파일은 건너뛴다.
  static Future<FileStore> open({Directory? at}) async {
    final base = at ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/data');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final data = <String, String>{};
    for (final f in dir.listSync().whereType<File>()) {
      final key = _keyOf(f.uri.pathSegments.last);
      if (key == null) continue;
      try {
        data[key] = f.readAsStringSync();
      } catch (_) {
        // 읽지 못한 파일은 건너뛴다(지우지 않는다).
      }
    }
    return FileStore._(dir, data);
  }

  @override
  String? read(String key) => _data[key];

  @override
  SaveResult write(String key, String value) {
    final file = File('${dir.path}/${_fileName(key)}');
    final tmp = File('${file.path}.tmp');
    try {
      tmp.writeAsStringSync(value, flush: true);
      tmp.renameSync(file.path);
      _data[key] = value;
      return SaveResult.ok;
    } on FileSystemException catch (e) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      // ENOSPC(28): 저장 공간 없음
      return e.osError?.errorCode == 28 ? SaveResult.quota : SaveResult.blocked;
    }
  }

  @override
  void remove(String key) {
    _data.remove(key);
    try {
      final f = File('${dir.path}/${_fileName(key)}');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  Iterable<String> get keys => _data.keys;
}
