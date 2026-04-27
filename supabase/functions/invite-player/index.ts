// Edge Function: invite-player
//
// Captain-gated player invite. Sends a Supabase magic-link invite via the
// auth admin API and upserts the player row so the club roster knows about
// the new member before they ever click the link.
//
// Caller: src/lib/components/admin/AdminRollen.svelte → sendInvite()
// POST   { email, name, role }
// Auth   Bearer <user access_token>  — must belong to a player with role
//        'kapitaen' or 'admin' (matched by email on public.players).
//
// Returns { ok: true, player_id }  on success
//         { ok: false, error }     on failure (4xx/5xx)
//
// Deploy: supabase functions deploy invite-player
// Env:    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
//         (Supabase populates these automatically inside the Edge runtime.)

// @ts-nocheck — Deno runtime, no project tsconfig.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
	'Access-Control-Allow-Origin':  '*',
	'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
	'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(payload: unknown, status = 200) {
	return new Response(JSON.stringify(payload), {
		status,
		headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
	});
}

Deno.serve(async (req) => {
	if (req.method === 'OPTIONS') {
		return new Response('ok', { headers: CORS_HEADERS });
	}
	if (req.method !== 'POST') {
		return json({ ok: false, error: 'method not allowed' }, 405);
	}

	const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')              ?? '';
	const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
	const ANON_KEY          = Deno.env.get('SUPABASE_ANON_KEY')         ?? '';

	if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
		return json({ ok: false, error: 'edge function nicht konfiguriert' }, 500);
	}

	// 1. Captain-Gate: prüfe, dass der Aufrufer ein Kapitän/Admin ist.
	const auth = req.headers.get('Authorization') ?? '';
	if (!auth.startsWith('Bearer ')) {
		return json({ ok: false, error: 'nicht angemeldet' }, 401);
	}

	const userClient = createClient(SUPABASE_URL, ANON_KEY, {
		global: { headers: { Authorization: auth } },
		auth:   { persistSession: false, autoRefreshToken: false },
	});

	const { data: userData, error: userErr } = await userClient.auth.getUser();
	if (userErr || !userData?.user?.email) {
		return json({ ok: false, error: 'nicht angemeldet' }, 401);
	}

	const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
		auth: { persistSession: false, autoRefreshToken: false },
	});

	const { data: caller } = await admin
		.from('players')
		.select('id, role')
		.eq('email', userData.user.email)
		.maybeSingle();

	if (!caller || !['kapitaen', 'admin'].includes(caller.role)) {
		return json({ ok: false, error: 'nur Kapitän/Admin' }, 403);
	}

	// 2. Body parsen + validieren.
	let body: { email?: string; name?: string | null; role?: string } = {};
	try {
		body = await req.json();
	} catch {
		return json({ ok: false, error: 'invalid json' }, 400);
	}

	const email = (body.email ?? '').trim().toLowerCase();
	const name  = (body.name ?? '').trim() || null;
	const role  = body.role === 'kapitaen' ? 'kapitaen' : 'user';

	if (!email || !email.includes('@')) {
		return json({ ok: false, error: 'gültige E-Mail erforderlich' }, 400);
	}

	// 3. Upsert player row (idempotent — wenn Spieler schon existiert, role/name mergen).
	//    UNIQUE-Constraint auf email kann fehlen — daher manuell suchen + insert/update.
	const { data: existing } = await admin
		.from('players')
		.select('id, name, role, active')
		.eq('email', email)
		.maybeSingle();

	let playerId: string;

	if (existing) {
		const patch: Record<string, unknown> = { active: true };
		if (name)                       patch.name = name;
		if (role && role !== existing.role) patch.role = role;

		const { error: upErr } = await admin
			.from('players')
			.update(patch)
			.eq('id', existing.id);

		if (upErr) {
			return json({ ok: false, error: 'spieler-update: ' + upErr.message }, 500);
		}
		playerId = existing.id;
	} else {
		const { data: inserted, error: insErr } = await admin
			.from('players')
			.insert({
				email,
				name:   name ?? email.split('@')[0],
				role,
				active: true,
			})
			.select('id')
			.maybeSingle();

		if (insErr || !inserted) {
			return json({ ok: false, error: 'spieler-insert: ' + (insErr?.message ?? 'unbekannt') }, 500);
		}
		playerId = inserted.id;
	}

	// 4. Magic-Link Invite via Auth Admin API.
	//    inviteUserByEmail sendet eine E-Mail mit Setup-Link;
	//    user_metadata wird beim Auth-User gesetzt (nicht in players).
	const { error: inviteErr } = await admin.auth.admin.inviteUserByEmail(email, {
		data: { name: name ?? '', role },
	});

	if (inviteErr) {
		// "already registered" ist kein Fail — Spieler-Row steht, User existiert in auth.
		const msg = inviteErr.message ?? '';
		const alreadyRegistered =
			/already.*registered/i.test(msg) ||
			/already.*exist/i.test(msg) ||
			/User already registered/i.test(msg);

		if (!alreadyRegistered) {
			return json({ ok: false, error: 'invite: ' + msg }, 500);
		}
	}

	return json({ ok: true, player_id: playerId });
});
