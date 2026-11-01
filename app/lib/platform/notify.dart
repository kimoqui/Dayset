// 알림 연결 자리. 2단계(flutter_local_notifications)에서 실제 권한 요청·잠금화면 알림을 붙인다.
// 지금(1단계)은 권한을 받을 수 없으므로 화면은 설정만 저장하고, 앱이 열려 있을 때 화면 안 알림 띠로 알린다.

abstract class NotifyPort {
  /// 기기 알림을 쓸 수 있는지(이 빌드에 알림 기능이 들어 있는지).
  bool get available;

  /// 권한을 묻는다. 허용하면 true.
  Future<bool> request();

  /// 이미 허용했는지.
  Future<bool> granted();
}

class _NoNotify implements NotifyPort {
  const _NoNotify();
  @override
  bool get available => false;
  @override
  Future<bool> request() async => false;
  @override
  Future<bool> granted() async => false;
}

/// 앱 전체가 쓰는 알림 연결. 2단계에서 실제 구현으로 바꾼다.
NotifyPort notifyPort = const _NoNotify();
