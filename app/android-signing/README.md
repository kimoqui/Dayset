# 베타 서명 키

`dayset-beta.keystore`는 GitHub Actions가 만드는 베타 APK에 서명하는 키다.
늘 같은 키로 서명해야 새 APK를 설치할 때 기존 앱(과 기록)을 지우지 않고 업데이트된다.

- 형식: 안드로이드 디버그 키와 같은 이름·암호(별칭 `androiddebugkey`, 암호 `android`). CI에서 `~/.android/debug.keystore`로 복사해 쓴다.
- 공개 저장소에 있는 베타용 키다. Play 스토어에 올릴 때는 새 키를 만들어 GitHub Secrets에 넣고 이 키는 쓰지 않는다.
