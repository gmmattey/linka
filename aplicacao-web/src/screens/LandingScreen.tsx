import { useEffect } from 'react';
import measurementScreenshot from '../assets/screenshots/02-meca-sua-internet.jpg';
import resultScreenshot from '../assets/screenshots/01-entenda-sua-conexao.jpg';
import historyScreenshot from '../assets/screenshots/04-veja-sua-evolucao.jpg';
import { Header } from '../ui/components/layout/Header';
import { Footer } from '../ui/components/layout/Footer';

const annualPrice = import.meta.env.VITE_LINKA_PLUS_ANNUAL_PRICE ?? 'R$ 34,90';
const appStoreURL = import.meta.env.VITE_LINKA_APP_STORE_URL;

function AppStoreCallToAction({ label }: { label: string }) {
  const style: React.CSSProperties = {
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center', minHeight: 48,
    padding: '0 22px', borderRadius: 12, background: 'var(--text-primary)',
    color: 'var(--surface-page)', fontWeight: 700, fontSize: 16, textDecoration: 'none',
    boxSizing: 'border-box'
  };

  if (!appStoreURL) {
    return <span aria-label="Disponível na App Store após aprovação" style={{ ...style, opacity: 0.72 }}>{label}</span>;
  }

  return <a href={appStoreURL} style={style}>{label}</a>;
}

const featureSteps = [
  { image: measurementScreenshot, number: '01', title: 'Meça', body: 'Abra o Linka e acompanhe download, upload e latência em segundos.' },
  { image: resultScreenshot, number: '02', title: 'Entenda', body: 'O resultado fica direto para você saber como a conexão respondeu.' },
  { image: historyScreenshot, number: '03', title: 'Acompanhe', body: 'Com o Plus, consulte o histórico e compare suas medições.' }
];

