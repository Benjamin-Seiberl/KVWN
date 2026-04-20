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
			{ key: 'uebersicht', label: 'Übersicht',  icon: 'dashboard'      },
			{ key: 'events',     label: 'Events',     icon: 'calendar_month' },
			{ key: 'trainings',  label: 'Trainings',  icon: 'fitness_center' },
		],
	},
	'/spielbetrieb': {
		title: 'Spielbetrieb',
		tabs: [
			{ key: 'uebersicht',    label: 'Übersicht',     icon: 'dashboard'            },
			{ key: 'aufstellungen', label: 'Aufstellungen',  icon: 'format_list_numbered' },
			{ key: 'spiele',        label: 'Spiele',         icon: 'emoji_events'         },
			{ key: 'turnier',       label: 'Turnier',        icon: 'military_tech'        },
			{ key: 'landesbewerb',  label: 'Landesbewerb',   icon: 'workspace_premium'    },
			{ key: 'statistiken',   label: 'Statistiken',    icon: 'bar_chart'            },
		],
	},
	'/profil': {
		title: 'Profil',
		tabs: [
			{ key: 'uebersicht',    label: 'Übersicht',    icon: 'dashboard'                      },
			{ key: 'einstellungen', label: 'Einstellungen',icon: 'settings'                       },
			{ key: 'admin',         label: 'Kapitän',      icon: 'shield_person', adminOnly: true },
		],
	},
};

export const activeSubtabs = writable({
	'/':             'neuigkeiten',
	'/kalender':     'uebersicht',
	'/spielbetrieb': 'uebersicht',
	'/profil':       'uebersicht',
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
