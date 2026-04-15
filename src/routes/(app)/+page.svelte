<script>
	import MatchCarousel from '$lib/components/MatchCarousel.svelte';
	import TrainingWidget from '$lib/components/TrainingWidget.svelte';
	import LineupConfirmCard from '$lib/components/LineupConfirmCard.svelte';
	import NewsFeed from '$lib/components/dashboard/NewsFeed.svelte';
</script>

<div class="page active">
	<LineupConfirmCard />
	<NewsFeed />
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

</div>
