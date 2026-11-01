# DaySet 앱 설치와 첫 실행 (Mac)

처음 한 번만 하면 된다. 막히는 단계가 있으면 그 화면을 캡처해서 Claude에게 보내면 된다.

## 1. 설치 (약 1~2시간, 대부분 다운로드 대기)

1. **Xcode**: App Store에서 설치 → 한 번 실행해 추가 구성요소 설치에 동의
2. **터미널**에서 차례로 실행
   ```bash
   xcode-select --install
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install --cask flutter
   brew install cocoapods
   ```
3. **Android Studio**: https://developer.android.com/studio 에서 설치 → 첫 실행 마법사에서 SDK 설치
4. 확인: `flutter doctor` → 빨간 X가 없으면 된다(경고는 괜찮다)
5. **Claude Code**: `npm install -g @anthropic-ai/claude-code` (Node가 없으면 `brew install node` 먼저)

## 2. 프로젝트 준비

```bash
mkdir -p ~/Projects && cd ~/Projects
unzip ~/Downloads/dayset-app.zip
cd dayset
flutter create --org com.dayset --project-name dayset --platforms ios,android .
rm -f test/widget_test.dart   # flutter create가 만든 예제 테스트(우리 앱과 맞지 않음)
flutter pub get
```

## 3. 테스트와 첫 실행

```bash
TZ=Asia/Seoul flutter test   # 엔진·앱 로직·웹 호환 테스트가 모두 통과해야 한다
flutter analyze              # 오류가 없어야 한다
flutter run                  # 연결된 아이폰이나 안드로이드 기기를 고른다
```

아이폰에 처음 설치할 때는 Xcode에서 서명이 필요하다:
`open ios/Runner.xcworkspace` → Runner → **Signing & Capabilities** → Team에서 본인 Apple 계정 선택.

처음 화면은 웹과 같다: 목표 고르기 → 동의 → 알림 안내 → 기록부터 시작(2일 관찰) 또는 바로 설정.
설정 → 데이터 → **예시 데이터**를 누르면 3주치 기록으로 모든 화면을 둘러볼 수 있다.

## 4. 웹에서 쓰던 기록 옮기기

1. 웹 버전에서 설정 → 데이터 → **백업 내보내기** → `dayset-backup-….json` 파일이 생긴다
2. 그 파일을 휴대폰으로 보낸다(에어드롭, 카카오톡 나에게 보내기, 구글 드라이브 등)
3. 앱에서 설정 → 데이터 → **백업 불러오기** → 파일 고르기(또는 내용 붙여 넣기)
4. 앱에 있던 데이터는 지우지 않고 따로 보관한다(같은 화면의 '보관한 데이터'에서 되돌릴 수 있다)

친구 코드(DS1-…)는 웹과 앱이 서로 읽는다.

## 5. 1단계에서 아직 안 되는 것 (다음 단계에서 붙인다)

| 기능 | 지금 | 다음 |
| --- | --- | --- |
| 잠금화면 '지금 일정' 알림·기록 버튼 | 앱이 열려 있을 때 화면 안 띠로 알림 | 2단계: flutter_local_notifications |
| 기상·취침 알람 | 앱이 열려 있을 때 알람 화면 | 3단계: iOS AlarmKit·안드로이드 AlarmManager |
| 캘린더 | .ics 파일 가져오기 | 기기 캘린더 연결 |
| QR | 내 QR 보여 주기 + 코드 붙여 넣기 | 카메라로 QR 찍기 |
| 친구·근처 순위 | 코드를 주고받을 때 갱신 | 4단계: 서버로 실시간 |

## 6. 홈 화면 '지금' 위젯 (선택)

### iOS (iOS 17 이상 아이폰)

1. `open ios/Runner.xcworkspace` → Runner → **Signing & Capabilities** → **+ Capability → App Groups** → `group.com.dayset.dayset`
2. **File → New → Target → Widget Extension** → Product Name `NowWidget`, Live Activity·Configuration App Intent **체크 해제**
3. 새 NowWidget 폴더의 swift 파일을 지우고 `native/ios/NowWidget/NowWidget.swift`를 넣는다(Target: NowWidget)
4. NowWidget 타깃 → General → Minimum Deployments **iOS 17.0**, Signing & Capabilities → **App Groups**에 같은 그룹
5. 실행 → 홈 화면 길게 누르기 → 위젯 추가 → DaySet '지금 상태'

"Cycle inside Runner" 오류: Runner 타깃 → Build Phases에서 **Embed Foundation Extensions**를 **Run Script** 위로.

### 안드로이드 (안드로이드 9 이상)

1. `native/android/kotlin/NowWidgetProvider.kt` → `android/app/src/main/kotlin/com/dayset/dayset/`
2. `native/android/res/` 아래 폴더들 → `android/app/src/main/res/` 같은 이름 폴더
3. `native/android/AndroidManifest-snippet.xml` 내용 → `android/app/src/main/AndroidManifest.xml`의 `<application>` 안
4. `flutter run` → 홈 화면 길게 누르기 → 위젯 → DaySet

위젯에서 누른 기록은 앱을 열 때 반영된다("위젯에서 누른 기록 N개를 반영했어요").

## 7. 이후 개발은 Claude Code로

```bash
cd ~/Projects/dayset
claude
```
첫 요청 예: "CLAUDE.md 읽고 2단계(잠금화면 알림) 진행해줘"
