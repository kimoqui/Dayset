// 계정 연동: 이메일 계정으로 로그인하면 기록 전체(백업과 같은 JSON)를 서버(Supabase)에 두고 웹·앱이 함께 쓴다.
// 웹 버전 src/app/cloud.ts와 같은 규칙·같은 표(dayset_state)다. HTTP 보내기는 바깥에서 넣어 준다(lib/platform/http_send.dart).
//
// 동기화 규칙(마지막에 쓴 쪽이 이기되, 모르고 덮어쓰지 않는다):
//  - rev: 서버에 쓸 때마다 1씩 올린다. 기기는 마지막으로 맞춘 rev를 기억한다.
//  - 올리기: 서버 rev가 내가 아는 rev와 같을 때만 쓴다(조건부 PATCH). 아니면 '충돌'.
//  - 받기: 서버 rev가 더 크고 이 기기에 안 올린 변경이 없으면 서버 기록으로 바꾼다.
//  - 충돌(양쪽 다 바뀜, 또는 처음 연결할 때 양쪽에 기록이 있음): 사용자가 고른다. 버리는 쪽은 지우지 않고 보관한다.

import 'dart:convert';

class CloudConfig {
  const CloudConfig({required this.url, required this.key});
  final String url;
  final String key;
}

class Session {
  const Session({required this.accessToken, required this.refreshToken, required this.expiresAt, required this.userId, required this.email});
  final String accessToken;
  final String refreshToken;

  /// 만료 시각(ms).
  final int expiresAt;
  final String userId;
  final String email;

