// 계정 동기화 실행: 로그인 상태를 기억하고, 기록이 바뀌면 잠시 뒤 올리고, 앱을 열면 받는다.
// 웹 버전 src/app/cloudSync.ts와 같은 흐름. 무엇을 할지는 cloud.dart의 planSync가 정한다.
// 버리는 쪽 기록은 지우지 않고 보관한다(설정 → 데이터).

import 'dart:async';
import 'dart:convert';

import 'cloud.dart';
import 'state.dart';
import 'store.dart';

enum CloudStatus { off, idle, syncing, offline, error, conflict }

const _authKey = 'dayset:auth';
const _metaKey = 'dayset:cloud';

class CloudSync {
  CloudSync({required this.store, required this.client, this.device = 'android', this.pushDelay = const Duration(seconds: 4)}) {
    session = Session.fromJson(_read(_authKey));
    final m = SyncMeta.fromJson(_read(_metaKey));
    meta = session != null && m.userId == session!.userId ? m : SyncMeta(userId: session?.userId ?? '');
    status = session != null ? CloudStatus.idle : CloudStatus.off;
    store.addListener(_onStore);
  }

  final Store store;
  CloudClient client;
  final String device;
  final Duration pushDelay;

  Session? session;
  late SyncMeta meta;
  late CloudStatus status;
  String? message;
  ({RemoteState remote, bool first})? conflict;

  bool get ready => client.ready;

  final _listeners = <void Function()>[];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _emit() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  void dispose() {
    _timer?.cancel();
    store.removeListener(_onStore);
  }

