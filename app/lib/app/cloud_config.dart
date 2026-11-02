// 계정 서버(Supabase) 주소와 공개 키(anon/publishable). 공개 키는 앱에 들어가도 되는 키다(행 수준 보안으로 자기 기록만 읽고 쓴다).
// 비어 있으면 계정 기능은 '서버 준비 중'으로 보인다. 빌드할 때 --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…로 바꿀 수 있다.
const cloudUrl = String.fromEnvironment('SUPABASE_URL');
const cloudKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'sb_publishable_Mdowe50HHor1nIoGwLOlUg_pZ_6EfEk');
