# 구글 플레이에 올리기

GitHub Actions가 앱을 두 가지로 만든다.

| 파일 | 서명 | 쓰는 곳 |
|---|---|---|
| `DaySet.apk` | 베타 키(저장소에 공개) | 직접 설치·베타 테스트 |
| `DaySet.aab` | 스토어 업로드 키(GitHub Secrets) | 구글 플레이 업로드 |

AAB는 아래 1단계 Secrets를 넣어야 만들어진다. 넣고 나면 `app/`이 바뀔 때마다 Releases에 APK와 AAB가 같이 올라간다.

## 1. 업로드 키 만들기 (PC에서 한 번)

Android Studio를 설치했으면 keytool이 들어 있다. PowerShell에서 실행한다.

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore "$HOME\dayset-upload.jks" -alias dayset -keyalg RSA -keysize 2048 -validity 10000
```

- 비밀번호를 두 번 묻는다. 키 비밀번호도 같은 것으로 둔다.
- 이름·조직은 `BeyondWork`처럼 적당히 넣는다.
- `dayset-upload.jks`와 비밀번호는 잃어버리지 않게 따로 보관한다. 구글 플레이 앱 서명을 쓰므로 잃어버려도 업로드 키는 다시 등록할 수 있지만 절차가 번거롭다.

GitHub에 넣을 문자열로 바꾼다(클립보드에 복사된다).

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\dayset-upload.jks")) | Set-Clipboard
```

## 2. GitHub Secrets 넣기

저장소 → Settings → Secrets and variables → Actions → New repository secret

| 이름 | 값 |
|---|---|
| `DAYSET_UPLOAD_KEYSTORE_B64` | 위에서 복사한 문자열 |
| `DAYSET_KEYSTORE_PASSWORD` | 키스토어 비밀번호 |
| `DAYSET_KEY_ALIAS` | `dayset` |
| `DAYSET_KEY_PASSWORD` | 키 비밀번호(위와 같게 했으면 같은 값) |

넣은 뒤 Actions → Android APK → Run workflow로 다시 빌드하면 Releases에 `DaySet.aab`가 생긴다.

## 3. Play Console

1. 개발자 계정 만들기(등록비 1회 25달러).
   - **개인 계정**: 정식 출시 전에 비공개 테스트를 **테스터 12명 이상, 14일 이상** 해야 한다.
   - **조직 계정**(비욘드워크 법인): 이 조건이 없다. D-U-N-S 번호(무료)가 필요하다.
2. 앱 만들기 → 앱 이름 DaySet, 무료.
3. 테스트 → 내부 테스트 → 새 버전 → `DaySet.aab` 업로드 → 테스터 이메일 추가 → 출시.
4. 앱 콘텐츠에서 아래를 채운다(심사에서 자주 걸리는 곳).
   - **정확한 알람(USE_EXACT_ALARM)**: 기상·취침 알람이 핵심 기능인 '알람 앱'으로 신고한다.
   - **전체 화면 알림(USE_FULL_SCREEN_INTENT)**: 알람이 울릴 때 화면을 켜는 용도로 신고한다.
   - **포그라운드 서비스(미디어 재생)**: 알람 소리를 재생하는 용도. 동작 영상 링크를 요구할 수 있다.
   - **데이터 보안**: 생활 기록(수면·식사·운동 시각)은 기기에 저장되고, 로그인하면 계정 서버(Supabase)에 백업된다. 광고·판매 없음.
   - **개인정보처리방침 주소**: 공개 웹 주소가 필요하다(웹 앱 안에 한 페이지를 만들어 쓸 수 있다).
5. 비공개 테스트(개인 계정이면 12명·14일) → 프로덕션 신청.

## 알아 둘 것

- 패키지 이름은 `com.dayset.dayset`. 한 번 올리면 바꿀 수 없다.
- 버전 번호(versionCode)는 Actions 실행 번호를 쓴다. 늘 커지므로 따로 올릴 필요가 없다.
- 직접 설치한 베타 APK와 스토어 앱은 서명이 달라서 한 휴대폰에 덮어 설치되지 않는다. 스토어 앱으로 옮길 때는 베타 앱의 기록을 계정에 올리고(로그인), 베타 앱을 지운 뒤 스토어 앱에서 로그인한다.
