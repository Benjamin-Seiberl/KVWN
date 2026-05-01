// $lib/constants/pushPrefs.js
//
// Single Source of Truth fuer Push-Notification-Preferences.
// - PUSH_PREFS map: key -> human-readable Austrian-German label (UI-fertig)
// - PUSH_PREF_KEYS array: nur die Keys, fuer Iteration/Validation
//
// DB-Mirror: public.players.push_prefs JSONB CHECK (siehe 20260430e_players_push_prefs.sql).
// Operationals (NICHT in dieser Liste):
//   - 'lineup_reminder' wird vom Cron always-on gesendet (Vereins-Lineup-Workflow,
//     berechtigtes Interesse Art.6(1)(f) DSGVO; siehe 0-CONTEXT.md D-05).
//
// Pitfall-Source: .planning/research/PITFALLS.md C9 (Push-Pref-Bypass).
// Spec: .planning/phases/00-cross-cutting-foundations/0-CONTEXT.md D-06.

/**
 * Map von Pref-Key auf Austrian-German Label fuer UI-Toggles.
 * @type {Record<string, string>}
 */
export const PUSH_PREFS = {
	training_24h:   'Training 24h vorher',     // TRAIN-04
	event_new:      'Neues Event',             // EVT-11
	event_reminder: 'Event 24h vorher',        // EVT-12
	poll_close:     'Umfrage schliesst',       // EVT-13
	birthday:       'Geburtstags-Banner Push'  // SELF-11
};

/**
 * Array der gueltigen Pref-Keys fuer DB-CHECK-Whitelist + UI-Iteration.
 * @type {string[]}
 */
export const PUSH_PREF_KEYS = Object.keys(PUSH_PREFS);
