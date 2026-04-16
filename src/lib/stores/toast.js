import { writable } from 'svelte/store';

export const toastMessage = writable('');
export const isToastActive = writable(false);

let timer = null;

/**
 * Triggert einen Dynamic-Island-Toast.
 * Schließt offene Sheets/Pill-Menüs, wartet 300ms,
 * dann morph die Pille in den Toast-Zustand für 3s.
 */
export function triggerToast(message) {
	if (timer) clearTimeout(timer);

	// Toast sofort vorbereiten (Sheet/Pill-Close passiert im Consumer)
	toastMessage.set(message);
	isToastActive.set(true);

	timer = setTimeout(() => {
		isToastActive.set(false);
		timer = null;
	}, 3000);
}
