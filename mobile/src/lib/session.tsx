// Who is signed in, and in which role. Roles come from the database (school_members),
// and the database enforces them; the app only uses them to choose which screens to show.
import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';
import type { Membership, Role } from './types';

interface SessionState {
  ready: boolean;
  session: Session | null;
  memberships: Membership[];
  active: Membership | null;
  isStaff: boolean;
  setActive: (m: Membership) => void;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
}

const Ctx = createContext<SessionState | null>(null);
const ROLE_ORDER: Role[] = ['admin', 'coach', 'guardian', 'student'];

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);

  async function loadMemberships(s: Session | null) {
    if (!s) { setMemberships([]); setActiveId(null); return; }
    const { data } = await supabase
      .from('school_members')
      .select('id, school_id, role, display_name, status, schools(name)')
      .eq('user_id', s.user.id)
      .eq('status', 'active');
    const rows = ((data ?? []) as unknown as Membership[]).sort(
      (a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role),
    );
    setMemberships(rows);
    setActiveId((cur) => (cur && rows.some((r) => r.id === cur) ? cur : rows[0]?.id ?? null));
  }

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSession(data.session);
      await loadMemberships(data.session);
      setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
      // Defer the query so it runs outside the auth callback.
      setTimeout(() => { loadMemberships(s); }, 0);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const value = useMemo<SessionState>(() => {
    const active = memberships.find((m) => m.id === activeId) ?? null;
    return {
      ready,
      session,
      memberships,
      active,
      isStaff: active?.role === 'admin' || active?.role === 'coach',
      setActive: (m) => setActiveId(m.id),
      refresh: () => loadMemberships(session),
      signOut: async () => { await supabase.auth.signOut(); },
    };
  }, [ready, session, memberships, activeId]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSession(): SessionState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useSession must be used inside SessionProvider');
  return v;
}
