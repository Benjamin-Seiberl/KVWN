<script>
	import MatchCarousel from '$lib/components/MatchCarousel.svelte';
	import ActionHub from '$lib/components/ActionHub.svelte';
</script>

<div class="page active">
	<ActionHub />
	<MatchCarousel />

	<!-- Club News -->
	<div class="widget widget--card">
		<div class="widget-header">
			<span class="material-symbols-outlined widget-icon">newspaper</span>
			<h3 class="widget-title">Club News</h3>
		</div>
		<div class="news-item">
			<div class="news-icon-wrap">
				<span class="material-symbols-outlined">celebration</span>
			</div>
			<div class="news-body">
				<p class="news-title">Sommerfest am See: Anmeldung offen</p>
				<p class="news-time">vor 2 Stunden</p>
			</div>
			<span class="material-symbols-outlined news-chevron">chevron_right</span>
		</div>
	</div>
</div>
