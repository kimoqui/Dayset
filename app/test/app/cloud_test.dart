import 'dart:convert';

import 'package:dayset/app/cloud.dart';
import 'package:dayset/app/cloud_sync.dart';
import 'package:dayset/app/seed.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 메모리 안 가짜 서버: Supabase Auth·PostgREST에서 쓰는 길만 흉내 낸다(웹 테스트 fakeCloud.ts와 같은 동작).
class FakeServer {
  final users = <String, ({String id, String password})>{};
  final tokens = <String, String>{};
  final refresh = <String, String>{};
  final rows = <String, Map<String, Object?>>{};
  var _n = 0;
  var down = false;

  Map<String, Object?> _session(String id, String email) {
    final a = 'a${++_n}';
    final r = 'r$_n';
    tokens[a] = id;
    refresh[r] = id;
    return {'access_token': a, 'refresh_token': r, 'expires_in': 3600, 'user': {'id': id, 'email': email}};
  }

  Future<({int status, String body})> send(String method, Uri url, Map<String, String> headers, String? body) async {
    if (down) throw Exception('offline');
    ({int status, String body}) res(int s, Object? b) => (status: s, body: b == null ? '' : jsonEncode(b));
    final b = body == null ? <String, Object?>{} : (jsonDecode(body) as Map).cast<String, Object?>();
    final who = tokens[(headers['Authorization'] ?? '').replaceFirst('Bearer ', '')];
    switch (url.path) {
      case '/auth/v1/signup':
        final email = b['email'] as String;
        if (users.containsKey(email)) return res(422, {'error_code': 'user_already_exists', 'msg': 'User already registered'});
        final id = 'u${users.length + 1}';
        users[email] = (id: id, password: b['password'] as String);
        return res(200, _session(id, email));
      case '/auth/v1/token':
        if (url.queryParameters['grant_type'] == 'password') {
          final u = users[b['email']];
          if (u == null || u.password != b['password']) return res(400, {'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'});
          return res(200, _session(u.id, b['email'] as String));
        }
        final id = refresh.remove(b['refresh_token']);
        if (id == null) return res(400, {'msg': 'Invalid Refresh Token'});
        return res(200, _session(id, users.entries.firstWhere((e) => e.value.id == id).key));
      case '/auth/v1/logout':
        return res(204, null);
      case '/rest/v1/dayset_state':
        if (who == null) return res(401, {'message': 'JWT expired'});
        final userEq = url.queryParameters['user_id']?.replaceFirst('eq.', '');
        if (userEq != null && userEq != who) return res(200, []);
        final row = rows[who];
        if (method == 'GET') return res(200, row == null ? [] : [row]);
        if (method == 'POST') {
          if (row != null) return res(409, {'code': '23505', 'message': 'duplicate key'});
          rows[who] = {'state': b['state'], 'rev': b['rev'], 'device': b['device'], 'updated_at': DateTime.now().toUtc().toIso8601String()};
          return res(201, null);
        }
        if (method == 'PATCH') {
          final rev = int.parse(url.queryParameters['rev']!.replaceFirst('eq.', ''));
          if (row == null || row['rev'] != rev) return res(200, []);
          rows[who] = {...row, ...b};
          return res(200, [rows[who]]);
        }
        if (method == 'DELETE') {
          rows.remove(who);
          return res(204, null);
        }
    }
    return res(404, {});
  }
}

const cfg = CloudConfig(url: 'https://x.supabase.co', key: 'anon');

