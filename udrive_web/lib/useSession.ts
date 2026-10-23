'use client';

import { useEffect, useState } from 'react';

import { onAuthChange, session } from './auth';

/**
 * The signed-in user, read after the page has hydrated (the static HTML is
 * always the signed-out version, so server and browser markup match).
 * `ready` is false until the browser has checked.
 */
export function useSession() {
  const [state, setState] = useState<{ ready: boolean; user: { phone: string; name: string } | null }>({ ready: false, user: null });
  useEffect(() => {
    // Same object while the same person is signed in, so effects that
    // depend on `user` do not re-run on every check.
    const update = () => setState((prev) => {
      const u = session();
      const same = prev.ready && (prev.user?.phone ?? null) === (u?.phone ?? null) && (prev.user?.name ?? null) === (u?.name ?? null);
      return same ? prev : { ready: true, user: u };
    });
    update();
    const off = onAuthChange(update);
    const idle = window.setInterval(update, 60_000);
    return () => { off(); window.clearInterval(idle); };
  }, []);
  return state;
}
