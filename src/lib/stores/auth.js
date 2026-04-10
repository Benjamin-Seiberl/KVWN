import { writable } from 'svelte/store';
import { sb } from '$lib/supabase';
import { goto } from '$app/navigation';

export const user     = writable(null);
export const isMember = writable(null); // null = noch nicht geprüft

async function checkMembership(email) {
  if (!email) { isMember.set(false); return; }
  const { data } = await sb
    .from('players')
    .select('id')
    .eq('email', email)
    .maybeSingle();
  isMember.set(!!data);
}

export async function signInWithGoogle() {
  await sb.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: typeof window !== 'undefined'
        ? window.location.origin + '/'
        : '/'
    }
  });
}

export async function signOut() {
  await sb.auth.signOut();
  user.set(null);
  isMember.set(false);
  goto('/login');
}

// Session beim App-Start initialisieren
export async function initAuth() {
  const { data: { session } } = await sb.auth.getSession();
  user.set(session?.user ?? null);
  await checkMembership(session?.user?.email ?? null);

  sb.auth.onAuthStateChange(async (_event, session) => {
    user.set(session?.user ?? null);
    await checkMembership(session?.user?.email ?? null);
  });
}
