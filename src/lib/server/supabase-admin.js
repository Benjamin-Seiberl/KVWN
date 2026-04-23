import { createClient } from '@supabase/supabase-js';

const URL = process.env.VITE_SUPABASE_URL ?? '';
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

/**
 * Supabase-Client mit Service-Role-Key.
 * Umgeht RLS — nur in Server-Routes verwenden.
 */
export function sbAdmin() {
	return createClient(URL, KEY, {
		auth: { persistSession: false, autoRefreshToken: false },
	});
}
