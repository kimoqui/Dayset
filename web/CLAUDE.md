# DaySet 로컬 버전 — 작업 안내

브라우저에서 동작하는 로컬 앱(React + TypeScript + Vite). 서버 없음, 저장은 localStorage.

## 원칙
- `src/engine`은 화면·저장소를 import하지 않는다. 규칙을 바꾸면 테스트부터 고친다.
- 엔진 규칙은 Flutter 버전(`dayset/lib/core`)과 같게 유지한다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
- 화면은 `src/app/store.ts`의 함수만 부른다. 상태를 직접 바꾸지 않는다.
- 하루 일정은 그 날이 시작되면(또는 전날 밤 저녁 확인·취침 기록 때) `plans[날짜]`에 고정한다.
  할 일·캘린더가 바뀌면 `store.changeAndReplan`이 오늘 남은 일정과 확정한 내일 일정을 바로 다시 짠다(진행 중인 할 일 조각은 유지, 15초 되돌리기).
  설정·목표가 바뀌면 `inputsVersion`만 올리고 화면에 '다시 짜기'를 보여준다.
- 문구는 '사실 + 다음 행동'. 진단·치료·처방 같은 의료 표현 금지.
- 디자인은 시안 B '나이트 링'. 색·글자 크기는 `src/ui/styles.css`의 변수만 쓴다(기본 나이트, 설정에서 밝게).

## 명령
- `npm run dev` / `npm test` / `npm run typecheck`
- `npm run build:single` → `dist-single/index.html` 한 파일

## 핵심 규칙 위치
- 일정 생성: `engine/scheduleBuilder.ts` (기상 = min(목표, 첫 일정 − 준비 − 이동), 할 일 75%·50분 조각)
- '지금' 버튼: `engine/nowTracker.ts` (5초 되돌리기, 10분 합치기)
- 달성 판정: `engine/achievement.ts` (±30분, 수면 90%, 추정 제외, 할 일은 진행 중 업무도 인정)
- 셋 데이: `engine/setDay.ts` (기상 ±30분 + 습관 70%)
- 교정: `engine/correction.ts` (80% 이상 올림, 50% 미만 내림, 피곤함 2회 유지)
- 코칭: `engine/coaching.ts` (R1~R9, 하루 3건, 2회 연속 거절 시 7일 쉼)
- 모션: `src/ui/motion.ts`(탭 스와이프·전환), `styles.css` 아래쪽 모션 블록(눌림·스프링). 동작 줄이기 설정을 따른다.
- 연속 기록: `src/app/streak.ts`, 친구 코드·순위: `src/app/social.ts`, 공유 카드: `src/ui/share.ts`, 화면: `src/ui/Social.tsx`.
- 시연: `src/ui/screens/Demo.tsx`, 캘린더 추가 예시안 A·B·C: `src/ui/AddEvent.tsx`, 한 줄 해석: `src/app/nlp.ts`, 바뀜 미리보기: `derive.ts`의 `comparePlans`·`eventImpact`.
- 할 일 순서: `store.reorderTasks`(순서 = rank), AI 추천: `src/app/priorityModel.ts`(3일·6건 이후, 이유를 말할 수 있는 신호만).
- 소셜 탭: `src/ui/screens/SocialTab.tsx`, 근처 익명: `src/app/nearby.ts`(별명·2km 칸·순위). 정확한 위치·실명은 저장하지 않는다.
- 걸리는 시간 보정: `src/app/duration.ts`(이름 2건·종류 3건, 중앙값, 0.5~2배, 이상값 제외). 일정 계산은 `derive.tasksForPlanning`에서 `plannedMinutes`로. 잡은 시간을 다 써도 자동 완료하지 않는다.
- 캘린더: `src/app/ics.ts`(파일 읽기), `src/app/gcal.ts`(구글), `src/app/calendarSync.ts`(동기화·오류 처리), 화면 `src/ui/CalendarConnect.tsx`. 실패해도 이전에 가져온 일정은 지우지 않는다.
- 비정상 상황 목록은 README '비정상 상황 대처'. 새 실패 경로를 만들면 거기와 `__tests__/auto.test.ts`에 같이 넣는다.
- 목표 '기타' 글 읽기: `src/app/goalText.ts`(기기 안 규칙, 읽지 못한 부분은 그대로 보여 준다). Flutter는 `lib/app/goal_text.dart`.
- 프리뷰 준비: 처음 목표·동의·알림 화면 `src/ui/Preview.tsx`, 일정 체크 `src/app/nowCheck.ts` + 팝업 `src/ui/NowDock.tsx`, 알림·푸시 토큰 `src/ui/notify.ts` + `public/sw.js`, 베타 지표 `src/app/metrics.ts`(이름·시각·제목·위치는 넣지 않는다). 동의(`consent.health`) 없이는 기록 화면으로 들어가지 않는다.
