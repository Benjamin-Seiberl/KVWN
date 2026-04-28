<script>
	import MatchCarousel      from '$lib/components/MatchCarousel.svelte';
	import NewsFeed           from '$lib/components/dashboard/NewsFeed.svelte';
	import MyNextMatchCard    from '$lib/components/dashboard/MyNextMatchCard.svelte';
	import NextTrainingCard   from '$lib/components/dashboard/NextTrainingCard.svelte';
	import UpcomingEvents     from '$lib/components/dashboard/UpcomingEvents.svelte';
	import GreetingHeader     from '$lib/components/dashboard/GreetingHeader.svelte';
	import TaskBlock          from '$lib/components/dashboard/tasks/TaskBlock.svelte';
	import CaptainTaskBlock   from '$lib/components/dashboard/tasks/CaptainTaskBlock.svelte';
	import OnboardingCard     from '$lib/components/dashboard/OnboardingCard.svelte';
</script>

<div class="page active dash">

	<!-- 0: Permanenter Greeting mit adaptiver Status-Zeile -->
	<div class="dash-section" style="--i:0">
		<GreetingHeader />
	</div>

	<!-- 1: Match carousel — Spiele der Woche direkt unter dem Greeting -->
	<div class="dash-section" style="--i:1">
		<div class="sec-head">
			<span class="material-symbols-outlined sec-icon">sports_score</span>
			<h3 class="sec-title">Spiele der Woche</h3>
		</div>
		<MatchCarousel />
	</div>

	<!-- 2: Nächstes Training -->
	<div class="dash-section" style="--i:2">
		<NextTrainingCard />
	</div>

	<!-- 3: Kapitän-Aufgaben (nur wenn kapitaen UND ≥1 Signal) -->
	<div class="dash-section" style="--i:3">
		<CaptainTaskBlock />
	</div>

	<!-- 4: Offene Aufgaben (Lineup-Bestätigung, Landesbewerb-Anmeldung) -->
	<div class="dash-section" style="--i:4">
		<TaskBlock />
	</div>

	<!-- 5: Mein nächstes Spiel (rendert nur wenn ich auf einer Aufstellung stehe) -->
	<div class="dash-section" style="--i:5">
		<MyNextMatchCard />
	</div>

	<!-- 6: Upcoming events -->
	<div class="dash-section" style="--i:6">
		<UpcomingEvents />
	</div>

	<!-- 7: Onboarding-Hinweis (nur für neue Spieler ohne Scores + unvollständigem Profil) -->
	<div class="dash-section" style="--i:7">
		<OnboardingCard />
	</div>

	<!-- 8: News & polls (mixed feed) -->
	<div class="dash-section" style="--i:8">
		<NewsFeed />
	</div>

</div>

<style>
	.dash {
		padding-bottom: calc(var(--nav-height, 72px) + var(--space-5));
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
	}

	/* Staggered sections — entrance animation */
	.dash-section {
		animation: dash-up 480ms cubic-bezier(0.22, 1, 0.36, 1) both;
		animation-delay: calc(var(--i) * 70ms + 40ms);
	}

	@keyframes dash-up {
		from { opacity: 0; transform: translateY(20px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	@media (prefers-reduced-motion: reduce) {
		.dash-section { animation: none; }
	}

	/* Section header shared by inline sections (MatchCarousel etc.) */
	.sec-head {
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 0 var(--space-5);
		margin-bottom: var(--space-3);
	}
	.sec-icon {
		font-size: 1.1rem;
		color: var(--color-primary);
		font-variation-settings: 'FILL' 1, 'wght' 400, 'GRAD' 0, 'opsz' 24;
	}
	.sec-title {
		margin: 0;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 1rem;
		color: var(--color-on-surface);
	}

	/* Desktop: centered max-width (cockpit stays phone-feel per design spec) */
	@media (min-width: 768px) {
		.dash {
			max-width: 600px;
			margin: 0 auto;
		}
	}
</style>
