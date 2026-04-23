import { createClient } from '@supabase/supabase-js';
import { sbAdmin } from '$lib/server/supabase-admin.js';
import { createEvent, updateEvent, deleteEvent } from '$lib/server/gcal.js';

const SUPABASE_URL      = process.env.VITE_SUPABASE_URL      ?? '';
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY ?? '';

function jsonResponse(payload, status = 200) {
	return new Response(JSON.stringify(payload), {
		status,
		headers: { 'Content-Type': 'application/json' },
	});
}

/**
 * Captain-Check: holt User via Bearer-Token, matched gegen players.email
 * und verlangt role in ('kapitaen','admin'). Returnt { ok, user, player } oder
 * ein Response-Objekt wenn nicht autorisiert.
 */
async function requireCaptain(request) {
	const auth = request.headers.get('authorization') ?? '';
	if (!auth.startsWith('Bearer ')) {
		return { response: jsonResponse({ error: 'unauthorized' }, 401) };
	}

	const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
		global: { headers: { Authorization: auth } },
		auth:   { persistSession: false, autoRefreshToken: false },
	});

	const { data: userData, error: userErr } = await client.auth.getUser();
	if (userErr || !userData?.user?.email) {
		return { response: jsonResponse({ error: 'unauthorized' }, 401) };
	}

	const admin = sbAdmin();
	const { data: player } = await admin
		.from('players')
		.select('id, role')
		.eq('email', userData.user.email)
		.maybeSingle();

	if (!player || !['kapitaen', 'admin'].includes(player.role)) {
		return { response: jsonResponse({ error: 'forbidden' }, 403) };
	}

	return { user: userData.user, player, admin };
}

export async function POST({ request }) {
	const guard = await requireCaptain(request);
	if (guard.response) return guard.response;
	const { admin } = guard;

	let body;
	try {
		body = await request.json();
	} catch {
		return jsonResponse({ error: 'invalid json' }, 400);
	}

	const { title, date, time, location, description } = body ?? {};
	if (!title || !date) {
		return jsonResponse({ error: 'title und date sind pflicht' }, 400);
	}

	try {
		const { id: external_id, etag } = await createEvent({
			title, date, time, location, description,
		});

		const row = {
			title,
			date,
			time:        time || null,
			location:    location || null,
			description: description || null,
			external_id,
			source:      'gcal',
			etag:        etag ?? null,
			synced_at:   new Date().toISOString(),
		};

		const { data: inserted, error } = await admin
			.from('events')
			.insert(row)
			.select('id, external_id')
			.maybeSingle();

		if (error) {
			// Rollback: das Google-Event wieder entfernen, damit kein Waise bleibt
			try { await deleteEvent(external_id); }
			catch (e) { console.error('gcal rollback failed', e); }
			return jsonResponse({ error: error.message }, 500);
		}

		return jsonResponse({ id: inserted?.id, external_id });
	} catch (err) {
		return jsonResponse({ error: err?.message ?? 'create failed' }, 500);
	}
}

export async function PATCH({ request }) {
	const guard = await requireCaptain(request);
	if (guard.response) return guard.response;
	const { admin } = guard;

	let body;
	try {
		body = await request.json();
	} catch {
		return jsonResponse({ error: 'invalid json' }, 400);
	}

	const { id, patch } = body ?? {};
	if (!id || !patch || typeof patch !== 'object') {
		return jsonResponse({ error: 'id und patch sind pflicht' }, 400);
	}

	const { data: existing, error: lookupErr } = await admin
		.from('events')
		.select('id, external_id, title, date, time, location, description')
		.eq('id', id)
		.maybeSingle();
	if (lookupErr || !existing) {
		return jsonResponse({ error: 'event not found' }, 404);
	}
	if (!existing.external_id) {
		return jsonResponse({ error: 'event ist nicht mit google verknüpft' }, 400);
	}

	// Nur whitelisted Felder erlauben
	const allowed = ['title','date','time','location','description'];
	const clean = {};
	for (const k of allowed) {
		if (k in patch) clean[k] = patch[k];
	}

	// Google-Resource aus merged Shape bauen (für Start/End-Berechnung
	// brauchen wir das effektive date/time).
	const merged = { ...existing, ...clean };

	try {
		const { etag } = await updateEvent(existing.external_id, {
			title:       merged.title,
			date:        merged.date,
			time:        merged.time,
			location:    merged.location,
			description: merged.description,
		});

		const rowPatch = {
			...clean,
			etag:      etag ?? existing.etag ?? null,
			synced_at: new Date().toISOString(),
		};
		// time explizit null erlauben
		if ('time' in clean && (clean.time === '' || clean.time == null)) {
			rowPatch.time = null;
		}

		const { error } = await admin
			.from('events')
			.update(rowPatch)
			.eq('id', id);

		if (error) return jsonResponse({ error: error.message }, 500);

		return jsonResponse({ id, external_id: existing.external_id });
	} catch (err) {
		return jsonResponse({ error: err?.message ?? 'update failed' }, 500);
	}
}

export async function DELETE({ request }) {
	const guard = await requireCaptain(request);
	if (guard.response) return guard.response;
	const { admin } = guard;

	let body;
	try {
		body = await request.json();
	} catch {
		return jsonResponse({ error: 'invalid json' }, 400);
	}

	const { id } = body ?? {};
	if (!id) return jsonResponse({ error: 'id ist pflicht' }, 400);

	const { data: existing, error: lookupErr } = await admin
		.from('events')
		.select('id, external_id')
		.eq('id', id)
		.maybeSingle();
	if (lookupErr || !existing) {
		return jsonResponse({ error: 'event not found' }, 404);
	}

	try {
		if (existing.external_id) {
			await deleteEvent(existing.external_id); // swallows 410
		}
		const { error } = await admin.from('events').delete().eq('id', id);
		if (error) return jsonResponse({ error: error.message }, 500);
		return jsonResponse({ id });
	} catch (err) {
		return jsonResponse({ error: err?.message ?? 'delete failed' }, 500);
	}
}
