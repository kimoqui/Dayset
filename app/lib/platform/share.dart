// 공유·파일 주고받기. 휴대폰의 공유 창(카카오톡·인스타그램·파일에 저장 등)을 연다.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum ShareOutcome {
  shared('공유했어요'),
  copied('복사했어요'),
  cancelled('공유를 닫았어요'),
  failed('공유하지 못했어요');

  const ShareOutcome(this.text);
  final String text;
}

/// 글을 공유한다. 공유 창을 열 수 없으면 복사한다.
Future<ShareOutcome> shareText(String text, {String? subject}) async {
  try {
    final r = await Share.share(text, subject: subject);
    return r.status == ShareResultStatus.dismissed ? ShareOutcome.cancelled : ShareOutcome.shared;
  } catch (_) {
    return await copyText(text) ? ShareOutcome.copied : ShareOutcome.failed;
  }
}

Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// 파일로 만들어 공유 창을 연다(백업 내려받기·공유 카드 이미지).
Future<ShareOutcome> shareFile(String name, Uint8List bytes, {required String mimeType, String? text}) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    final r = await Share.shareXFiles([XFile(f.path, mimeType: mimeType, name: name)], text: text);
    return r.status == ShareResultStatus.dismissed ? ShareOutcome.cancelled : ShareOutcome.shared;
  } catch (_) {
    return ShareOutcome.failed;
  }
}

Future<ShareOutcome> shareTextFile(String name, String content, {String mimeType = 'application/json'}) =>
    shareFile(name, Uint8List.fromList(utf8.encode(content)), mimeType: mimeType);

/// 글 파일(.json·.ics)을 고른다. 취소하면 null, 읽지 못하면 예외.
Future<({String name, String text})?> pickTextFile(List<String> extensions) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions, withData: true);
  final f = r?.files.firstOrNull;
  if (f == null) return null;
  final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
  if (bytes == null) throw const FileSystemException('파일을 읽지 못했어요');
  return (name: f.name, text: utf8.decode(bytes, allowMalformed: true));
}
