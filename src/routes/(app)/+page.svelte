<script>
	import MatchCarousel from '$lib/components/MatchCarousel.svelte';
	import TrainingWidget from '$lib/components/TrainingWidget.svelte';
</script>

<div class="page active">
	<MatchCarousel />

	<div class="widget-row">
		<TrainingWidget />

		<!-- Vereinsrang -->
		<div class="widget widget--card widget--half widget--gold-member">
			<div class="widget-header">
				<span class="material-symbols-outlined widget-icon">leaderboard</span>
				<h3 class="widget-title">Rang</h3>
			</div>
			<div class="rank-display rank-display--stacked">
				<div class="rank-number">
					<span class="rank-value">#12</span>
					<span class="rank-delta rank-delta--up">
						<span class="material-symbols-outlined">arrow_upward</span>2
					</span>
				</div>
				<span class="badge-status badge-status--gold">Gold</span>
			</div>
		</div>
	</div>

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
