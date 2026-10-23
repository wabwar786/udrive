'use client';

import type { ListingHome } from '@/lib/types';
import { FilePick, Msg, upload, useAction } from './ui';

const DOCS = [
  ['cnic-front', 'CNIC — front', 'cnicFront'],
  ['cnic-back', 'CNIC — back', 'cnicBack'],
  ['selfie', 'Selfie (your face, clear)', 'selfie'],
  ['licence-front', 'Driving licence — front', 'licenceFront'],
  ['licence-back', 'Driving licence — back', 'licenceBack'],
] as const;

export function Documents({ home, reload }: { home: ListingHome | null; reload: () => Promise<void> }) {
  const a = useAction();
  if (!home) return <div className="skel" style={{ minHeight: 300 }} />;
  const o = home.owner;
  async function send(kind: string, file: File) {
    await a.run(async () => { await upload(`/api/v1/listings/owner/documents/${kind}`, file); await reload(); }, 'Uploaded.');
  }
  return (
    <>
      <div className="acctHead"><div><h1>Documents</h1><p className="muted">Uploaded once, used for all your vehicles. Seen only by the UDrive team — never on the website.</p></div></div>
      <Msg error={a.error} ok={a.ok} />
      <div className="fgrid">
        {DOCS.map(([kind, label, key]) => <FilePick key={kind} label={label} done={o[key]} onFile={(f) => send(kind, f)} disabled={a.busy} />)}
      </div>
      <p className="note2">Licence is needed only if you drive your vehicles yourself. {o.licenceNumber ? `Licence on file: ${o.licenceNumber}${o.licenceExpiry ? `, valid until ${o.licenceExpiry}` : ''}.` : ''}</p>
      {o.agreementAccepted && <div className="msg ok">Owner agreement accepted (version {o.agreementVersion}).</div>}
    </>
  );
}