export function LandingScreen() {
  useEffect(() => {
    document.title = 'Linka Speedtest — velocidade real no iPhone';
    document.querySelector('meta[name="description"]')?.setAttribute(
      'content',
      'Linka é o Speedtest para iPhone: mede download, upload e latência de forma direta.'
    );
  }, []);

  return (
    <div className="linka-landing">
      <style>{`
        .linka-landing { min-height: 100vh; color: var(--text-primary); background: var(--surface-page); font-family: var(--font-body); }
        .linka-shell { width: min(1120px, calc(100% - 48px)); margin: 0 auto; }
        .linka-hero { display: grid; grid-template-columns: minmax(0, .92fr) minmax(360px, .68fr); align-items: center; gap: clamp(48px, 9vw, 132px); padding: clamp(72px, 11vw, 152px) 0 clamp(88px, 12vw, 152px); }
        .linka-eyebrow { margin: 0 0 20px; color: var(--brand-accent-warm); font: 600 12px/1.2 var(--font-mono); letter-spacing: .14em; text-transform: uppercase; }
        .linka-hero h1 { max-width: 660px; margin: 0; font: 700 clamp(50px, 7vw, 86px)/.98 var(--font-display); letter-spacing: -.05em; text-wrap: balance; }
        .linka-lede { max-width: 510px; margin: 28px 0 34px; color: var(--text-secondary); font-size: clamp(18px, 2vw, 21px); line-height: 1.55; text-wrap: pretty; }
        .linka-availability { margin: 14px 0 0; color: var(--text-secondary); font-size: 14px; }
        .linka-screen { width: min(100%, 390px); justify-self: center; border-radius: 36px; box-shadow: 0 22px 70px color-mix(in srgb, #000 42%, transparent); }
        .linka-section { padding: clamp(72px, 10vw, 128px) 0; border-top: 1px solid var(--border-default); }
        .linka-section-heading { max-width: 680px; margin-bottom: 48px; }
        .linka-section-heading h2, .linka-plus h2 { margin: 0; font: 700 clamp(34px, 5vw, 58px)/1.04 var(--font-display); letter-spacing: -.04em; text-wrap: balance; }
        .linka-section-heading p, .linka-plus-copy { max-width: 620px; margin: 18px 0 0; color: var(--text-secondary); font-size: 18px; line-height: 1.6; }
        .linka-steps { display: grid; grid-template-columns: repeat(3, 1fr); gap: 24px; }
        .linka-step { min-width: 0; }
        .linka-step-image { display: block; width: 100%; aspect-ratio: .54; object-fit: cover; object-position: top; border-radius: 26px; background: var(--surface-card); }
        .linka-step-number { display: block; margin-top: 22px; color: var(--brand-accent-warm); font: 600 12px/1 var(--font-mono); letter-spacing: .12em; }
        .linka-step h3 { margin: 10px 0 8px; font: 700 24px/1.15 var(--font-display); letter-spacing: -.02em; }
        .linka-step p { margin: 0; color: var(--text-secondary); font-size: 16px; line-height: 1.55; }
        .linka-plus { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .75fr); gap: clamp(36px, 7vw, 100px); align-items: end; }
        .linka-price { margin: 0; font: 700 clamp(38px, 5vw, 58px)/1 var(--font-display); letter-spacing: -.045em; }
        .linka-price small { font: 500 18px/1 var(--font-body); letter-spacing: 0; color: var(--text-secondary); }
        .linka-renewal { margin: 16px 0 0; color: var(--text-secondary); font-size: 15px; line-height: 1.55; }
        .linka-legal-links { display: flex; flex-wrap: wrap; gap: 18px; margin-top: 28px; font-size: 14px; }
        .linka-legal-links a { color: var(--text-secondary); }
        @media (max-width: 760px) {
          .linka-shell { width: min(100% - 40px, 560px); }
          .linka-hero, .linka-plus { grid-template-columns: 1fr; }
          .linka-hero { padding-top: 72px; }
          .linka-screen { width: min(80%, 340px); grid-row: 1; }
          .linka-hero-copy { grid-row: 2; }
          .linka-steps { grid-template-columns: 1fr; gap: 44px; }
          .linka-step { display: grid; grid-template-columns: 132px 1fr; column-gap: 20px; align-items: start; }
          .linka-step-image { grid-row: span 3; border-radius: 18px; }
          .linka-step-number { margin-top: 2px; }
          .linka-step h3 { margin-top: 8px; }
        }
      `}</style>

      <Header maxWidth={1120} />
      <main>
        <section className="linka-shell linka-hero">
          <div className="linka-hero-copy">
            <p className="linka-eyebrow">Linka Speedtest</p>
            <h1>Velocidade real. Sem complicação.</h1>
            <p className="linka-lede">O Linka mede download, upload e latência no seu iPhone de forma rápida, clara e sem cadastro.</p>
            <AppStoreCallToAction label={appStoreURL ? 'Baixar na App Store' : 'Em breve na App Store'} />
            <p className="linka-availability">O teste é gratuito. Sem limite de medições.</p>
          </div>
          <img className="linka-screen" src={measurementScreenshot} alt="Tela do Linka medindo a velocidade da internet" />
        </section>

        <section id="como-funciona" className="linka-shell linka-section">
          <div className="linka-section-heading">
            <p className="linka-eyebrow">Como funciona</p>
            <h2>Três passos. Tudo no seu iPhone.</h2>
            <p>O essencial, bem feito: medir, ver o resultado e decidir o que fazer com ele.</p>
          </div>
          <div className="linka-steps">
            {featureSteps.map((step) => (
              <article className="linka-step" key={step.number}>
                <img className="linka-step-image" src={step.image} alt="" />
                <span className="linka-step-number">{step.number}</span>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section id="planos" className="linka-shell linka-section">
          <div className="linka-plus">
            <div>
              <p className="linka-eyebrow">Linka Plus</p>
              <h2>Mais contexto para a sua conexão.</h2>
              <p className="linka-plus-copy">O Linka Plus libera histórico completo, comparação entre medições e o Assist para interpretar os resultados. O teste continua útil e gratuito para todo mundo.</p>
            </div>
            <div>
              <p className="linka-price">{annualPrice} <small>por ano</small></p>
              <p className="linka-renewal">Assinatura com renovação automática. Cobrança e gerenciamento pela Apple.</p>
              <div style={{ marginTop: 26 }}><AppStoreCallToAction label={appStoreURL ? 'Assinar na App Store' : 'Disponível após aprovação'} /></div>
              <nav className="linka-legal-links" aria-label="Informações da assinatura">
                <a href="/termos">Termos de Uso</a>
                <a href="/privacidade">Privacidade</a>
                <a href="/suporte">Suporte</a>
              </nav>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
