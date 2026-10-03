import type { ReactNode } from 'react';

/**
 * Renders a partner contract's stored Markdown as readable text.
 *
 * It exists because of what the first screenshot of the signing page showed: the
 * partner was being asked to read `## 3. Security deposit` and
 * `**Reference:** UD-PT-…` and then say out loud that they had read and accepted
 * all of it. The stars and hashes are an implementation detail of how the text is
 * stored; nobody should be signing around them.
 *
 * Deliberately tiny, and deliberately not a Markdown library:
 *
 * - This renders exactly what the templates use — headings, bold, bullets,
 *   paragraphs — and nothing else. A full parser is a dependency, a bundle, and a
 *   much larger surface, for one document.
 * - Nothing goes through `dangerouslySetInnerHTML`. The text comes out of the
 *   database, an admin can edit it before sending, and this is the screen where
 *   somebody's signature is captured. Everything here is React elements, so a
 *   stray `<script>` in a contract is text on the page and nothing more.
 *
 * Anything it does not recognise is shown as the plain line it is, which is the
 * right failure: an unrendered sentence still reads, an eaten one does not.
 */
export function ContractText({ text }: { text: string }) {
  const blocks: ReactNode[] = [];
  const lines = text.replace(/\r\n/g, '\n').split('\n');

  let paragraph: string[] = [];
  let bullets: string[] = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    // A single newline is a line break here, not a space.
    //
    // Markdown would join these into one paragraph, and that is what the first
    // render did: the reference, the partner, the territory and the date all ran
    // together into one line of soup at the top of the agreement. Whoever writes
    // a contract in the admin editor puts those on separate lines because they
    // mean them to be on separate lines.
    blocks.push(
      <p key={`p${blocks.length}`}>
        {paragraph.map((line, index) => (
          <span key={index}>
            {index > 0 && <br />}
            {inline(line)}
          </span>
        ))}
      </p>,
    );
    paragraph = [];
  };

  const flushBullets = () => {
    if (bullets.length === 0) return;
    blocks.push(
      <ul key={`u${blocks.length}`}>
        {bullets.map((item, index) => (
          <li key={index}>{inline(item)}</li>
        ))}
      </ul>,
    );
    bullets = [];
  };

  for (const raw of lines) {
    const line = raw.trimEnd();

    if (line.trim() === '') {
      flushBullets();
      flushParagraph();
      continue;
    }

    if (line.startsWith('## ')) {
      flushBullets();
      flushParagraph();
      blocks.push(<h3 key={`h${blocks.length}`}>{inline(line.slice(3))}</h3>);
      continue;
    }

    if (line.startsWith('# ')) {
      flushBullets();
      flushParagraph();
      blocks.push(<h2 key={`h${blocks.length}`}>{inline(line.slice(2))}</h2>);
      continue;
    }

    if (line.startsWith('- ') || line.startsWith('* ')) {
      flushParagraph();
      bullets.push(line.slice(2));
      continue;
    }

    // A wrapped bullet keeps belonging to the bullet above it.
    if (bullets.length > 0) {
      bullets.push(line);
    } else {
      paragraph.push(line.trim());
    }
  }

  flushBullets();
  flushParagraph();

  return <div className="contractDoc">{blocks}</div>;
}

/** `**bold**` and `_italic_`, which is all the templates use inside a line. */
function inline(text: string): ReactNode[] {
  const parts: ReactNode[] = [];
  const pattern = /(\*\*[^*]+\*\*|_[^_]+_)/g;
  let last = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > last) parts.push(text.slice(last, match.index));
    const token = match[0];
    parts.push(
      token.startsWith('**') ? (
        <strong key={`${match.index}b`}>{token.slice(2, -2)}</strong>
      ) : (
        <em key={`${match.index}i`}>{token.slice(1, -1)}</em>
      ),
    );
    last = match.index + token.length;
  }

  if (last < text.length) parts.push(text.slice(last));
  return parts;
}