  Object? _read(String key) {
    try {
      final t = store.storage.kv.read(key);
      return t == null ? null : jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  void _write(String key, Object? v) {
    try {
      if (v == null) {
        store.storage.kv.remove(key);
      } else {
        store.storage.kv.write(key, jsonEncode(v));
      }
    } catch (_) {}
  }

  void _saveMeta(SyncMeta m) {
    meta = m;
    _write(_metaKey, m.toJson());
  }

  void _setSession(Session? s) {
    session = s;
    _write(_authKey, s?.toJson());
    if (s != null && meta.userId != s.userId) _saveMeta(SyncMeta(userId: s.userId));
    if (s == null) _write(_metaKey, null);
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  Object? _toJson(AppState s) => jsonDecode(serialize(s));

  bool _applying = false;
  Timer? _timer;

  void _onStore() {
    if (_applying || session == null) return;
    if (!meta.dirty) _saveMeta(meta.copyWith(dirty: true));
    _emit();
    _timer?.cancel();
    _timer = Timer(pushDelay, syncNow);
  }

  void _applyRemote(RemoteState remote, {required bool keepLocal}) {
    final next = deserialize(jsonEncode(remote.state));
    if (keepLocal) store.storage.keepCopy(serialize(store.state), KeptReason.beforeImport);
    _applying = true;
    try {
      store.replaceState(next);
    } finally {
      _applying = false;
    }
    _saveMeta(meta.copyWith(rev: remote.rev, dirty: false, syncedAt: _nowMs()));
  }

  Future<Session> _fresh() async {
    final s = session;
    if (s == null) throw CloudError(CloudErrorCode.auth);
    if (s.expiresAt - _nowMs() > 60000) return s;
    try {
      final n = await client.refresh(s);
      _setSession(n);
      return n;
    } on CloudError catch (e) {
      if (e.code == CloudErrorCode.auth) {
        _setSession(null);
        status = CloudStatus.off;
        message = '로그인이 만료됐어요. 다시 로그인해 주세요';
        _emit();
      }
      rethrow;
    }
  }

  Future<void>? _running;

  /// 지금 맞춘다(이미 맞추는 중이면 그 결과를 기다린다).
  Future<void> syncNow() {
    if (session == null || !client.ready) return Future.value();
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<void> _run() async {
    status = CloudStatus.syncing;
    message = null;
    _emit();
    try {
      for (var round = 0; round < 2; round++) {
        final s = await _fresh();
        final remote = await client.fetchState(s);
        final plan = planSync(meta, remote, store.state.onboarded);
        switch (plan.kind) {
          case SyncKind.none:
            _saveMeta(meta.copyWith(syncedAt: _nowMs()));
          case SyncKind.create:
            final rev = await client.createState(s, _toJson(store.state), device);
            if (rev == null) continue;
            _saveMeta(meta.copyWith(rev: rev, dirty: false, syncedAt: _nowMs()));
          case SyncKind.push:
            final rev = await client.updateState(s, _toJson(store.state), plan.baseRev!, device);
            if (rev == null) continue;
            _saveMeta(meta.copyWith(rev: rev, dirty: false, syncedAt: _nowMs()));
          case SyncKind.pull:
            _applyRemote(plan.remote!, keepLocal: false);
          case SyncKind.conflict:
            status = CloudStatus.conflict;
            conflict = (remote: plan.remote!, first: plan.first);
            _emit();
            return;
        }
        status = CloudStatus.idle;
        conflict = null;
        _emit();
        return;
      }
      status = CloudStatus.idle;
      _emit();
    } catch (e) {
      if (session != null) {
        status = e is CloudError && e.code == CloudErrorCode.network ? CloudStatus.offline : CloudStatus.error;
        message = errorText(e);
        _emit();
      }
    }
  }

  /// 충돌 해결: remote = 계정 기록 쓰기(이 기기 기록은 보관), local = 이 기기 기록으로 계정을 덮기.
  Future<void> resolveConflict({required bool useRemote}) async {
    final c = conflict;
    if (c == null || session == null) return;
    try {
      if (useRemote) {
        _applyRemote(c.remote, keepLocal: true);
      } else {
        final s = await _fresh();
        final rev = await client.updateState(s, _toJson(store.state), c.remote.rev, device);
        if (rev == null) {
          conflict = null;
          _emit();
          await syncNow();
          return;
        }
        _saveMeta(meta.copyWith(rev: rev, dirty: false, syncedAt: _nowMs()));
      }
      status = CloudStatus.idle;
      conflict = null;
      message = null;
      _emit();
    } catch (e) {
      status = CloudStatus.error;
      message = errorText(e);
      _emit();
    }
  }

  Future<void> signIn(String email, String password) async {
    final s = await client.signIn(email, password);
    _setSession(s);
    status = CloudStatus.idle;
    message = null;
    _emit();
    await syncNow();
  }

  /// 가입. 메일 확인이 필요한 서버면 false.
  Future<bool> signUp(String email, String password) async {
    final s = await client.signUp(email, password);
    if (s == null) return false;
    _setSession(s);
    status = CloudStatus.idle;
    message = null;
    _emit();
    await syncNow();
    return true;
  }

  /// 로그아웃. 이 기기 기록은 그대로 둔다.
  Future<void> signOut() async {
    final s = session;
    _setSession(null);
    meta = const SyncMeta();
    status = CloudStatus.off;
    message = null;
    conflict = null;
    _emit();
    if (s != null) await client.signOut(s);
  }

  Future<void> resetPassword(String email) => client.resetPassword(email);

  /// 로그인했으면 서버 AI에 말을 보낸다. 로그인 전·서버 오류·시간 초과면 null(화면은 기기 안 규칙으로 읽는다).
  Future<Object?> askChat(String text, Object? context, {Duration timeout = const Duration(seconds: 12)}) async {
    if (session == null || !client.ready) return null;
    try {
      final s = await _fresh();
      return await client.askChat(s, text, context).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// 서버에 저장된 기록을 지운다(이 기기 기록은 그대로). 다음 동기화 때 이 기기 기록을 새로 올린다.
  Future<void> deleteRemote() async {
    final s = await _fresh();
    await client.deleteState(s);
    _saveMeta(meta.copyWith(rev: 0, dirty: true, clearSynced: true));
    status = CloudStatus.idle;
    _emit();
  }
}

/// 충돌 창에 보여 줄 요약(기록 수, 마지막 기록 날).
({int logs, int tasks, DateTime? lastLog})? summarizeState(Object? raw) {
  try {
    final s = deserialize(jsonEncode(raw));
    return (logs: s.logs.length, tasks: s.tasks.length, lastLog: s.logs.isEmpty ? null : s.logs.last.start);
  } catch (_) {
    return null;
  }
}
