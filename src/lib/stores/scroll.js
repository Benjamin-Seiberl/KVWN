import { writable } from 'svelte/store';
import { browser } from '$app/environment';

export const scrollY = writable(0);
export const scrollDirection = writable('up');
export const isScrolling = writable(false);

let lastY = 0;
let scrollIdleTimer;

export function initScrollListener() {
	if (!browser) return () => {};

	function onScroll() {
		const y = window.scrollY;
		scrollDirection.set(y > lastY ? 'down' : 'up');
		scrollY.set(y);
		lastY = y;

		isScrolling.set(true);
		clearTimeout(scrollIdleTimer);
		scrollIdleTimer = setTimeout(() => isScrolling.set(false), 200);
	}

	lastY = window.scrollY;
	scrollY.set(lastY);
	window.addEventListener('scroll', onScroll, { passive: true });
	return () => window.removeEventListener('scroll', onScroll);
}
