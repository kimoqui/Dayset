import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { isGetAppLink } from './app/appLinks';
import { App } from './ui/App';
import { GetAppPage } from './ui/GetApp';
import './ui/styles.css';

/** QR(?get=app)로 열면 먼저 앱 받는 곳을 보여 주고, '웹에서 계속 쓰기'를 누르면 평소 화면으로. */
function Root() {
  const [getApp, setGetApp] = useState(() => isGetAppLink());
  if (getApp)
    return (
      <GetAppPage
        onContinue={() => {
          history.replaceState(null, '', location.pathname);
          setGetApp(false);
        }}
      />
    );
  return <App />;
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);

// 설치형(PWA)으로 쓸 때 오프라인에서도 열리게 한다. 파일로 열면(file://) 건너뛴다.
if ('serviceWorker' in navigator && location.protocol.startsWith('http') && import.meta.env.PROD) {
  navigator.serviceWorker.register('./sw.js').catch(() => undefined);
}
