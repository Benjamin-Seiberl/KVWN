// Service Worker für Web-Push
self.addEventListener('install', (e) => { self.skipWaiting(); });
self.addEventListener('activate', (e) => { e.waitUntil(self.clients.claim()); });

self.addEventListener('push', (event) => {
	let payload = {};
	try { payload = event.data?.json() ?? {}; } catch { payload = { title: 'KVWN', body: event.data?.text() ?? '' }; }
	const title = payload.title || 'KV Wiener Neustadt';
	const options = {
		body: payload.body || '',
		icon: '/favicon.png',
		badge: '/favicon.png',
		data: { link: payload.link || '/' },
	};
	event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
	event.notification.close();
	const link = event.notification.data?.link || '/';
	event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
		for (const c of list) {
			if ('focus' in c) { c.navigate(link); return c.focus(); }
		}
		if (clients.openWindow) return clients.openWindow(link);
	}));
});
