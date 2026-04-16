import { sb } from '$lib/supabase';

// VAPID Public-Key wird via env ausgelesen. Setze VITE_VAPID_PUBLIC_KEY.
const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY ?? '';

function urlBase64ToUint8Array(base64String) {
	const padding = '='.repeat((4 - base64String.length % 4) % 4);
	const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
	const rawData = atob(base64);
	const out = new Uint8Array(rawData.length);
	for (let i = 0; i < rawData.length; i++) out[i] = rawData.charCodeAt(i);
	return out;
}

export async function ensureSW() {
	if (!('serviceWorker' in navigator)) throw new Error('Service Worker nicht verfügbar');
	return navigator.serviceWorker.register('/sw.js');
}

export async function pushStatus() {
	if (!('serviceWorker' in navigator) || !('PushManager' in window)) return false;
	try {
		const reg = await navigator.serviceWorker.getRegistration('/sw.js');
		if (!reg) return false;
		const sub = await reg.pushManager.getSubscription();
		return !!sub;
	} catch { return false; }
}

export async function registerPush(playerId) {
	if (!playerId) throw new Error('Kein Spieler verknüpft');
	if (!VAPID_PUBLIC_KEY) throw new Error('VAPID-Public-Key fehlt (Env: VITE_VAPID_PUBLIC_KEY)');
	const perm = await Notification.requestPermission();
	if (perm !== 'granted') throw new Error('Benachrichtigung nicht erlaubt');
	const reg = await ensureSW();
	const sub = await reg.pushManager.subscribe({
		userVisibleOnly: true,
		applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
	});
	const json = sub.toJSON();
	await sb.from('push_subscriptions').upsert({
		player_id: playerId,
		endpoint:  json.endpoint,
		p256dh:    json.keys?.p256dh,
		auth:      json.keys?.auth,
	}, { onConflict: 'endpoint' });
}

export async function unregisterPush() {
	const reg = await navigator.serviceWorker.getRegistration('/sw.js');
	if (!reg) return;
	const sub = await reg.pushManager.getSubscription();
	if (sub) {
		await sb.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
		await sub.unsubscribe();
	}
}
