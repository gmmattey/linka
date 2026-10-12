import { useEffect, useRef } from 'react';
import { prototypePages } from '../generated/prototypePages';

export function PrototypeScreen({ pathname }: { pathname: string }) {
  const page = prototypePages[pathname];
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    document.title = page.title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', page.description);
  }, [page]);

  function onClick(event: React.MouseEvent<HTMLDivElement>) {
    const button = (event.target as Element).closest('button');
    if (!button || !root.current?.contains(button)) return;

    if (button.hasAttribute('data-faq')) {
      const answer = button.nextElementSibling as HTMLElement | null;
      const icon = button.querySelector('span:last-child') as HTMLElement | null;
      if (!answer) return;
      const opening = answer.style.maxHeight === '0px' || !answer.style.maxHeight;
      answer.style.maxHeight = opening ? `${answer.scrollHeight + 24}px` : '0px';
      answer.style.paddingBottom = opening ? '20px' : '0px';
      if (icon) icon.style.transform = opening ? 'rotate(45deg)' : 'none';
      button.setAttribute('aria-expanded', String(opening));
      return;
    }

    const index = button.getAttribute('data-assist-index');
    if (index === null || !page.examples) return;
    const example = page.examples[Number(index)];
    const card = root.current?.querySelector('[data-assist-card]');
    if (!example || !card) return;
    const paragraphs = card.querySelectorAll(':scope > p');
    if (paragraphs[0]) paragraphs[0].textContent = example.tag;
    if (paragraphs[1]) paragraphs[1].textContent = example.head;
    if (paragraphs[2]) paragraphs[2].textContent = example.why;
    card.querySelectorAll(':scope > div').forEach((step, number) => {
      const text = step.querySelector('span:last-child');
      if (text) text.textContent = example.steps[number] ?? '';
    });
    root.current.querySelectorAll<HTMLButtonElement>('[data-assist-index]').forEach((choice) => {
      const selected = choice === button;
      choice.style.border = selected ? '1px solid var(--ink)' : '0.5px solid var(--border)';
      choice.style.background = selected ? 'var(--ink)' : 'var(--card)';
      choice.style.color = selected ? 'var(--on)' : 'var(--ink)';
      choice.setAttribute('aria-pressed', String(selected));
    });
  }

  return (
    <div className="prototype-page" ref={root} onClick={onClick}>
      <style>{`${page.style}
        .prototype-page { min-height: 100vh; }
        .prototype-page *, .prototype-page *::before, .prototype-page *::after { box-sizing: border-box; }
        .prototype-page img { max-width: 100%; }
        .prototype-page [data-faq] { font-family: inherit; }
        @media (max-width: 720px) {
          .prototype-page header { height: auto !important; min-height: 52px; }
          .prototype-page header > div { flex-wrap: wrap; padding-bottom: 10px !important; justify-content: center !important; }
          .prototype-page header nav { flex-wrap: wrap; justify-content: center; gap: 10px 18px !important; }
          .prototype-page section { scroll-margin-top: 105px; }
        }
        @media (prefers-reduced-motion: reduce) {
          .prototype-page *, .prototype-page *::before, .prototype-page *::after { animation-duration: .01ms !important; transition-duration: .01ms !important; scroll-behavior: auto !important; }
        }
      `}</style>
      <div dangerouslySetInnerHTML={{ __html: page.html }} />
    </div>
  );
}
