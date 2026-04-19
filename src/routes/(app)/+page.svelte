<script>
	import { onMount } from 'svelte';
	import { sb } from '$lib/supabase';
	import { user } from '$lib/stores/auth';
	import { currentSubtab } from '$lib/stores/subtab.js';
	import { MONTH_FULL } from '$lib/utils/dates.js';
	import MatchCarousel   from '$lib/components/MatchCarousel.svelte';
	import ActionHub       from '$lib/components/ActionHub.svelte';
	import NewsFeed        from '$lib/components/dashboard/NewsFeed.svelte';
	import MyNextMatchCard from '$lib/components/dashboard/MyNextMatchCard.svelte';
	import QuickActions    from '$lib/components/dashboard/QuickActions.svelte';
	import UpcomingEvents  from '$lib/components/dashboard/UpcomingEvents.svelte';
	import OpenRegistrationsCard from '$lib/components/dashboard/OpenRegistrationsCard.svelte';

	let firstName        = $state('');
	let greetingVisible  = $state(true);

	// Wave animation: 0.8s delay + 2.4s duration = 3.2s. Collapse shortly after.
	onMount(() => {
		const t = setTimeout(() => { greetingVisible = false; }, 3600);
		return () => clearTimeout(t);
	});

	function greeting() {
		const h = new Date().getHours();
		if (h < 12) return 'Guten Morgen';
		if (h < 18) return 'Guten Tag';
		return 'Guten Abend';
	}

	const DAY_FULL = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];

	function todayLabel() {
		const d = new Date();
		return DAY_FULL[d.getDay()].toUpperCase() + ', ' + d.getDate() + '. ' + MONTH_FULL[d.getMonth()].toUpperCase();
	}

	$effect(() => {
		if ($user?.email && !firstName) {
			sb.from('players').select('name').eq('email', $user.email).maybeSingle()
				.then(({ data }) => {
					if (data?.name) firstName = data.name.split(' ')[0];
				});
		}
	});
</script>

<div class="page active dash">

	<!-- Greeting header -->
	<header class="dash-header" class:dash-header--gone={!greetingVisible} style="--i:0">
		<div class="dash-header-inner">
			<p class="dash-date">{todayLabel()}</p>
			<h1 class="dash-greeting">
				{greeting()}
				<span class="dash-wave" aria-hidden="true">👋</span>
			</h1>
		</div>
	</header>

	{#if $currentSubtab === 'neuigkeiten'}

		<!-- Match carousel -->
		<div class="dash-section" style="--i:1">
			<div class="sec-head">
				<span class="material-symbols-outlined sec-icon">sports_score</span>
				<h3 class="sec-title">Spiele der Woche</h3>
			</div>
			<MatchCarousel />
		</div>

		<!-- My next match (only if on lineup) -->
		<div class="dash-section" style="--i:2; padding: 0 var(--space-5);">
			<div class="sec-head">
				<span class="material-symbols-outlined sec-icon">emoji_events</span>
				<h3 class="sec-title">Mein nächstes Spiel</h3>
			</div>
			<MyNextMatchCard />
		</div>

		<!-- Action Hub (lineup confirm + polls + events + tournaments + LM) -->
		<div class="dash-section" style="--i:3">
			<div class="sec-head">
				<span class="material-symbols-outlined sec-icon">task_alt</span>
				<h3 class="sec-title">Action Hub</h3>
			</div>
			<ActionHub />
		</div>

		<!-- Quick Actions -->
		<div class="dash-section" style="--i:4">
			<QuickActions />
		</div>

		<!-- News & polls -->
		<div class="dash-section" style="--i:5">
			<NewsFeed />
		</div>

	{:else}

		<!-- Events tab -->
		<div class="dash-section" style="--i:1">
			<OpenRegistrationsCard />
		</div>

		<div class="dash-section" style="--i:2">
			<UpcomingEvents />
		</div>

	{/if}

</div>

<style>
	.dash {
		padding-bottom: calc(var(--nav-height, 72px) + var(--space-5));
	}

	/* Greeting header — outer: clips inner, controls space */
	.dash-header {
		overflow: hidden;
		max-height: 120px;
		padding: var(--space-4) var(--space-5) var(--space-2);
		/* space collapses 0.12s after inner leaves */
		transition:
			max-height     0.6s cubic-bezier(0.32, 0.72, 0, 1) 0.16s,
			padding-top    0.6s cubic-bezier(0.32, 0.72, 0, 1) 0.16s,
			padding-bottom 0.6s cubic-bezier(0.32, 0.72, 0, 1) 0.16s;
	}
	.dash-header--gone {
		max-height: 0;
		padding-top: 0;
		padding-bottom: 0;
	}

	/* inner: slides DOWN from top on enter (slow spring hop), slides UP on exit */
	.dash-header-inner {
		animation: greeting-in 0.9s cubic-bezier(0.34, 1.56, 0.64, 1) both;
		transition:
			transform 0.5s  cubic-bezier(0.4, 0, 1, 1),
			opacity   0.31s ease;
		will-change: transform;
	}
	@keyframes greeting-in {
		from { transform: translateY(-100%); opacity: 0.4; }
		to   { transform: translateY(0);     opacity: 1;   }
	}
	.dash-header--gone .dash-header-inner {
		transform: translateY(-110%);
		opacity: 0;
	}
	.dash-date {
		margin: 0 0 2px;
		font-size: 0.68rem;
		font-weight: 700;
		letter-spacing: 0.09em;
		color: var(--color-text-soft, #888);
	}
	.dash-greeting {
		margin: 0;
		font-family: 'Lexend', sans-serif;
		font-size: clamp(1.35rem, 5vw, 1.6rem);
		font-weight: 700;
		color: var(--color-text, #1a1a1a);
		line-height: 1.2;
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.dash-wave {
		display: inline-block;
		animation: wave 2.4s ease-in-out 0.8s 1;
		transform-origin: 70% 80%;
	}
	@keyframes wave {
		0%,100% { transform: rotate(0deg); }
		15%      { transform: rotate(14deg); }
		30%      { transform: rotate(-8deg); }
		45%      { transform: rotate(14deg); }
		60%      { transform: rotate(-4deg); }
		75%      { transform: rotate(10deg); }
	}

	/* Staggered sections */
	.dash-section {
		animation: dash-up 480ms cubic-bezier(0.22, 1, 0.36, 1) both;
		animation-delay: calc(var(--i) * 70ms + 40ms);
	}

	@keyframes dash-up {
		from { opacity: 0; transform: translateY(20px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	/* Section header — matches QuickActions .qa-header style */
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
</style>
