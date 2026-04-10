<script>
	import '../app.css';
	import { onMount } from 'svelte';
	import { initAuth } from '$lib/stores/auth';

	let { children } = $props();

	onMount(() => {
		initAuth();
	});
</script>

{@render children()}