  Map<String, Object?> toJson() =>
      {'accessToken': accessToken, 'refreshToken': refreshToken, 'expiresAt': expiresAt, 'userId': userId, 'email': email};
  static Session? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return Session(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expiresAt: (j['expiresAt'] as num).toInt(),
        userId: j['userId'] as String,
        email: j['email'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteState {
  const RemoteState({required this.state, required this.rev, required this.updatedAt, this.device});
  final Object? state;
  final int rev;
  final String updatedAt;
  final String? device;
}

enum CloudErrorCode { config, network, auth, exists, weak, confirm, rate, server, email }

const _text = {
  CloudErrorCode.config: '서버가 아직 준비되지 않았어요',
  CloudErrorCode.network: '인터넷 연결을 확인해 주세요',
  CloudErrorCode.auth: '이메일이나 비밀번호가 맞지 않아요',
  CloudErrorCode.exists: '이미 가입한 이메일이에요. 로그인해 주세요',
  CloudErrorCode.weak: '비밀번호는 6자 이상이어야 해요',
  CloudErrorCode.confirm: '메일함에서 가입 확인 링크를 누른 뒤 로그인해 주세요',
  CloudErrorCode.rate: '요청이 많아요. 잠시 후 다시 해 주세요',
  CloudErrorCode.server: '서버에서 처리하지 못했어요. 잠시 후 다시 해 주세요',
  CloudErrorCode.email: '이메일 주소를 확인해 주세요',
};

class CloudError implements Exception {
  CloudError(this.code) : message = _text[code]!;
  final CloudErrorCode code;
  final String message;

  @override
  String toString() => message;
}

String errorText(Object e) => e is CloudError ? e.message : _text[CloudErrorCode.server]!;

/// 서버 오류 글을 사용자 문구로 바꾼다.
CloudError classify(int status, Map<String, Object?> body) {
  final raw = [body['error_code'], body['code'], body['msg'], body['message'], body['error_description'], body['error']].whereType<Object>().join(' ').toLowerCase();
  final CloudErrorCode code;
  if (status == 429 || raw.contains('rate limit') || raw.contains('over_request')) {
    code = CloudErrorCode.rate;
  } else if (raw.contains('already registered') || raw.contains('user_already_exists') || raw.contains('already exists')) {
    code = CloudErrorCode.exists;
  } else if (raw.contains('not confirmed') || raw.contains('email_not_confirmed')) {
    code = CloudErrorCode.confirm;
  } else if (raw.contains('password') && (raw.contains('least') || raw.contains('weak') || raw.contains('short'))) {
    code = CloudErrorCode.weak;
  } else if (raw.contains('invalid login') || raw.contains('invalid_credentials') || raw.contains('invalid grant') || raw.contains('refresh token') || status == 401) {
    code = CloudErrorCode.auth;
  } else if (raw.contains('email') && (raw.contains('invalid') || raw.contains('format'))) {
    code = CloudErrorCode.email;
  } else {
    code = CloudErrorCode.server;
  }
  return CloudError(code);
}

/// HTTP 보내기. 연결이 안 되면 예외를 던진다(network로 바꾼다).
typedef HttpSend = Future<({int status, String body})> Function(String method, Uri url, Map<String, String> headers, String? body);

class CloudClient {
  CloudClient(this.cfg, this.send);
  final CloudConfig cfg;
  final HttpSend send;

  bool get ready => cfg.url.isNotEmpty && cfg.key.isNotEmpty;

  Future<({int status, Object? json})> _call(String path, {String method = 'GET', Object? body, String? token, Map<String, String> headers = const {}}) async {
    if (!ready) throw CloudError(CloudErrorCode.config);
    final base = cfg.url.replaceAll(RegExp(r'/+$'), '');
    // 새 공개 키(sb_publishable_…)는 JWT가 아니라 apikey 머리에만 둔다. Authorization에는 로그인 토큰만 넣는다.
    final bearer = token ?? (cfg.key.startsWith('sb_') ? null : cfg.key);
    final h = {'apikey': cfg.key, 'Content-Type': 'application/json', ...headers, if (bearer != null) 'Authorization': 'Bearer $bearer'};
    ({int status, String body}) res;
    try {
      res = await send(method, Uri.parse('$base$path'), h, body == null ? null : jsonEncode(body));
    } catch (_) {
      throw CloudError(CloudErrorCode.network);
    }
    Object? json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      json = null;
    }
    if (res.status < 200 || res.status >= 300) {
      throw classify(res.status, json is Map ? json.cast<String, Object?>() : const {});
    }
    return (status: res.status, json: json);
  }

  Session _toSession(Object? json, int now, String email) {
    if (json is! Map || json['access_token'] is! String || json['refresh_token'] is! String || json['user'] is! Map) {
      throw CloudError(CloudErrorCode.server);
    }
    final user = (json['user'] as Map).cast<String, Object?>();
    final expiresAt = json['expires_at'] is num ? (json['expires_at'] as num).toInt() * 1000 : now + ((json['expires_in'] as num?)?.toInt() ?? 3600) * 1000;
    return Session(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: expiresAt,
      userId: user['id'] as String,
      email: user['email'] as String? ?? email,
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 가입. 메일 확인을 켜 둔 서버면 null(로그인 전 메일 확인 필요).
  Future<Session?> signUp(String email, String password) async {
    if (password.length < 6) throw CloudError(CloudErrorCode.weak);
    final r = await _call('/auth/v1/signup', method: 'POST', body: {'email': email.trim(), 'password': password});
    final j = r.json;
    if (j is Map && j['access_token'] == null) {
      final user = j['user'];
      final ids = user is Map ? user['identities'] : j['identities'];
      if (ids is List && ids.isEmpty) throw CloudError(CloudErrorCode.exists);
      return null;
    }
    return _toSession(j, _now(), email);
  }

  Future<Session> signIn(String email, String password) async {
    final r = await _call('/auth/v1/token?grant_type=password', method: 'POST', body: {'email': email.trim(), 'password': password});
    return _toSession(r.json, _now(), email);
  }

  Future<Session> refresh(Session s) async {
    final r = await _call('/auth/v1/token?grant_type=refresh_token', method: 'POST', body: {'refresh_token': s.refreshToken});
    return _toSession(r.json, _now(), s.email);
  }

  Future<void> signOut(Session s) async {
    try {
      await _call('/auth/v1/logout', method: 'POST', token: s.accessToken);
    } catch (_) {}
  }

  Future<void> resetPassword(String email) => _call('/auth/v1/recover', method: 'POST', body: {'email': email.trim()});

  Future<RemoteState?> fetchState(Session s) async {
    final r = await _call('/rest/v1/dayset_state?select=state,rev,updated_at,device&user_id=eq.${s.userId}', token: s.accessToken);
    final j = r.json;
    if (j is! List || j.isEmpty || j.first is! Map) return null;
    final row = (j.first as Map).cast<String, Object?>();
    return RemoteState(state: row['state'], rev: (row['rev'] as num).toInt(), updatedAt: row['updated_at'] as String? ?? '', device: row['device'] as String?);
  }

  /// 처음 올리기. 이미 행이 있으면 null(충돌).
  Future<int?> createState(Session s, Object? state, String device) async {
    try {
      await _call('/rest/v1/dayset_state',
          method: 'POST', token: s.accessToken, headers: {'Prefer': 'return=minimal'}, body: {'user_id': s.userId, 'state': state, 'rev': 1, 'device': device});
      return 1;
    } on CloudError catch (e) {
      if (e.code == CloudErrorCode.exists || e.code == CloudErrorCode.server) {
        if (await fetchState(s) != null) return null;
      }
      rethrow;
    }
  }

  /// 서버 rev가 baseRev일 때만 바꾼다. 바꿨으면 새 rev, 다른 기기가 먼저 바꿨으면 null.
  Future<int?> updateState(Session s, Object? state, int baseRev, String device, {DateTime? now}) async {
    final r = await _call('/rest/v1/dayset_state?user_id=eq.${s.userId}&rev=eq.$baseRev',
        method: 'PATCH',
        token: s.accessToken,
        headers: {'Prefer': 'return=representation'},
        body: {'state': state, 'rev': baseRev + 1, 'device': device, 'updated_at': (now ?? DateTime.now()).toUtc().toIso8601String()});
    final j = r.json;
    return j is List && j.isNotEmpty ? baseRev + 1 : null;
  }

  Future<void> deleteState(Session s) => _call('/rest/v1/dayset_state?user_id=eq.${s.userId}', method: 'DELETE', token: s.accessToken);

  /// 말로 일정 바꾸기: 서버 AI 함수(dayset-chat)에 말과 일정 요약을 보내고 바꾸기 목록(JSON)을 받는다.
  Future<Object?> askChat(Session s, String text, Object? context) async =>
      (await _call('/functions/v1/dayset-chat', method: 'POST', token: s.accessToken, body: {'text': text, 'context': context})).json;
}

// ---------------------------------------------------------------------------
// 동기화 판단(순수 함수: 무엇을 할지만 정한다)
// ---------------------------------------------------------------------------

class SyncMeta {
  const SyncMeta({this.userId = '', this.rev = 0, this.dirty = false, this.syncedAt});

  final String userId;

  /// 마지막으로 서버와 맞춘 rev(0 = 아직 맞춘 적 없음).
  final int rev;

  /// 마지막으로 맞춘 뒤 이 기기에서 바뀐 것이 있는지.
  final bool dirty;

  /// 마지막으로 맞춘 시각(ms).
  final int? syncedAt;

  SyncMeta copyWith({String? userId, int? rev, bool? dirty, int? syncedAt, bool clearSynced = false}) => SyncMeta(
        userId: userId ?? this.userId,
        rev: rev ?? this.rev,
        dirty: dirty ?? this.dirty,
        syncedAt: clearSynced ? null : (syncedAt ?? this.syncedAt),
      );

  Map<String, Object?> toJson() => {'userId': userId, 'rev': rev, 'dirty': dirty, 'syncedAt': syncedAt};
  static SyncMeta fromJson(Object? j) => j is Map
      ? SyncMeta(
          userId: j['userId'] as String? ?? '',
          rev: (j['rev'] as num?)?.toInt() ?? 0,
          dirty: j['dirty'] as bool? ?? false,
          syncedAt: (j['syncedAt'] as num?)?.toInt(),
        )
      : const SyncMeta();
}

enum SyncKind { create, push, pull, conflict, none }

class SyncPlan {
  const SyncPlan(this.kind, {this.baseRev, this.remote, this.first = false});
  final SyncKind kind;
  final int? baseRev;
  final RemoteState? remote;
  final bool first;
}

/// 무엇을 할지 정한다. localHasData: 이 기기에 쓸 만한 기록이 있는지(시작했는지).
SyncPlan planSync(SyncMeta meta, RemoteState? remote, bool localHasData) {
  if (remote == null) return SyncPlan(localHasData ? SyncKind.create : SyncKind.none);
  if (meta.rev == 0) {
    return localHasData ? SyncPlan(SyncKind.conflict, remote: remote, first: true) : SyncPlan(SyncKind.pull, remote: remote);
  }
  if (remote.rev == meta.rev) return meta.dirty ? SyncPlan(SyncKind.push, baseRev: meta.rev) : const SyncPlan(SyncKind.none);
  if (remote.rev > meta.rev) return meta.dirty ? SyncPlan(SyncKind.conflict, remote: remote) : SyncPlan(SyncKind.pull, remote: remote);
  return SyncPlan(SyncKind.push, baseRev: remote.rev);
}
