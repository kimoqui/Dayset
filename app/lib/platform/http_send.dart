// 계정 서버에 HTTP로 보낸다(dart:io, 추가 패키지 없음).

import 'dart:convert';
import 'dart:io';

import '../app/cloud.dart';

final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

/// [HttpSend] 구현. 20초 안에 답이 없으면 연결 실패로 본다.
Future<({int status, String body})> ioSend(String method, Uri url, Map<String, String> headers, String? body) async {
  final req = await _client.openUrl(method, url).timeout(const Duration(seconds: 20));
  headers.forEach(req.headers.set);
  if (body != null) {
    final bytes = utf8.encode(body);
    req.headers.contentLength = bytes.length;
    req.add(bytes);
  }
  final res = await req.close().timeout(const Duration(seconds: 20));
  final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
  return (status: res.statusCode, body: text);
}
