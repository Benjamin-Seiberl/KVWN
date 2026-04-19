import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export const scrollY         = writable(0);
export const scrollDirection = writable('up');

let lastY = 0;

export function initScrollListener() {
	if (!browser) return () => {};

	function onScroll() {
		const y = window.scrollY;
		scrollDirection.set(y > lastY ? 'down' : 'up');
		scrollY.set(y);
		lastY = y;
	}

	lastY = window.scrollY;
	scrollY.set(lastY);
	window.addEventListener('scroll', onScroll, { passive: true });
	return () => window.removeEventListener('scroll', onScroll);
}
