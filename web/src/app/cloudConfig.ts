// 계정 서버(Supabase) 주소와 공개 키(anon/publishable). 공개 키는 앱에 들어가도 되는 키다(행 수준 보안으로 자기 기록만 읽고 쓴다).
// 비어 있으면 계정 기능은 '서버 준비 중'으로 보인다. 빌드할 때 VITE_SUPABASE_URL·VITE_SUPABASE_KEY로 바꿀 수 있다.
export const CLOUD_URL: string = import.meta.env.VITE_SUPABASE_URL ?? '';
export const CLOUD_KEY: string = import.meta.env.VITE_SUPABASE_KEY ?? 'sb_publishable_Mdowe50HHor1nIoGwLOlUg_pZ_6EfEk';
