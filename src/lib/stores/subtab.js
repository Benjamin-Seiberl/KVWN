import { writable, derived } from 'svelte/store';
import { page } from '$app/stores';

export const PAGE_CONFIG = {
	'/': {
		title: 'Dashboard',
		tabs: [
			{ key: 'neuigkeiten', label: 'Neuigkeiten', icon: 'newspaper' },
			{ key: 'events',      label: 'Events',      icon: 'celebration' },
		],
	},
	'/kalender': {
		title: 'Kalender',
		tabs: [
			{ key: 'events',    label: 'Events',    icon: 'calendar_month' },
			{ key: 'trainings', label: 'Trainings', icon: 'fitness_center' },
		],
	},
	'/spielbetrieb': {
		title: 'Spielbetrieb',
		tabs: [
			{ key: 'spiele',      label: 'Spiele',      icon: 'emoji_events' },
			{ key: 'turnier',     label: 'Turnier',     icon: 'military_tech' },
			{ key: 'statistiken', label: 'Statistiken', icon: 'bar_chart' },
		],
	},
	'/profil': {
		title: 'Profil',
		tabs: [
			{ key: 'meine-daten',    label: 'Meine Daten',    icon: 'person' },
			{ key: 'einstellungen',  label: 'Einstellungen',  icon: 'settings' },
			{ key: 'admin',          label: 'Kapitän',        icon: 'shield_person', adminOnly: true },
		],
	},
};

export const activeSubtabs = writable({
	'/':             'neuigkeiten',
	'/kalender':     'events',
	'/spielbetrieb': 'spiele',
	'/profil':       'meine-daten',
});

export function setSubtab(path, key) {
	activeSubtabs.update(s => ({ ...s, [path]: key }));
}

export const currentPageConfig = derived(page, ($page) => {
	return PAGE_CONFIG[$page.url.pathname] ?? null;
});

export const currentSubtab = derived([page, activeSubtabs], ([$page, $active]) => {
	return $active[$page.url.pathname] ?? null;
});