void main() {
  group('계정 서버 연결', () {
    test('가입·로그인·잘못된 비밀번호·이미 가입한 이메일·짧은 비밀번호', () async {
      final srv = FakeServer();
      final c = CloudClient(cfg, srv.send);
      expect(await c.signUp('a@b.c', 'secret1'), isNotNull);
      Object? e1;
      try {
        await c.signUp('a@b.c', 'secret1');
      } catch (e) {
        e1 = e;
      }
      expect((e1 as CloudError).code, CloudErrorCode.exists);
      Object? e2;
      try {
        await c.signIn('a@b.c', 'wrong!!');
      } catch (e) {
        e2 = e;
      }
      expect((e2 as CloudError).message, '이메일이나 비밀번호가 맞지 않아요');
      Object? e3;
      try {
        await c.signUp('x@b.c', '123');
      } catch (e) {
        e3 = e;
      }
      expect((e3 as CloudError).code, CloudErrorCode.weak);
    });

    test('서버 설정이 없으면 준비 중, 끊기면 network', () async {
      final srv = FakeServer();
      Object? e1;
      try {
        await CloudClient(const CloudConfig(url: '', key: ''), srv.send).signIn('a@b.c', 'secret1');
      } catch (e) {
        e1 = e;
      }
      expect((e1 as CloudError).code, CloudErrorCode.config);
      srv.down = true;
      Object? e2;
      try {
        await CloudClient(cfg, srv.send).signIn('a@b.c', 'secret1');
      } catch (e) {
        e2 = e;
      }
      expect((e2 as CloudError).code, CloudErrorCode.network);
    });

    test('조건부 올리기: 다른 기기가 먼저 올리면 null', () async {
      final srv = FakeServer();
      final c = CloudClient(cfg, srv.send);
      final s = (await c.signUp('a@b.c', 'secret1'))!;
      expect(await c.createState(s, {'v': 1}, 'web'), 1);
      expect(await c.createState(s, {'v': 9}, 'web'), isNull);
      expect(await c.updateState(s, {'v': 2}, 1, 'android'), 2);
      expect(await c.updateState(s, {'v': 3}, 1, 'web'), isNull);
      final r = (await c.fetchState(s))!;
      expect(r.rev, 2);
      expect(r.device, 'android');
    });
  });

  group('동기화 판단(웹과 같다)', () {
    const remote3 = RemoteState(state: null, rev: 3, updatedAt: '');
    test('기본', () {
      expect(planSync(const SyncMeta(), null, true).kind, SyncKind.create);
      expect(planSync(const SyncMeta(), null, false).kind, SyncKind.none);
      expect(planSync(const SyncMeta(), remote3, false).kind, SyncKind.pull);
      expect(planSync(const SyncMeta(), remote3, true).first, isTrue);
      expect(planSync(const SyncMeta(rev: 3, dirty: true), remote3, true).baseRev, 3);
      expect(planSync(const SyncMeta(rev: 3), remote3, true).kind, SyncKind.none);
      expect(planSync(const SyncMeta(rev: 2), remote3, true).kind, SyncKind.pull);
      expect(planSync(const SyncMeta(rev: 2, dirty: true), remote3, true).kind, SyncKind.conflict);
    });
  });

  group('계정 동기화(이 기기 + 다른 기기)', () {
    final now = DateTime(2026, 11, 1, 21);
    late FakeServer srv;
    late Store store;
    late CloudSync sync;

    setUp(() {
      srv = FakeServer();
      store = Store(storage: StateStorage(MemoryStore()));
      store.setFixedClock(now);
      store.replaceState(demoState(now));
      sync = CloudSync(store: store, client: CloudClient(cfg, srv.send), pushDelay: const Duration(hours: 1));
    });
    tearDown(() => sync.dispose());

    test('가입하면 올리고, 바꾸면 다시 올리고, 다른 기기 것을 받는다', () async {
      expect(await sync.signUp('me@d.s', 'secret1'), isTrue);
      expect(srv.rows.values.first['rev'], 1);
      store.setProfileName('대희');
      expect(sync.meta.dirty, isTrue);
      await sync.syncNow();
      expect(srv.rows.values.first['rev'], 2);

      final other = CloudClient(cfg, srv.send);
      final os = await other.signIn('me@d.s', 'secret1');
      final r = (await other.fetchState(os))!;
      final changed = (jsonDecode(jsonEncode(r.state)) as Map).cast<String, Object?>();
      changed['profile'] = {...(changed['profile'] as Map), 'name': '웹에서'};
      expect(await other.updateState(os, changed, r.rev, 'web'), 3);
      await sync.syncNow();
      expect(store.state.profile.name, '웹에서');
      expect(sync.status, CloudStatus.idle);
    });

    test('양쪽 다 바뀌면 고르게 하고, 이 기기 것을 고르면 계정을 덮는다', () async {
      await sync.signUp('me@d.s', 'secret1');
      final other = CloudClient(cfg, srv.send);
      final os = await other.signIn('me@d.s', 'secret1');
      final r = (await other.fetchState(os))!;
      await other.updateState(os, r.state, r.rev, 'web');
      store.setProfileName('앱에서');
      await sync.syncNow();
      expect(sync.status, CloudStatus.conflict);
      await sync.resolveConflict(useRemote: false);
      expect(srv.rows.values.first['rev'], 3);
      expect(((srv.rows.values.first['state'] as Map)['profile'] as Map)['name'], '앱에서');
    });

    test('새 기기(빈 상태)에서 로그인하면 계정 기록을 받는다', () async {
      await sync.signUp('me@d.s', 'secret1');
      final uploaded = serialize(store.state);
      final store2 = Store(storage: StateStorage(MemoryStore()));
      final sync2 = CloudSync(store: store2, client: CloudClient(cfg, srv.send), pushDelay: const Duration(hours: 1));
      await sync2.signIn('me@d.s', 'secret1');
      expect(store2.state.onboarded, isTrue);
      expect(serialize(store2.state), uploaded);
      sync2.dispose();
    });

    test('기록이 있는 기기에서 처음 로그인하면 고르게 하고, 계정 기록을 고르면 이 기기 기록은 보관한다', () async {
      await sync.signUp('me@d.s', 'secret1');
      final store2 = Store(storage: StateStorage(MemoryStore()));
      store2.replaceState(demoState(now).copyWith(profile: const Profile(id: 'u-local', name: '이 기기')));
      final sync2 = CloudSync(store: store2, client: CloudClient(cfg, srv.send), pushDelay: const Duration(hours: 1));
      await sync2.signIn('me@d.s', 'secret1');
      expect(sync2.conflict?.first, isTrue);
      await sync2.resolveConflict(useRemote: true);
      expect(store2.state.profile.name, isNot('이 기기'));
      expect(store2.storage.keptBackups().length, 1);
      sync2.dispose();
    });

    test('로그인 상태는 다시 열어도 남고, 로그아웃하면 지운다(기록은 그대로)', () async {
      await sync.signUp('me@d.s', 'secret1');
      final again = CloudSync(store: store, client: CloudClient(cfg, srv.send));
      expect(again.session?.email, 'me@d.s');
      expect(again.meta.rev, 1);
      await again.signOut();
      again.dispose();
      final third = CloudSync(store: store, client: CloudClient(cfg, srv.send));
      expect(third.session, isNull);
      expect(store.state.onboarded, isTrue);
      third.dispose();
    });

    test('인터넷이 끊기면 오프라인으로 표시하고, 돌아오면 올린다', () async {
      await sync.signUp('me@d.s', 'secret1');
      store.setProfileName('끊김');
      srv.down = true;
      await sync.syncNow();
      expect(sync.status, CloudStatus.offline);
      expect(sync.meta.dirty, isTrue);
      srv.down = false;
      await sync.syncNow();
      expect(sync.meta.dirty, isFalse);
    });
  });
}
