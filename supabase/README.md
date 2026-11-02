# Supabase 설정

## 1. 계정 동기화 표
SQL Editor에서 `dayset_state` 표와 RLS 정책을 만든다(앞서 보낸 SQL). Authentication → Providers → Email에서 Confirm email은 끈다.

## 2. AI 일정 바꾸기 함수 (선택)
로그인한 사용자가 '말로 일정 바꾸기'를 쓰면 Claude가 읽는다. 없으면 기기 안 규칙으로 읽는다.

1. Edge Functions → Deploy a new function → 이름 `dayset-chat` → `functions/dayset-chat/index.ts` 내용을 붙여넣고 Deploy.
   함수 설정에서 **Verify JWT(Enforce JWT verification)는 끈다** — 함수 안에서 로그인을 직접 확인한다.
   (CLI: `supabase functions deploy dayset-chat` — config.toml에 verify_jwt = false)
2. Edge Functions → Secrets → `ANTHROPIC_API_KEY` = console.anthropic.com에서 만든 키.
3. 선택: `DAYSET_AI_MODEL` (기본 `claude-haiku-5-5`).

AI는 해석만 한다. 앱이 돌려받은 목록을 검사하고 미리보기를 보여 준 뒤, 사용자가 '바꾸기'를 눌러야 바뀐다.
보내는 것: 사용자가 적은 말, 오늘부터 사흘 식사·운동·기상 시각, 7일 캘린더 일정 제목·시각, 할 일 제목. 생활 기록·건강 정보는 보내지 않는다.
