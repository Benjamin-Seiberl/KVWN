import { writable } from 'svelte/store';
import { sb } from '$lib/supabase';
import { goto } from '$app/navigation';

export const user       = writable(null);
export const isMember   = writable(null);   // null = noch nicht geprüft
export const playerRole = writable('user'); // 'user' | 'kapitaen'
export const playerId   = writable(null);

async function checkMembership(email) {
  if (!email) {
    isMember.set(false);
    playerRole.set('user');
    playerId.set(null);
    return;
  }
  const { data } = await sb
    .from('players')
    .select('id, role')
    .eq('email', email)
    .maybeSingle();
  isMember.set(!!data);
  playerRole.set(data?.role ?? 'user');
  playerId.set(data?.id ?? null);
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
  playerRole.set('user');
  playerId.set(null);
  goto('/login');
}

export async function initAuth() {
  const { data: { session } } = await sb.auth.getSession();
  user.set(session?.user ?? null);
  await checkMembership(session?.user?.email ?? null);

  sb.auth.onAuthStateChange(async (_event, session) => {
    user.set(session?.user ?? null);
    await checkMembership(session?.user?.email ?? null);
  });
}
