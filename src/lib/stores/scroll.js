import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export const scrollY = writable(0);
export const scrollDirection = writable('up');

let lastY = 0;
let scrollTimer;

export function initScrollListener() {
	if (!browser) return () => {};

	function onScroll() {
		const y = window.scrollY;
		scrollDirection.set(y > lastY ? 'down' : 'up');
		scrollY.set(y);
		lastY = y;

		// Reset direction to null after scroll stops so the pill can be opened
		clearTimeout(scrollTimer);
		scrollTimer = setTimeout(() => scrollDirection.set(null), 150);
	}

	lastY = window.scrollY;
	scrollY.set(lastY);
	window.addEventListener('scroll', onScroll, { passive: true });
	return () => window.removeEventListener('scroll', onScroll);
}
