import { writable } from 'svelte/store';

/** Global open state for the Spotlight Search overlay */
export const spotlightOpen = writable(false);
