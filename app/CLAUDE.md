# DaySet 앱(Flutter) — Claude Code 작업 안내

"자동으로 짜주는 일정으로 편하게 생활습관 잡기". 알람·'지금' 버튼으로 생활을 자동 기록하고,
매일 밤 다음 날 일정과 알람을 자동으로 만드는 앱이다. 웹 버전(dayset-web)을 앱으로 옮긴 것이다.

## 구조
```
lib/core/model     도메인 모델 (Flutter 의존 없음, JSON은 웹과 같은 형식)
lib/core/engine    일정 생성·'지금' 버튼·달성 판정·셋 데이·단계적 교정·코칭 규칙 (Flutter 의존 없음)
lib/app            앱 상태와 동작 (Flutter 의존 없음) — 웹 src/app과 1:1
  state.dart       AppState(웹 백업 JSON과 같은 구조), 저장·불러오기, 깨진 데이터 보관
  store.dart       Store: 화면이 부르는 동작 전부(웹 store.ts와 같은 이름)
  derive.dart      화면용 계산(일정, 하루 평가, 기간 통계, 관찰, 바뀜 미리보기)
  streak / social / nearby / duration / priority_model / now_check / metrics / nlp / ics / seed / goal_text
  cloud / cloud_sync 계정 연동(Supabase, 웹 cloud.ts·cloudSync.ts와 같은 규칙), cloud_config 서버 주소·공개 키
  edits.dart       일정 바꾸기 목록·적용·미리보기(그날만=overrides / 매일=goals), Store.applyEdits로 적용
  chat_command.dart 채팅 글 → 바꾸기 목록(기기 안 규칙)
  log_edit.dart    기록 시각 고치기(웹 logEdit.ts와 같은 규칙), Store.retimeLog·tapAt
  device_plan.dart 휴대폰에 맡길 알림·알람 목록(지금 일정 문구=웹 noticeFor, 일정 시작·저녁 확인 예약 알림, 기상·취침 알람=dueAlarms 규칙), 위젯 둘째 줄
  기록 이어 가기: derive.eveningAsk·todayProgress, Store.markRestAsPlanned('남은 건 일정대로 했어요'). 웹과 같은 규칙
  ai_chat.dart     로그인하면 서버 AI(supabase/functions/dayset-chat)가 먼저 읽는다: 보낼 요약·받은 답 검사, 실패하면 규칙
lib/platform       기기 연결: 파일 저장(file_store), 공유·파일 고르기(share), 홈 화면 위젯(widget_bridge), 알림 자리(notify)
  device_sync.dart 알림(flutter_local_notifications)·알람(alarm)을 device_plan 목록대로 맞춘다. 알림 버튼 → 셸이 기록(늦으면 일정 시각부터)
ci/patch_android.py  CI에서 flutter create 뒤 권한·알림 수신기·위젯(native/android 복사)·desugaring·서명(베타 키 APK / 스토어 키 AAB)을 넣는다
lib/ui             화면 — 웹 src/ui와 1:1
  theme.dart       디자인 B '나이트 링' 토큰(나이트·밝게·파스텔 다이어리). 파스텔은 외곽선·밀린 그림자(DsColors.outlined)와 DaySetPastel 글꼴
  kit.dart         공통 부품(아이콘·카드·버튼·세그먼트·스위치·아래 창·입력)
  scope.dart       context.store / context.app / context.ui, 알림 띠, 화면 이동
  app.dart         셸: 탭 6개(밀어서 이동), 일정 체크 띠, 알람 화면, 관찰 안내, 기념일
  chat.dart        말로 일정 바꾸기 창 + 습관·기상 바꾸기 창(바로 바꾸지 않고 미리보기 → '바꾸기')
  screens/         홈·일정·할 일·기록·소셜·설정 + 저녁 확인·내 하루 보기·시연·처음 설정
assets/fonts       Pretendard, 파스텔 테마용 고운돋움·주아(DaySetPastel: 보통=고운돋움, 굵게=주아). 모두 SIL OFL 1.1, 한글 2,350자 묶음
native/            flutter create 뒤 ios·android 폴더에 넣을 위젯 네이티브 코드
test/engine        엔진 테스트
test/app           앱 로직 테스트(웹 테스트를 옮긴 것) + 웹 호환 테스트(fixtures/)
```

## 원칙
- 엔진(lib/core)·앱 로직(lib/app)은 Flutter를 import하지 않는다. 규칙을 바꾸면 테스트부터 고친다.
- 엔진·앱 로직 규칙은 웹 버전과 같게 유지한다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
  `test/app/web_compat_test.dart`가 웹 예시 데이터로 결과가 같은지 확인한다(웹에서 fixtures를 다시 만들 수 있다).
- 화면은 `context.store`의 메서드만 부른다. 상태를 직접 바꾸지 않는다. 시각은 `context.ui.now`만 쓴다.
- 할 일·캘린더가 바뀌면 Store가 오늘 남은 일정과 확정한 내일 일정을 바로 다시 짠다(진행 중인 조각 유지, 15초 되돌리기).
- 알람·기록·일정 계산은 네트워크 없이 기기 안에서 끝난다. 서버는 동기화와 AI 호출만(4단계).
- 잠금·캘린더·수면 블록은 엔진이 움직이지 않는다. AI는 해석만 하고 변경은 확인 카드를 거친다.
- 문구는 '사실 + 다음 행동'. 진단·치료·처방 같은 의료 표현 금지.
- 색·글자 크기는 lib/ui/theme.dart 토큰만 쓴다. 하드코딩 금지.
- 저장은 기기 파일(앱 전용 폴더). 깨진 데이터는 지우지 않고 보관한다. 백업은 웹과 같은 JSON.

## 명령
- 테스트: `flutter test` (웹 호환 테스트는 한국 시간대에서만 돈다: `TZ=Asia/Seoul flutter test`)
- 정적 분석: `flutter analyze`
- 실행: `flutter run`

## 단계
1. (지금) 웹 기능을 앱으로 옮기기 — 엔진·로직·화면, 웹 백업 불러오기
2. 알림: (안드로이드 됨) 지금 일정 고정 알림·일정 시작 예약 알림·기록 버튼(device_sync). iOS 라이브 액티비티는 남음
3. 알람: (안드로이드 됨, alarm 패키지) 앱이 꺼져 있어도 울리기, 끄기 = 기상 기록. iOS AlarmKit은 남음
4. 서버: Supabase(익명 로그인 → 계정 연결), 친구·근처 순위 실시간, 백업 동기화
5. 베타: TestFlight·Play 내부 테스트
