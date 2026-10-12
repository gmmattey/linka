import { InfoScreen } from './screens/InfoScreen';
import { NotFoundScreen } from './screens/NotFoundScreen';
import { PrototypeScreen } from './screens/PrototypeScreen';
import { prototypePages } from './generated/prototypePages';

const infoRoutes = new Set(['/sobre', '/como-medimos', '/privacidade', '/termos', '/suporte', '/casawifi/privacidade']);

export default function App() {
  const pathname = window.location.pathname.replace(/\/$/, '') || '/';

  if (pathname === '/privacidade' || pathname === '/termos') {
    return <InfoScreen pathname={pathname} />;
  }

  if (prototypePages[pathname]) {
    return <PrototypeScreen pathname={pathname} />;
  }

  if (pathname === '/casawifi' || pathname === '/casawifi/privacidade') {
    return <InfoScreen pathname="/casawifi/privacidade" />;
  }

  if (infoRoutes.has(pathname)) {
    return <InfoScreen pathname={pathname} />;
  }

  return <NotFoundScreen />;
}
