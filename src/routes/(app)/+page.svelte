<script>
	import { sb } from '$lib/supabase';
	import { user } from '$lib/stores/auth';
	import { currentSubtab } from '$lib/stores/subtab.js';
	import MatchCarousel   from '$lib/components/MatchCarousel.svelte';
	import ActionHub       from '$lib/components/ActionHub.svelte';
	import NewsFeed        from '$lib/components/dashboard/NewsFeed.svelte';
	import MyNextMatchCard from '$lib/components/dashboard/MyNextMatchCard.svelte';
	import QuickActions    from '$lib/components/dashboard/QuickActions.svelte';
	import UpcomingEvents  from '$lib/components/dashboard/UpcomingEvents.svelte';

	let firstName = $state('');

	function greeting() {
		const h = new Date().getHours();
		if (h < 12) return 'Guten Morgen';
		if (h < 18) return 'Guten Tag';
		return 'Guten Abend';
	}

	function todayLabel() {
		const d = new Date();
		const days = ['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];
		const months = ['Jänner','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'];
		return days[d.getDay()].toUpperCase() + ', ' + d.getDate() + '. ' + months[d.getMonth()].toUpperCase();
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
	<header class="dash-header" style="--i:0">
		<p class="dash-date">{todayLabel()}</p>
		<h1 class="dash-greeting">
			{greeting()}{firstName ? ', ' + firstName : ''}
			<span class="dash-wave" aria-hidden="true">👋</span>
		</h1>
	</header>

	{#if $currentSubtab === 'neuigkeiten'}

		<!-- Action Hub (lineup confirm + polls + events + tournaments + LM) -->
		<div class="dash-section" style="--i:1">
			<ActionHub />
		</div>

		<!-- My next match (only if on lineup) -->
		<div class="dash-section" style="--i:2; padding: 0 var(--space-5);">
			<MyNextMatchCard />
		</div>

		<!-- Match carousel -->
		<div class="dash-section" style="--i:3">
			<MatchCarousel />
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
			<UpcomingEvents />
		</div>

	{/if}

</div>

<style>
	.dash {
		padding-bottom: calc(var(--nav-height, 72px) + var(--space-5));
	}

	/* Greeting header */
	.dash-header {
		padding: var(--space-4) var(--space-5) var(--space-2);
		animation: dash-up 500ms cubic-bezier(0.22, 1, 0.36, 1) both;
		animation-delay: calc(var(--i) * 60ms + 40ms);
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
</style>
