# DaySet

자동으로 짜주는 일정으로 편하게 생활습관 잡기.

## 바로 열기 (웹 앱)

**https://kimoqui.github.io/Dayset/**

휴대폰에서 열고 브라우저 메뉴의 **홈 화면에 추가**를 누르면 앱처럼 열린다. 기록은 그 기기 브라우저에만 저장된다(설정 → 데이터 → 백업 내보내기로 옮길 수 있다).

## 폴더

| 폴더 | 내용 |
| --- | --- |
| `web/` | 웹 버전 소스(React + TypeScript + Vite). 작업 안내는 `web/CLAUDE.md` |
| `docs/` | GitHub Pages로 공개하는 웹 앱 빌드 결과(직접 고치지 않는다) |
| `app/` | 앱 버전 소스(Flutter, 안드로이드·iOS). 설치는 `app/SETUP.md`, 작업 안내는 `app/CLAUDE.md` |

## 웹 앱 다시 올리기

```bash
cd web
npm ci
npm test
npm run build
rm -rf ../docs && cp -r dist ../docs && touch ../docs/.nojekyll
cd .. && git add -A && git commit -m "웹 앱 갱신" && git push
```

엔진·앱 로직 규칙은 `web/`과 `app/`이 같게 유지한다. 한쪽을 바꾸면 다른 쪽도 맞춘다.
