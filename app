<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KV Wiener Neustadt</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <!-- ADDED: SortableJS library for mobile-friendly drag-and-drop -->
    <script src="https://cdn.jsdelivr.net/npm/sortablejs@latest/Sortable.min.js"></script>
    <style>
        body {
            font-family: 'Inter', sans-serif;
        }
        .tab-btn {
            color: #6b7280; /* text-gray-500 */
        }
        .tab-btn:hover {
            color: #b45309; /* amber-700 */
        }
        .tab-btn.active {
            background-color: #dc2626; /* red-600 */
            color: white;
            border-color: #dc2626;
        }
        .player-select.error {
            border-color: #ef4444 !important; /* red-500 */
            background-color: #fee2e2; /* red-100 */
        }
        .substitute-slot {
            background-color: #fefce8; /* yellow-50 */
            border-left: 4px solid #f59e0b; /* amber-500 */
        }
        .regular-slot {
             border-left: 4px solid #ef4444; /* red-500 */
        }
         /* Simple spinner for loading state */
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            width: 36px;
            height: 36px;
            border-radius: 50%;
            border-left-color: #f59e0b; /* amber-500 */
            animation: spin 1s ease infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        /* Hide number input arrows */
        input[type=number]::-webkit-inner-spin-button, 
        input[type=number]::-webkit-outer-spin-button { 
          -webkit-appearance: none; 
          margin: 0; 
        }
        input[type=number] {
          -moz-appearance: textfield;
        }
        .sort-btn {
            transition: background-color 0.2s ease-in-out;
        }
        .sort-btn.active {
            background-color: white;
            color: #d97706; /* amber-600 */
            box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06);
        }
        .collapsible-content {
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.3s ease-out;
        }
        .dragging {
            opacity: 0.5;
            background: #fef3c7; /* amber-100 */
        }
        .drag-over {
            border-top: 2px solid #f59e0b;
        }
        /* Availability Grid Styles */
        .availability-cell {
            cursor: pointer;
            border-radius: 4px;
            width: 100%;
            height: 100%;
            transition: background-color 0.1s ease-in-out;
        }
        /* Player Pool Styles */
        .player-card {
            cursor: grab;
        }
        .player-card.assigned {
            cursor: not-allowed;
            opacity: 0.4;
            text-decoration: line-through;
            background-color: #e5e7eb; /* gray-200 */
        }
         .player-card.unavailable {
            background-color: #fee2e2; /* red-100 */
            border-color: #fca5a5; /* red-300 */
            color: #9ca3af; /* gray-400 */
            text-decoration: line-through;
            opacity: 0.6;
            cursor: not-allowed;
        }
        .player-card.maybe {
            border-color: #f59e0b; /* amber-500 */
        }
        .drop-target.drag-over {
            background-color: #fef3c7; /* amber-100 */
            border-color: #f59e0b; /* amber-500 */
        }
    </style>
</head>
<body class="bg-gray-100 text-gray-800 min-h-screen p-4 sm:p-6 lg:p-8">
    <div id="loading-overlay" class="fixed inset-0 bg-gray-100 bg-opacity-80 flex justify-center items-center z-50">
        <div class="spinner"></div>
    </div>

    <!-- Delete Confirmation Modal -->
    <div id="delete-modal" class="fixed inset-0 bg-gray-800 bg-opacity-75 flex justify-center items-center z-[60] hidden">
        <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-md mx-4">
            <h2 class="text-xl font-bold text-gray-800">Spieler löschen</h2>
            <p class="mt-2 text-gray-600">Möchten Sie den Spieler <strong id="player-to-delete-name"></strong> wirklich endgültig löschen? Alle zugehörigen Spieldaten gehen verloren.</p>
            <div class="mt-6 flex justify-end space-x-4">
                <button id="cancel-delete-btn" class="px-4 py-2 bg-gray-200 text-gray-800 rounded-md hover:bg-gray-300">Abbrechen</button>
                <button id="confirm-delete-btn" class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 disabled:bg-red-300 disabled:cursor-not-allowed" disabled>Löschen</button>
            </div>
        </div>
    </div>
    
    <!-- Settings Modal -->
    <div id="settings-modal" class="fixed inset-0 bg-gray-800 bg-opacity-75 flex justify-center items-start pt-20 z-50 hidden">
        <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-2xl mx-4 relative max-h-[90vh] overflow-y-auto">
             <button id="close-settings-btn" class="absolute top-4 right-4 text-gray-500 hover:text-gray-800">
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
             </button>
             <div id="content-setup" class="space-y-12 p-2 sm:p-6">
                  <!-- Schedule Management -->
                  <div>
                      <h2 class="text-xl font-semibold mb-4 text-amber-600">Spielplan Verwaltung</h2>
                      <button id="edit-schedule-btn" class="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded-md transition-colors">Spielplan bearbeiten</button>
                  </div>
                  
                  <!-- Player Pool Management -->
                  <div>
                      <h2 class="text-xl font-semibold mb-4 text-amber-600">Spielerpool</h2>
                      <div class="flex gap-2 mb-4">
                          <input type="text" id="player-input" class="flex-grow bg-white border border-gray-300 rounded-md px-3 py-2 focus:ring-2 focus:ring-amber-500 focus:border-amber-500 outline-none" placeholder="Spielername eingeben...">
                          <button id="add-player-btn" class="bg-amber-500 hover:bg-amber-600 text-white font-medium py-2 px-4 rounded-md transition-colors">Hinzufügen</button>
                      </div>
                      <div id="player-list" class="space-y-2 max-h-80 overflow-y-auto">
                          <!-- Player items will be injected here -->
                      </div>
                  </div>

                  <!-- Team Management -->
                  <div>
                      <h2 class="text-xl font-semibold mb-4 text-amber-600">Mannschaften</h2>
                      <div class="flex gap-2 mb-4">
                          <input type="text" id="team-input" class="flex-grow bg-white border border-gray-300 rounded-md px-3 py-2 focus:ring-2 focus:ring-amber-500 focus:border-amber-500 outline-none" placeholder="Mannschaftsname eingeben...">
                          <button id="add-team-btn" class="bg-amber-500 hover:bg-amber-600 text-white font-medium py-2 px-4 rounded-md transition-colors">Hinzufügen</button>
                      </div>
                      <div id="team-list" class="space-y-2 max-h-80 overflow-y-auto">
                          <!-- Team items will be injected here -->
                      </div>
                  </div>
             </div>
        </div>
    </div>

    <!-- Share Modal -->
    <div id="share-modal" class="fixed inset-0 bg-gray-800 bg-opacity-75 flex justify-center items-center z-[60] hidden">
        <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-2xl mx-4 max-h-[90vh] flex flex-col">
            <div class="flex justify-between items-center mb-4">
                <h2 class="text-xl font-bold text-gray-800">Aufstellung teilen</h2>
                <button id="close-share-btn" class="text-gray-500 hover:text-gray-800">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                </button>
            </div>
            <textarea id="share-text-container" readonly class="w-full h-64 bg-gray-100 border border-gray-300 rounded-md p-3 text-sm font-mono whitespace-pre flex-grow"></textarea>
            <div class="mt-6 flex justify-end">
                <button id="copy-share-text-btn" class="px-4 py-2 bg-amber-500 text-white rounded-md hover:bg-amber-600">Text kopieren</button>
            </div>
        </div>
    </div>

    <!-- Schedule Edit Modal -->
    <div id="schedule-modal" class="fixed inset-0 bg-gray-800 bg-opacity-75 flex justify-center items-center z-[70] hidden">
        <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-6xl mx-4 max-h-[90vh] flex flex-col">
            <div class="flex justify-between items-center mb-4 border-b pb-4">
                <h2 class="text-xl font-bold text-gray-800">Spielplan bearbeiten</h2>
                <button id="close-schedule-btn" class="text-gray-500 hover:text-gray-800">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                </button>
            </div>
            <div id="schedule-editor-container" class="flex-grow overflow-y-auto pr-2 space-y-4">
                <!-- Schedule items will be dynamically inserted here by JavaScript -->
            </div>
            <div class="mt-6 flex justify-between items-center border-t pt-4">
                <button id="add-schedule-row-btn" class="px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600">Neue Zeile</button>
                <button id="save-schedule-btn" class="px-4 py-2 bg-amber-500 text-white rounded-md hover:bg-amber-600">Änderungen speichern</button>
            </div>
        </div>
    </div>


    <div id="app" class="max-w-7xl mx-auto hidden">
        <!-- Tabs -->
        <div class="mb-6 border-b border-gray-200 flex justify-between items-center">
             <!-- Desktop Tabs -->
            <nav class="hidden sm:flex space-x-1 sm:space-x-2 flex-wrap">
                <button id="tab-stats" class="tab-btn active px-3 sm:px-4 py-2 text-sm font-medium rounded-t-lg transition-colors duration-200">Rangliste</button>
                <button id="tab-plan" class="tab-btn px-3 sm:px-4 py-2 text-sm font-medium rounded-t-lg transition-colors duration-200">Spielplan</button>
                <button id="tab-availability" class="tab-btn px-3 sm:px-4 py-2 text-sm font-medium rounded-t-lg transition-colors duration-200">Verfügbarkeiten</button>
                <button id="tab-games" class="tab-btn px-3 sm:px-4 py-2 text-sm font-medium rounded-t-lg transition-colors duration-200">Spiele</button>
                <button id="tab-zuschauer" class="tab-btn px-3 sm:px-4 py-2 text-sm font-medium rounded-t-lg transition-colors duration-200">Zuschauer</button>
            </nav>
             <!-- Mobile Burger Menu -->
             <div class="sm:hidden relative">
                 <button id="burger-menu-btn" class="p-2 text-gray-500 hover:text-amber-600 rounded-full hover:bg-gray-200">
                      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7"></path></svg>
                 </button>
                 <div id="mobile-menu" class="hidden absolute left-0 mt-2 w-48 bg-white rounded-md shadow-lg z-20">
                      <a href="#" data-tab="stats" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 mobile-tab-btn">Rangliste</a>
                      <a href="#" data-tab="plan" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 mobile-tab-btn">Spielplan</a>
                      <a href="#" data-tab="availability" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 mobile-tab-btn">Verfügbarkeiten</a>
                      <a href="#" data-tab="games" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 mobile-tab-btn">Spiele</a>
                      <a href="#" data-tab="zuschauer" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 mobile-tab-btn">Zuschauer</a>
                 </div>
             </div>
            <button id="open-settings-btn" class="p-2 text-gray-500 hover:text-amber-600 rounded-full hover:bg-gray-200">
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path></svg>
            </button>
        </div>

        <!-- App Content -->
        <main>
            <!-- Game Plan Tab Content -->
            <div id="content-plan" class="hidden">
                 <div class="bg-white p-4 sm:p-6 rounded-lg shadow-md">
                   <div class="flex flex-col sm:flex-row justify-between items-center mb-4 gap-4">
                       <h2 class="text-2xl sm:text-3xl font-bold text-gray-800 text-center sm:text-left">Woche auswählen</h2>
                       <div id="plan-actions" class="flex flex-wrap justify-center gap-2">
                           <!-- Action buttons will be injected here -->
                       </div>
                   </div>
                   <div id="week-selector" class="mb-6">
                       <!-- Week navigation will be generated here -->
                   </div>
                   <div id="player-pool-container" class="mb-6">
                       <!-- Player Pool will be rendered here by JS -->
                   </div>
                   <div id="plan-container" class="space-y-3">
                       <!-- Team plans will be generated here -->
                       <p class="text-gray-500 text-center py-8">Bitte eine Woche auswählen, um die Aufstellung zu planen.</p>
                   </div>
                 </div>
            </div>
            
            <!-- Availability Tab Content -->
            <div id="content-availability" class="hidden">
                <!-- Availability grid will be populated here -->
            </div>

            <!-- Statistics Tab Content -->
            <div id="content-stats">
                <!-- Statistics will be populated here -->
            </div>

            <!-- Games Tab Content -->
            <div id="content-games" class="hidden">
                <!-- Game list will be populated here -->
            </div>

            <!-- Spectator Tab Content -->
            <div id="content-zuschauer" class="hidden">
                <!-- Spectator planning will be populated here -->
            </div>
        </main>
        
        <!-- Statistics Section -->
        <footer class="mt-12 bg-white p-4 sm:p-6 rounded-lg shadow-md">
            <h2 class="text-xl font-semibold mb-4 text-red-600">Statistik: Abgeschlossene Wochen</h2>
            <div id="stats-container" class="flex flex-wrap gap-3">
                <!-- Stats will be injected here -->
            </div>
        </footer>

    </div>
    
    <!-- Firebase -->
    <script type="module">
        import { initializeApp } from "https://www.gstatic.com/firebasejs/12.3.0/firebase-app.js";
        import { getAuth, signInAnonymously, signInWithCustomToken } from "https://www.gstatic.com/firebasejs/12.3.0/firebase-auth.js";
        import { getFirestore, doc, onSnapshot, setDoc, setLogLevel } from "https://www.gstatic.com/firebasejs/12.3.0/firebase-firestore.js";
        
        // --- CONFIG & INITIALIZATION ---
        const firebaseConfig = {
            apiKey: "AIzaSyDv0S4tILmEANkdNnGE3eQ4WQEy34agvAc",
            authDomain: "kv-wiener-neustadt.firebaseapp.com",
            projectId: "kv-wiener-neustadt",
            storageBucket: "kv-wiener-neustadt.appspot.com",
            messagingSenderId: "1023083766729",
            appId: "1:1023083766729:web:625f92fd90eb58922afe18",
            measurementId: "G-1QT49CTYGC"
        };
        
        const appId = firebaseConfig.appId;
        const app = initializeApp(firebaseConfig);
        const auth = getAuth(app);
        const db = getFirestore(app);
        // setLogLevel('debug');

        let userId = null;
        let unsubscribe = () => {};
        
        // --- HELPER FUNCTIONS ---
        function parseDate(dateStr) { // "dd.mm.yy"
            const [day, month, year] = dateStr.split('.');
            return new Date(`20${year}`, month - 1, day);
        }

        function getWeekNumber(d) {
            d = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
            d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay()||7));
            var yearStart = new Date(Date.UTC(d.getUTCFullYear(),0,1));
            var weekNo = Math.ceil(( ( (d - yearStart) / 86400000) + 1)/7);
            return d.getUTCFullYear() + '-WK' + weekNo;
        }

        function getGameId(game) {
            return `${game.week}-${game.round}-${game.league}`;
        }
        
        // --- STATE MANAGEMENT ---
        let state = {
            players: [],
            teams: [], // Will be loaded from Firestore
            gamePlan: {},
            playerAvailability: {},
            statsRanking: [],
            schedule: [], // Will be loaded from Firestore
            smallLeagues: [], // Will be loaded from Firestore
            spectatorPlan: {} // NEW: To store spectator and ride info
        };
        
        let currentWeek = null;
        let initialWeekSet = false;
        let gamesSortOrder = 'date';
        let statsMode = 'last3';
        let temporarilyHiddenPlayers = new Set();
        let openPlanPanels = new Set();
        let visibleWeekStartIndex = 0;
        let availabilitySeasonView = 'herbst'; // 'herbst' or 'fruehjahr'
        let showPastGames = false;
        let playerPoolIsOpen = true;
        let mobileAvailabilityWeekIndex = 0; // State for availability mobile view
        
        // --- DOM ELEMENTS ---
        const playerInput = document.getElementById('player-input');
        const addPlayerBtn = document.getElementById('add-player-btn');
        const playerList = document.getElementById('player-list');
        const teamInput = document.getElementById('team-input');
        const addTeamBtn = document.getElementById('add-team-btn');
        const teamList = document.getElementById('team-list');
        const tabPlan = document.getElementById('tab-plan');
        const tabGames = document.getElementById('tab-games');
        const tabStats = document.getElementById('tab-stats');
        const tabAvailability = document.getElementById('tab-availability');
        const tabZuschauer = document.getElementById('tab-zuschauer');
        const contentPlan = document.getElementById('content-plan');
        const contentGames = document.getElementById('content-games');
        const contentStats = document.getElementById('content-stats');
        const contentAvailability = document.getElementById('content-availability');
        const contentZuschauer = document.getElementById('content-zuschauer');
        const openSettingsBtn = document.getElementById('open-settings-btn');
        const settingsModal = document.getElementById('settings-modal');
        const closeSettingsBtn = document.getElementById('close-settings-btn');
        const weekSelector = document.getElementById('week-selector');
        const planContainer = document.getElementById('plan-container');
        const statsContainer = document.getElementById('stats-container');
        const loadingOverlay = document.getElementById('loading-overlay');
        const appContainer = document.getElementById('app');
        const deleteModal = document.getElementById('delete-modal');
        const confirmDeleteBtn = document.getElementById('confirm-delete-btn');
        const cancelDeleteBtn = document.getElementById('cancel-delete-btn');
        const playerNameToDelete = document.getElementById('player-to-delete-name');
        const shareModal = document.getElementById('share-modal');
        const closeShareBtn = document.getElementById('close-share-btn');
        const shareTextContainer = document.getElementById('share-text-container');
        const copyShareTextBtn = document.getElementById('copy-share-text-btn');
        const planActionsContainer = document.getElementById('plan-actions');
        const playerPoolContainer = document.getElementById('player-pool-container');
        const scheduleModal = document.getElementById('schedule-modal');
        const closeScheduleBtn = document.getElementById('close-schedule-btn');
        const saveScheduleBtn = document.getElementById('save-schedule-btn');
        const editScheduleBtn = document.getElementById('edit-schedule-btn');
        const scheduleEditorContainer = document.getElementById('schedule-editor-container');
        const addScheduleRowBtn = document.getElementById('add-schedule-row-btn');
        const burgerMenuBtn = document.getElementById('burger-menu-btn');
        const mobileMenu = document.getElementById('mobile-menu');
        
        // --- DATA PERSISTENCE (FIRESTORE) ---
        async function saveStateToFirestore() {
            if (!userId) return;
            try {
                const stateToSave = {
                    players: state.players,
                    gamePlan: state.gamePlan,
                    playerAvailability: state.playerAvailability,
                    statsRanking: state.statsRanking,
                    spectatorPlan: state.spectatorPlan
                };
                const docRef = doc(db, `artifacts/${appId}/organizer/data`);
                await setDoc(docRef, stateToSave);
            } catch (error) {
                console.error("Error saving state to Firestore:", error);
            }
        }

        async function saveConfigToFirestore() {
            if (!userId) return;
            try {
                const configToSave = {
                    schedule: state.schedule,
                    teamOrder: state.teams,
                    smallLeagues: state.smallLeagues
                };
                const docRef = doc(db, `artifacts/${appId}/organizer/config`);
                await setDoc(docRef, configToSave, { merge: true });
                console.log("Config saved successfully.");
            } catch (error) {
                console.error("Error saving config to Firestore:", error);
                alert("Fehler beim Speichern des Spielplans. Bitte versuchen Sie es erneut.");
            }
        }

        // --- SCHEDULE EDITOR LOGIC ---
        function renderScheduleEditor() {
            scheduleEditorContainer.innerHTML = '';
            const headerRow = document.createElement('div');
            headerRow.className = 'grid grid-cols-8 gap-2 font-bold text-sm text-gray-600 pb-2 border-b';
            headerRow.innerHTML = `
                <span>Datum (TT.MM.JJ)</span>
                <span>Runde</span>
                <span>Team</span>
                <span>Zeit</span>
                <span>Gegner</span>
                <span>Ort</span>
                <span>Heim/Auswärts</span>
                <span>Aktion</span>
            `;
            scheduleEditorContainer.appendChild(headerRow);

            state.schedule.forEach((game, index) => {
                const row = createScheduleEditorRow(game, index);
                scheduleEditorContainer.appendChild(row);
            });
        }

        function createScheduleEditorRow(game, index) {
            const row = document.createElement('div');
            row.className = 'grid grid-cols-8 gap-2 items-center py-2 border-b border-gray-100';
            row.dataset.index = index;
            row.innerHTML = `
                <input type="text" placeholder="TT.MM.JJ" value="${game.dateStr || ''}" data-field="dateStr" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                <input type="text" placeholder="z.B. H1" value="${game.round || ''}" data-field="round" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                <select data-field="league" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                    ${state.teams.map(t => `<option value="${t}" ${game.league === t ? 'selected' : ''}>${t}</option>`).join('')}
                </select>
                <input type="text" placeholder="18:30" value="${game.time || ''}" data-field="time" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                <input type="text" placeholder="Gegnerteam" value="${game.opponent || ''}" data-field="opponent" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                <input type="text" placeholder="Spielort" value="${game.location || ''}" data-field="location" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                <select data-field="home_away" class="w-full bg-white border border-gray-300 rounded-md p-1.5 text-sm outline-none">
                    <option value="HEIM" ${game.home_away === 'HEIM' ? 'selected' : ''}>HEIM</option>
                    <option value="AUSWÄRTS" ${game.home_away === 'AUSWÄRTS' ? 'selected' : ''}>AUSWÄRTS</option>
                </select>
                <button class="remove-schedule-row-btn text-red-500 hover:text-red-700 font-bold flex justify-center items-center h-full">&times;</button>
            `;
            return row;
        }

        function openScheduleEditor() {
            renderScheduleEditor();
            scheduleModal.classList.remove('hidden');
        }

        function closeScheduleEditor() {
            scheduleModal.classList.add('hidden');
        }

        async function saveScheduleChanges() {
            const newSchedule = [];
            const rows = scheduleEditorContainer.querySelectorAll('div[data-index]');
            let hasError = false;

            rows.forEach(row => {
                const game = {};
                row.querySelectorAll('input, select').forEach(input => {
                    const field = input.dataset.field;
                    game[field] = input.value.trim();
                });
                
                if (!/^\d{2}\.\d{2}\.\d{2}$/.test(game.dateStr) || !game.round) {
                    if (!/^\d{2}\.\d{2}\.\d{2}$/.test(game.dateStr)) row.querySelector('[data-field="dateStr"]').classList.add('border-red-500');
                    if (!game.round) row.querySelector('[data-field="round"]').classList.add('border-red-500');
                    hasError = true;
                } else {
                     row.querySelector('[data-field="dateStr"]').classList.remove('border-red-500');
                     row.querySelector('[data-field="round"]').classList.remove('border-red-500');
                }
                newSchedule.push(game);
            });

            if (hasError) {
                alert("Bitte korrigieren Sie die markierten Felder. Datum (TT.MM.JJ) und Runde sind Pflichtfelder.");
                return;
            }

            newSchedule.sort((a, b) => parseDate(a.dateStr) - parseDate(b.dateStr));
            state.schedule = newSchedule;
            
            closeScheduleEditor();
            loadingOverlay.style.display = 'flex';
            appContainer.classList.add('hidden');
            
            await saveConfigToFirestore();
            
            // Force a full re-initialization to get new weeks etc.
            initialWeekSet = false;
            setTimeout(() => {
                 initialSetupAndRender();
            }, 100);
        }

        function addNewScheduleRow() {
            const newGame = { dateStr: '', round: '', league: state.teams[0] || '', time: '', opponent: '', location: '', home_away: 'HEIM' };
            const newIndex = scheduleEditorContainer.querySelectorAll('div[data-index]').length;
            const row = createScheduleEditorRow(newGame, newIndex);
            scheduleEditorContainer.appendChild(row);
            row.querySelector('input').focus();
        }

        function handleScheduleEditorClicks(e) {
            if (e.target.classList.contains('remove-schedule-row-btn')) {
                e.target.closest('div[data-index]').remove();
                scheduleEditorContainer.querySelectorAll('div[data-index]').forEach((row, index) => {
                    row.dataset.index = index;
                });
            }
        }
        
        let isConfigLoaded = false;
        let isStateLoaded = false;
        let WEEKS = [];

        function initialSetupAndRender() {
            if (!initialWeekSet) {
                // --- DATA PROCESSING (MOVED HERE) ---
                state.schedule.forEach(game => {
                    game.week = getWeekNumber(parseDate(game.dateStr));
                });

                WEEKS = [...new Set(state.schedule.map(g => g.week))].sort((a, b) => {
                    const [yearA, weekA] = a.split('-WK');
                    const [yearB, weekB] = b.split('-WK');
                    if (yearA !== yearB) return parseInt(yearA) - parseInt(yearB);
                    return parseInt(weekA) - parseInt(weekB);
                });
                
                const playerStats = getPlayerStats(statsMode);
                const ranked = Array.from(playerStats.keys()).sort((a,b) => (playerStats.get(b)?.average || 0) - (playerStats.get(a)?.average || 0));
                const unranked = state.players.filter(p => !playerStats.has(p)).sort();
                state.statsRanking = [...ranked, ...unranked];
                
                const currentSystemWeek = getWeekNumber(new Date());
                let currentWeekIndex = WEEKS.indexOf(currentSystemWeek);
                if (currentWeekIndex === -1) {
                    let foundWeek = WEEKS.find(w => w >= currentSystemWeek);
                    currentWeekIndex = WEEKS.indexOf(foundWeek || WEEKS[0]);
                }
                currentWeek = WEEKS[currentWeekIndex];

                visibleWeekStartIndex = Math.max(0, currentWeekIndex - 3);
                if (visibleWeekStartIndex + 7 > WEEKS.length) {
                    visibleWeekStartIndex = Math.max(0, WEEKS.length - 7);
                }
                initialWeekSet = true;
            }

            renderAll();
            hideLoading();
        }

        function listenToConfigChanges() {
            if (!userId) return;
            const docRef = doc(db, `artifacts/${appId}/organizer/config`);
            onSnapshot(docRef, (docSnap) => {
                if (docSnap.exists()) {
                    const config = docSnap.data();
                    state.schedule = config.schedule || [];
                    state.teams = config.teamOrder || [];
                    state.smallLeagues = config.smallLeagues || [];
                    
                    if (!isConfigLoaded) {
                        isConfigLoaded = true;
                        if (isStateLoaded) initialSetupAndRender();
                    } else {
                        // This else block might cause re-renders on every config save,
                        // which is fine for now as it ensures UI is in sync.
                        initialWeekSet = false; // Force re-calculation of weeks
                        initialSetupAndRender();
                    }
                } else {
                     console.error("Config document does not exist in Firestore!");
                     // You could create a default one here if needed
                }
            }, (error) => console.error("Error listening to config changes:", error));
        }

        function listenToStateChanges() {
            if (!userId) return;
            const docRef = doc(db, `artifacts/${appId}/organizer/data`);
            unsubscribe = onSnapshot(docRef, (docSnap) => {
                if (!docSnap.exists()) {
                    saveStateToFirestore(); // Create document if it doesn't exist
                    return;
                }

                const data = docSnap.data();
                state.players = Array.isArray(data.players) ? data.players : [];
                state.gamePlan = (typeof data.gamePlan === 'object' && data.gamePlan !== null) ? data.gamePlan : {};
                state.playerAvailability = (typeof data.playerAvailability === 'object' && data.playerAvailability !== null) ? data.playerAvailability : {};
                state.statsRanking = Array.isArray(data.statsRanking) ? data.statsRanking : [];
                state.spectatorPlan = (typeof data.spectatorPlan === 'object' && data.spectatorPlan !== null) ? data.spectatorPlan : {};


                if (docSnap.metadata.hasPendingWrites && initialWeekSet) {
                    return;
                }

                if (!isStateLoaded) {
                    isStateLoaded = true;
                    if (isConfigLoaded) initialSetupAndRender();
                } else {
                    renderAll();
                }
            }, (error) => {
                console.error("Error listening to state changes:", error);
                hideLoading();
            });
        }
        
        // --- RENDER FUNCTIONS ---
        function renderAll() {
            renderPlayers();
            renderTeams();
            renderWeekSelector();
            renderStatisticsFooter();
            renderGamesList();
            renderStatisticsTab();
            renderAvailabilityTab();
            renderSpectatorTab();
            if (currentWeek) {
                renderGamePlanUI();
                renderActionButtons();
                renderPlayerPool();
            }
        }

        function createListItem(text, onRemove) {
            const div = document.createElement('div');
            div.className = 'flex justify-between items-center bg-gray-50 border border-gray-200 p-2 rounded-md';
            const span = document.createElement('span');
            span.textContent = text;
            div.appendChild(span);
            
            if(onRemove){
                const button = document.createElement('button');
                button.innerHTML = '&times;';
                button.className = 'text-red-500 hover:text-red-700 font-bold text-xl px-2';
                button.onclick = onRemove;
                div.appendChild(button);
            }
            return div;
        }

        function renderPlayers() {
            playerList.innerHTML = '';
            state.players.forEach(player => {
                const item = createListItem(player, () => showDeleteConfirmation(player));
                playerList.appendChild(item);
            });
        }
        
        function renderTeams() {
            teamList.innerHTML = '';
            state.teams.forEach(team => {
                const item = createListItem(team, () => deleteTeam(team));
                teamList.appendChild(item);
            });
        }

        function renderWeekSelector() {
            weekSelector.innerHTML = '';
            const heading = document.querySelector('#content-plan h2');
            if (!heading.querySelector('#season-display')) {
                heading.innerHTML = `Woche auswählen <span id="season-display" class="text-gray-500 font-medium text-base">Saison 2025/2026</span>`;
            }

            const navContainer = document.createElement('div');
            navContainer.className = 'flex items-center gap-2';
            weekSelector.appendChild(navContainer);

            // Left Arrow
            const leftArrow = document.createElement('button');
            leftArrow.innerHTML = `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"></path></svg>`;
            leftArrow.className = 'p-2 rounded-full hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed flex-shrink-0';
            if (visibleWeekStartIndex <= 0) {
                leftArrow.disabled = true;
            }
            leftArrow.addEventListener('click', () => {
                visibleWeekStartIndex = Math.max(0, visibleWeekStartIndex - 1);
                renderWeekSelector();
            });
            navContainer.appendChild(leftArrow);

            const weekButtonsContainer = document.createElement('div');
            weekButtonsContainer.className = 'flex flex-grow justify-center flex-wrap gap-2';
            navContainer.appendChild(weekButtonsContainer);

            // Week Buttons
            const endIndex = Math.min(visibleWeekStartIndex + 7, WEEKS.length);
            for (let i = visibleWeekStartIndex; i < endIndex; i++) {
                const week = WEEKS[i];
                const button = document.createElement('button');
                const isPast = week < getWeekNumber(new Date());
                const weekNumber = parseInt(week.split('-WK')[1], 10).toString().padStart(2, '0');
                button.textContent = `KW${weekNumber}`;
                
                let classes = 'px-3 py-1.5 rounded-md transition-colors text-sm font-medium ';
                 if (currentWeek === week) {
                      classes += 'bg-amber-500 text-white';
                 } else if (isPast) {
                      classes += 'bg-gray-100 text-gray-400 border border-gray-200 hover:bg-gray-200';
                 } else {
                      classes += 'bg-white hover:bg-gray-50 border border-gray-300 text-gray-700';
                 }
                button.className = classes;

                button.onclick = () => selectWeek(week);
                weekButtonsContainer.appendChild(button);
            }

            // Right Arrow
            const rightArrow = document.createElement('button');
            rightArrow.innerHTML = `<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path></svg>`;
            rightArrow.className = 'p-2 rounded-full hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed flex-shrink-0';
            if (visibleWeekStartIndex >= WEEKS.length - 7) {
                rightArrow.disabled = true;
            }
            rightArrow.addEventListener('click', () => {
                visibleWeekStartIndex = Math.min(WEEKS.length - 7, visibleWeekStartIndex + 1);
                renderWeekSelector();
            });
            navContainer.appendChild(rightArrow);
        }

        function renderGamePlanUI() {
            planContainer.innerHTML = '';
            if (!currentWeek) {
                planContainer.innerHTML = `<p class="text-gray-500 text-center py-8">Bitte eine Woche auswählen, um die Aufstellung zu planen.</p>`;
                return;
            }
            
            const gamesThisWeek = state.schedule.filter(g => g.week === currentWeek);

            if (gamesThisWeek.length === 0) {
                planContainer.innerHTML = `<p class="text-gray-500 text-center py-8">Keine Spiele für die ausgewählten Mannschaften in dieser Woche geplant.</p>`;
                return;
            }

            const weekPlan = state.gamePlan[currentWeek] || {};

            state.teams.forEach(teamName => {
                const game = gamesThisWeek.find(g => g.league === teamName);
                if (!game) return;

                const teamDiv = document.createElement('div');
                teamDiv.className = 'bg-gray-50 border border-gray-200 rounded-lg';
                teamDiv.dataset.teamName = teamName;
                
                const isSmallLeague = state.smallLeagues.includes(teamName);
                const numPlayersTotal = isSmallLeague ? 5 : 8;
                const numRegular = isSmallLeague ? 4 : 6;
                const numErsatz = numPlayersTotal - numRegular;

                const teamPlan = weekPlan[teamName] || [];
                const regularFilled = teamPlan.slice(0, numRegular).filter(p => p && p.name).length;
                const ersatzFilled = teamPlan.slice(numRegular).filter(p => p && p.name).length;

                const headerButton = document.createElement('button');
                headerButton.className = "w-full text-left p-2 sm:p-4 flex justify-between items-center";
                const gameDate = new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit' });

                if (game.opponent === 'SPIELFREI') {
                    headerButton.innerHTML = `
                        <div class="flex-grow overflow-hidden">
                            <div class="flex items-center justify-between">
                                 <h3 class="text-base sm:text-lg font-semibold text-red-600 truncate">${teamName} (${game.round})</h3>
                            </div>
                            <div class="text-xs sm:text-sm font-semibold mt-1.5">
                                 <span class="font-semibold text-gray-600">${gameDate}</span> | <span class="text-amber-600">SPIELFREI</span>
                            </div>
                        </div>
                        <svg class="w-5 h-5 ml-4 flex-shrink-0 transition-transform duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path></svg>
                    `;
                } else {
                    headerButton.innerHTML = `
                        <div class="flex-grow overflow-hidden">
                            <div class="flex items-center justify-between">
                                 <h3 class="text-base sm:text-lg font-semibold text-red-600 truncate">${teamName} (${game.round})</h3>
                                 <span class="text-xs sm:text-sm font-medium text-gray-600 flex-shrink-0 ml-4">${regularFilled}/${numRegular} & ${ersatzFilled}/${numErsatz} Ersatz</span>
                            </div>
                            <div class="text-xs sm:text-sm text-gray-600 mt-1.5">
                                 <span class="font-semibold">${gameDate}</span> | ${game.time} | ${game.opponent} (${game.home_away})
                            </div>
                        </div>
                        <svg class="w-5 h-5 ml-4 flex-shrink-0 transition-transform duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path></svg>
                    `;
                }
                
                const contentDiv = document.createElement('div');
                contentDiv.className = 'px-4 border-t border-gray-200 collapsible-content';

                if (game.opponent !== 'SPIELFREI') {
                    const grid = document.createElement('div');
                    grid.className = 'py-4 grid grid-cols-1 gap-x-4 gap-y-2';
                    
                    for (let i = 0; i < numPlayersTotal; i++) {
                        const isSubstitute = i >= numRegular;
                        const slotDiv = document.createElement('div');
                        slotDiv.className = `p-2 rounded-md drop-target ${isSubstitute ? 'substitute-slot' : 'regular-slot'}`;
                        
                        const label = document.createElement('label');
                        label.className = 'block text-xs font-medium text-gray-700 mb-1';
                        label.textContent = isSubstitute ? `Ersatz ${i - numRegular + 1}` : `Spieler ${i + 1}`;
                        
                        const inputFlexContainer = document.createElement('div');
                        inputFlexContainer.className = 'flex gap-1 items-center';

                        const playerInputContainer = document.createElement('div');
                        playerInputContainer.className = 'player-input-container relative flex-grow';

                        const playerInput = document.createElement('input');
                        playerInput.type = 'text';
                        playerInput.className = 'player-select w-full bg-white border border-gray-300 rounded-md p-1 sm:p-1.5 text-xs sm:text-sm focus:ring-2 focus:ring-amber-500 outline-none';
                        playerInput.dataset.team = game.league;
                        playerInput.dataset.position = i;
                        playerInput.dataset.round = game.round;
                        playerInput.value = teamPlan[i]?.name || '';
                        playerInput.autocomplete = 'off';
                        playerInput.placeholder = 'Spieler wählen';

                        const dropdown = document.createElement('div');
                        dropdown.className = 'player-dropdown absolute hidden bg-white border mt-1 w-full rounded-md shadow-lg z-10 max-h-40 overflow-y-auto';
                        
                        playerInputContainer.appendChild(playerInput);
                        playerInputContainer.appendChild(dropdown);

                        const scoreInput = document.createElement('input');
                        scoreInput.type = 'number';
                        scoreInput.className = 'kegel-score w-16 bg-white border border-gray-300 rounded-md p-1 sm:p-1.5 text-xs sm:text-sm focus:ring-2 focus:ring-amber-500 outline-none text-center';
                        scoreInput.min = "0";
                        scoreInput.max = "999";
                        scoreInput.placeholder = "Kegel";
                        scoreInput.value = teamPlan[i]?.score || '';
                        scoreInput.dataset.team = game.league;
                        scoreInput.dataset.position = i;
                        
                        inputFlexContainer.appendChild(playerInputContainer);
                        inputFlexContainer.appendChild(scoreInput);
                        
                        if (isSubstitute) {
                            const checkboxContainer = document.createElement('div');
                            checkboxContainer.className = "flex items-center ml-1";
                            const checkbox = document.createElement('input');
                            checkbox.type = 'checkbox';
                            checkbox.checked = teamPlan[i]?.played || false;
                            checkbox.className = 'h-4 w-4 rounded border-gray-300 text-amber-600 focus:ring-amber-500 substitute-checkbox';
                            checkbox.dataset.team = game.league;
                            checkbox.dataset.position = i;
                            checkbox.addEventListener('change', () => {
                                validatePlayerAssignments();
                                saveWeek(); // Autosave
                            });
                            checkboxContainer.appendChild(checkbox);
                            inputFlexContainer.appendChild(checkboxContainer);
                            
                            scoreInput.addEventListener('input', () => {
                                if (scoreInput.value) {
                                    checkbox.checked = true;
                                }
                            });
                            scoreInput.addEventListener('change', () => {
                                validatePlayerAssignments();
                                saveWeek(); // Autosave
                            });
                        } else {
                             scoreInput.addEventListener('change', saveWeek); // Autosave
                        }
                        
                        slotDiv.appendChild(label);
                        slotDiv.appendChild(inputFlexContainer);
                        grid.appendChild(slotDiv);

                        // Drag and Drop Logic for player slots
                        slotDiv.addEventListener('dragover', (e) => {
                            e.preventDefault();
                            slotDiv.classList.add('bg-amber-100', 'border-amber-400');
                        });
                        slotDiv.addEventListener('dragleave', (e) => {
                             slotDiv.classList.remove('bg-amber-100', 'border-amber-400');
                        });
                        slotDiv.addEventListener('drop', (e) => {
                            e.preventDefault();
                            slotDiv.classList.remove('bg-amber-100', 'border-amber-400');
                            const playerName = e.dataTransfer.getData('text/plain');
                            
                            const input = slotDiv.querySelector('.player-select');
                            if (input && input.value !== playerName) {
                                saveWeek(); // Save current state before changing
                                updatePlayerCardState(input.value, false); // Free up old player
                                input.value = playerName;
                                saveWeek(); // Save new state
                                updatePlayerCardState(playerName, true); // Assign new player
                                validatePlayerAssignments();
                            }
                        });


                        playerInput.addEventListener('focus', (e) => {
                            const contentParent = e.target.closest('.collapsible-content');
                            if (contentParent) {
                                contentParent.style.overflow = 'visible';
                            }
                            playerInputContainer.style.zIndex = '20';
                            
                            dropdown.classList.remove('bottom-full', 'mb-1');
                            dropdown.classList.add('mt-1');

                            showPlayerDropdown(playerInput, dropdown);
                        });

                        playerInput.addEventListener('input', () => showPlayerDropdown(playerInput, dropdown));
                        
                        playerInput.addEventListener('change', () => {
                            const oldPlayer = teamPlan[i]?.name;
                            if (!state.players.includes(playerInput.value)) {
                                playerInput.value = '';
                            }
                            updatePlayerCardState(oldPlayer, false);
                            updatePlayerCardState(playerInput.value, true);
                            validatePlayerAssignments();
                            saveWeek();
                        });

                        playerInput.addEventListener('blur', (e) => {
                            const contentParent = e.target.closest('.collapsible-content');

                            setTimeout(() => {
                                // Only hide the overflow if focus moves outside of the player inputs in this section
                                if (!contentParent.contains(document.activeElement) || !document.activeElement.classList.contains('player-select')) {
                                    if (contentParent) {
                                        contentParent.style.overflow = 'hidden';
                                    }
                                }
                                
                                dropdown.classList.add('hidden');
                                playerInputContainer.style.zIndex = 'auto';

                            }, 150);
                        });
                    }
                    contentDiv.appendChild(grid);
                }

                teamDiv.appendChild(headerButton);
                teamDiv.appendChild(contentDiv);
                planContainer.appendChild(teamDiv);
                
                // Drag and Drop for Team Header
                headerButton.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    headerButton.classList.add('bg-amber-100');
                });
                 headerButton.addEventListener('dragleave', (e) => {
                    headerButton.classList.remove('bg-amber-100');
                });
                headerButton.addEventListener('drop', (e) => {
                    e.preventDefault();
                    headerButton.classList.remove('bg-amber-100');
                    const playerName = e.dataTransfer.getData('text/plain');

                    const currentTeamPlan = state.gamePlan[currentWeek]?.[teamName] || Array(numPlayersTotal).fill({name: '', score: '', played: false});
                    let firstEmptyIndex = -1;
                    for(let i=0; i < numPlayersTotal; i++) {
                        if (!currentTeamPlan[i] || !currentTeamPlan[i].name) {
                            firstEmptyIndex = i;
                            break;
                        }
                    }

                    if(firstEmptyIndex !== -1) {
                        const inputToUpdate = document.querySelector(`.player-select[data-team="${teamName}"][data-position="${firstEmptyIndex}"]`);
                        if(inputToUpdate) {
                            inputToUpdate.value = playerName;
                            saveWeek();
                            syncPlayerPoolState();
                            validatePlayerAssignments();
                        }
                    } else {
                        // Optionally provide feedback that the team is full
                    }
                });

                headerButton.addEventListener('click', () => {
                    const icon = headerButton.querySelector('svg');
                    if (contentDiv.style.maxHeight && contentDiv.style.maxHeight !== '0px') {
                        contentDiv.style.maxHeight = '0px';
                        icon.style.transform = 'rotate(0deg)';
                        openPlanPanels.delete(teamName);
                    } else {
                        contentDiv.style.maxHeight = contentDiv.scrollHeight + "px";
                        icon.style.transform = 'rotate(180deg)';
                        openPlanPanels.add(teamName);
                    }
                });

                if (openPlanPanels.has(teamName)) {
                    const icon = headerButton.querySelector('svg');
                    contentDiv.style.maxHeight = contentDiv.scrollHeight + "px";
                    icon.style.transform = 'rotate(180deg)';
                } else {
                    contentDiv.style.maxHeight = '0px';
                }

            });
            validatePlayerAssignments();
        }

        function renderStatisticsFooter() {
            statsContainer.innerHTML = '';
            WEEKS.forEach(week => {
                const isComplete = state.gamePlan[week] && Object.keys(state.gamePlan[week]).length > 0;
                const statChip = document.createElement('div');
                statChip.textContent = week;
                statChip.className = `px-3 py-1 rounded-full text-sm font-medium ${isComplete ? 'bg-green-100 text-green-800' : 'bg-gray-200 text-gray-600'}`;
                statsContainer.appendChild(statChip);
            });
        }
        
        function renderGamesList() {
            contentGames.innerHTML = '';
            const container = document.createElement('div');
            container.className = "bg-white p-4 sm:p-6 rounded-lg shadow-md";

            // --- Header ---
            const headerContainer = document.createElement('div');
            headerContainer.className = "flex flex-col items-center mb-6 gap-4";
            container.appendChild(headerContainer);

            const titleRow = document.createElement('div');
            titleRow.className = 'w-full flex flex-col sm:flex-row justify-between items-center gap-4';
            headerContainer.appendChild(titleRow);

            const title = document.createElement('h2');
            title.className = "text-2xl sm:text-3xl font-bold text-gray-800 text-center";
            title.textContent = "Saison 2025/2026";
            
            // Toggle on the left
            const toggleWrapper = document.createElement('div');
            toggleWrapper.className = 'flex items-center gap-2';
            toggleWrapper.innerHTML = `
                <div class="relative">
                    <input id="show-past-games-toggle" type="checkbox" class="sr-only peer" ${showPastGames ? 'checked' : ''}>
                    <label for="show-past-games-toggle" class="block bg-gray-300 peer-checked:bg-amber-500 w-12 h-7 rounded-full cursor-pointer"></label>
                    <div class="dot absolute left-1 top-1 bg-white w-5 h-5 rounded-full transition-transform peer-checked:translate-x-full cursor-pointer"></div>
                </div>
                <label for="show-past-games-toggle" class="text-sm font-medium text-gray-700 cursor-pointer">Vergangene</label>
            `;

            titleRow.appendChild(toggleWrapper);
            titleRow.appendChild(title);
            // Add a placeholder div to balance the flex layout on larger screens
            const placeholderDiv = document.createElement('div');
            placeholderDiv.className = 'hidden sm:block w-36'; // Match width of toggle
            titleRow.appendChild(placeholderDiv);
            
            // Sort Controls below title
            const sortControlContainer = document.createElement('div');
            sortControlContainer.className = "flex justify-center";
            sortControlContainer.innerHTML = `
                <div class="flex items-center space-x-1 rounded-lg bg-gray-200 p-1 text-gray-600">
                    <button id="sort-by-date-btn" class="sort-btn px-3 py-1 text-sm rounded-md ${gamesSortOrder === 'date' ? 'active' : ''}">Nach Datum</button>
                    <button id="sort-by-team-btn" class="sort-btn px-3 py-1 text-sm rounded-md ${gamesSortOrder === 'team' ? 'active' : ''}">Nach Team</button>
                    <button id="sort-by-round-btn" class="sort-btn px-3 py-1 text-sm rounded-md ${gamesSortOrder === 'round' ? 'active' : ''}">Nach Runde</button>
                </div>`;
            headerContainer.appendChild(sortControlContainer);

            // --- Game List ---
            const listContainer = document.createElement('div');
            listContainer.className = "space-y-2";
            container.appendChild(listContainer);
            
            const today = new Date();
            today.setHours(0, 0, 0, 0); // Normalize to start of day

            const gamesToDisplay = showPastGames ? [...state.schedule] : state.schedule.filter(game => parseDate(game.dateStr) >= today);

            if (gamesToDisplay.length === 0) {
                 listContainer.innerHTML = `<p class="text-gray-500 text-center py-8">Keine zukünftigen Spiele geplant. Schalten Sie "Vergangene" ein, um alle Spiele zu sehen.</p>`;
            } else if (gamesSortOrder === 'team') {
                const gamesByLeague = gamesToDisplay.reduce((acc, game) => {
                    if (!acc[game.league]) acc[game.league] = [];
                    acc[game.league].push(game);
                    return acc;
                }, {});

                state.teams.forEach(league => {
                    if (!gamesByLeague[league]) return;

                    const leagueSection = document.createElement('div');
                    const titleButton = document.createElement('button');
                    titleButton.className = "w-full text-left text-xl font-semibold text-red-600 mb-2 p-2 rounded-md hover:bg-gray-100 flex justify-between items-center";
                    titleButton.innerHTML = `<span>${league}</span><svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path></svg>`;
                    
                    const gameList = document.createElement('div');
                    gameList.className = "pl-4 space-y-2 collapsible-content";
                    
                    gamesByLeague[league].forEach(game => {
                        const gameCard = document.createElement('div');
                        const isPast = parseDate(game.dateStr) < today;
                        gameCard.className = `p-2 bg-gray-50 rounded-lg border border-gray-200 ${isPast ? 'opacity-60' : ''}`;
                        
                        let content;
                        if (game.opponent === 'SPIELFREI') {
                            content = `<p class="font-medium text-sm">${game.round} am ${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: '2-digit' })}: <span class="font-bold text-amber-600">SPIELFREI</span></p>`;
                        } else {
                            content = `
                                <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center">
                                    <div>
                                        <p class="font-medium text-gray-800 text-sm">${game.round}: ${game.opponent}</p>
                                        <p class="text-xs text-gray-500">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit', year: '2-digit' })}, ${game.time} @ ${game.location}</p>
                                    </div>
                                    <div class="mt-1 sm:mt-0">
                                       <span class="text-xs font-semibold px-2 py-0.5 rounded-full ${game.home_away === 'HEIM' ? 'bg-blue-100 text-blue-800' : 'bg-green-100 text-green-800'}">${game.home_away}</span>
                                    </div>
                                </div>`;
                        }
                        gameCard.innerHTML = content;
                        gameList.appendChild(gameCard);
                    });
                    
                    leagueSection.appendChild(titleButton);
                    leagueSection.appendChild(gameList);
                    listContainer.appendChild(leagueSection);
                    
                    // Collapse logic
                    titleButton.addEventListener('click', () => {
                        const icon = titleButton.querySelector('svg');
                        if (gameList.style.maxHeight && gameList.style.maxHeight !== '0px') {
                            gameList.style.maxHeight = '0px';
                            icon.style.transform = 'rotate(0deg)';
                        } else {
                            gameList.style.maxHeight = gameList.scrollHeight + "px";
                            icon.style.transform = 'rotate(180deg)';
                        }
                    });
                });
            } else if (gamesSortOrder === 'date') {
                const sortedGames = gamesToDisplay.sort((a,b) => parseDate(a.dateStr) - parseDate(b.dateStr));
                let currentRenderedWeek = null;

                sortedGames.forEach(game => {
                    if(game.week !== currentRenderedWeek) {
                        currentRenderedWeek = game.week;
                        const weekHeader = document.createElement('h4');
                        weekHeader.className = "text-lg font-semibold text-gray-700 mt-4 mb-1 border-b pb-1";
                        weekHeader.textContent = currentRenderedWeek.replace('-WK', '-KW');
                        weekHeader.id = `week-header-${currentRenderedWeek}`;
                        if (parseDate(game.dateStr) < today) {
                            weekHeader.classList.add('text-gray-400');
                        }
                        listContainer.appendChild(weekHeader);
                    }

                const gameCard = document.createElement('div');
                const isPast = parseDate(game.dateStr) < today;
                gameCard.className = `p-2 bg-gray-50 rounded-lg border border-gray-200 ${isPast ? 'opacity-60' : ''}`;

                let content;
                if (game.opponent === 'SPIELFREI') {
                        content = `<p class="font-medium text-sm">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: '2-digit' })} - ${game.league} (${game.round}): <span class="font-bold text-amber-600">SPIELFREI</span></p>`;
                } else {
                        content = `
                         <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center">
                             <div>
                                 <p class="font-medium text-gray-800 text-sm">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit', year: '2-digit' })} - ${game.league} (${game.round}): ${game.opponent}</p>
                                 <p class="text-xs text-gray-500">${game.time} @ ${game.location}</p>
                             </div>
                             <div class="mt-1 sm:mt-0">
                                <span class="text-xs font-semibold px-2 py-0.5 rounded-full ${game.home_away === 'HEIM' ? 'bg-blue-100 text-blue-800' : 'bg-green-100 text-green-800'}">${game.home_away}</span>
                             </div>
                         </div>`;
                }
                gameCard.innerHTML = content;
                listContainer.appendChild(gameCard);
            });
            } else { // Sort by round
                const allRounds = [...new Set(gamesToDisplay.map(g => g.round))];
                allRounds.sort((a,b) => {
                    const prefixA = a.charAt(0);
                    const prefixB = b.charAt(0);
                    const numA = parseInt(a.substring(1));
                    const numB = parseInt(b.substring(1));
                    if(prefixA !== prefixB) return prefixA === 'H' ? -1 : 1;
                    return numA - numB;
                });

                const gamesByRound = gamesToDisplay.reduce((acc, game) => {
                    if(!acc[game.round]) acc[game.round] = [];
                    acc[game.round].push(game);
                    return acc;
                }, {});

                allRounds.forEach(round => {
                    const roundHeader = document.createElement('h4');
                    roundHeader.className = "text-lg font-semibold text-gray-700 mt-4 mb-1 border-b pb-1";
                    roundHeader.textContent = `Runde ${round}`;
                    listContainer.appendChild(roundHeader);
                    
                    const gamesInRound = gamesByRound[round].sort((a,b) => parseDate(a.dateStr) - parseDate(b.dateStr));

                    gamesInRound.forEach(game => {
                         const gameCard = document.createElement('div');
                         const isPast = parseDate(game.dateStr) < today;
                         gameCard.className = `p-2 bg-gray-50 rounded-lg border border-gray-200 ${isPast ? 'opacity-60' : ''}`;
                         let content;
                         if (game.opponent === 'SPIELFREI') {
                               content = `<p class="font-medium text-sm">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: '2-digit' })} - ${game.league}: <span class="font-bold text-amber-600">SPIELFREI</span></p>`;
                         } else {
                               content = `
                                     <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center">
                                         <div>
                                             <p class="font-medium text-gray-800 text-sm">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit' })} - ${game.league}: ${game.opponent}</p>
                                             <p class="text-xs text-gray-500">${game.time} @ ${game.location}</p>
                                         </div>
                                         <div class="mt-1 sm:mt-0">
                                             <span class="text-xs font-semibold px-2 py-0.5 rounded-full ${game.home_away === 'HEIM' ? 'bg-blue-100 text-blue-800' : 'bg-green-100 text-green-800'}">${game.home_away}</span>
                                         </div>
                                     </div>`;
                         }
                         gameCard.innerHTML = content;
                         listContainer.appendChild(gameCard);
                    });
                });
            }
            
            contentGames.appendChild(container);

            document.getElementById('show-past-games-toggle').addEventListener('change', (e) => {
                showPastGames = e.target.checked;
                renderGamesList();
            });
            document.getElementById('sort-by-team-btn').addEventListener('click', () => {
                gamesSortOrder = 'team';
                renderGamesList();
            });
            document.getElementById('sort-by-date-btn').addEventListener('click', () => {
                gamesSortOrder = 'date';
                renderGamesList();
                setTimeout(() => {
                    const currentSystemWeek = getWeekNumber(new Date());
                    const currentWeekHeader = document.getElementById(`week-header-${currentSystemWeek}`);
                    if (currentWeekHeader) {
                        currentWeekHeader.scrollIntoView({ behavior: 'smooth', block: 'start' });
                    }
                }, 100);
            });
            document.getElementById('sort-by-round-btn').addEventListener('click', () => {
                gamesSortOrder = 'round';
                renderGamesList();
            });
        }

        // --- UPDATED FUNCTION ---
        function renderStatisticsTab() {
            contentStats.innerHTML = '';
            
            const container = document.createElement('div');
            container.className = "bg-white p-6 rounded-lg shadow-md";
            contentStats.appendChild(container);

            const title = document.createElement('h2');
            title.className = "text-3xl font-bold text-gray-800 mb-4 text-center";
            title.textContent = "Rangliste";
            container.appendChild(title);
            
            const controlsContainer = document.createElement('div');
            controlsContainer.className = "flex flex-col sm:flex-row justify-center items-center mb-6 gap-4";
            
            const statsModeControlHTML = `
                <div class="flex items-center space-x-1 rounded-lg bg-gray-200 p-1 text-gray-600">
                    <button data-mode="last3" class="stats-mode-btn sort-btn px-3 py-1 text-sm rounded-md ${statsMode === 'last3' ? 'active' : ''}">Letzte 3 Spiele</button>
                    <button data-mode="last5" class="stats-mode-btn sort-btn px-3 py-1 text-sm rounded-md ${statsMode === 'last5' ? 'active' : ''}">Letzte 5 Spiele</button>
                    <button data-mode="overall" class="stats-mode-btn sort-btn px-3 py-1 text-sm rounded-md ${statsMode === 'overall' ? 'active' : ''}">Gesamt</button>
                </div>`;
            
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = statsModeControlHTML;
            controlsContainer.appendChild(tempDiv.firstElementChild);

            if (temporarilyHiddenPlayers.size > 0) {
                const resetBtn = document.createElement('button');
                resetBtn.id = 'reset-stats-view-btn';
                resetBtn.className = 'px-4 py-2 bg-amber-500 text-white rounded-md hover:bg-amber-600 text-sm';
                resetBtn.textContent = `Ausgeblendete Spieler anzeigen (${temporarilyHiddenPlayers.size})`;
                controlsContainer.appendChild(resetBtn);
            }
            
            container.appendChild(controlsContainer);
            
            const playerStatsMap = getPlayerStats(statsMode);
            const defaultRankedPlayers = Array.from(playerStatsMap.keys()).sort((a, b) => (playerStatsMap.get(b)?.average || 0) - (playerStatsMap.get(a)?.average || 0));
            const allPlayersSet = new Set(state.players);
            let currentDisplayRanking = state.statsRanking.filter(p => allPlayersSet.has(p));
            
            state.players.forEach(p => {
                if (!currentDisplayRanking.includes(p)) {
                    currentDisplayRanking.push(p);
                }
            });
            state.statsRanking = currentDisplayRanking;

            const listContainer = document.createElement('div');
            listContainer.id = "stats-list-container"; // ID for SortableJS to find it
            container.appendChild(listContainer);
            
            if (state.statsRanking.length === 0) {
                listContainer.innerHTML = `<p class="text-gray-500">Keine Spieler vorhanden.</p>`;
            } else {
                const teamNames = state.teams;
                const teamSizes = [6, 6, 4, 4, 4];
                let teamIndex = 0;
                let playerThreshold = 0;
                let currentTeamContainer;
                let visualPlayerCount = 0;

                state.statsRanking.forEach((playerName) => {
                    if (temporarilyHiddenPlayers.has(playerName)) return;
                    
                    const playerStats = playerStatsMap.get(playerName) || { average: 0, gamesPlayed: 0 };
                    const player = { name: playerName, ...playerStats };
                    const actualRank = defaultRankedPlayers.indexOf(playerName) + 1;
                    
                    if (visualPlayerCount >= playerThreshold) {
                        currentTeamContainer = document.createElement('div');
                        currentTeamContainer.className = "stats-team-group"; // Dedicated class for SortableJS
                        if (visualPlayerCount > 0) {
                           currentTeamContainer.classList.add("mt-6", "border-t", "pt-4");
                        }
                        listContainer.appendChild(currentTeamContainer);
                        
                        const title = document.createElement('h3');
                        title.className = "text-xl font-semibold text-red-600 mb-2";
                        title.textContent = teamNames[teamIndex] || `Weitere Spieler`;
                        currentTeamContainer.appendChild(title);

                        if(teamIndex < teamSizes.length) {
                            playerThreshold += teamSizes[teamIndex];
                            teamIndex++;
                        } else {
                            playerThreshold = Infinity;
                        }
                    }
                    
                    let colorClass = 'text-gray-800';
                    if (player.average >= 600) colorClass = 'text-blue-600';
                    else if (player.average >= 540) colorClass = 'text-green-600';
                    else if (player.average >= 480) colorClass = 'text-amber-600';

                    const playerDiv = document.createElement('div');
                    playerDiv.className = 'player-draggable flex justify-between items-center p-2 bg-gray-50 rounded-md mb-1 cursor-grab hover:bg-gray-100';
                    playerDiv.dataset.playerName = player.name;
                    playerDiv.innerHTML = `
                        <div class="flex items-center">
                            <span class="font-medium text-gray-500 w-8 text-center text-sm">${actualRank > 0 ? `${actualRank}.` : '-'}</span>
                            <div>
                                <span class="font-medium text-gray-800 text-sm">${player.name}</span>
                                <span class="text-xs text-gray-500 ml-2">(${player.gamesPlayed} Sp.)</span>
                            </div>
                        </div>
                        <div class="text-base font-bold ${colorClass}">${player.gamesPlayed > 0 ? player.average.toFixed(2) : '0'}</div>
                    `;
                    playerDiv.addEventListener('click', () => {
                        temporarilyHiddenPlayers.add(player.name);
                        renderStatisticsTab();
                    });
                    currentTeamContainer.appendChild(playerDiv);
                    visualPlayerCount++;
                });
            }

            // Attach event listeners for controls
            container.querySelectorAll('.stats-mode-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    statsMode = btn.dataset.mode;
                    temporarilyHiddenPlayers.clear();
                    
                    const playerStats = getPlayerStats(statsMode);
                    const ranked = Array.from(playerStats.keys()).sort((a,b) => (playerStats.get(b)?.average || 0) - (playerStats.get(a)?.average || 0));
                    const unranked = state.players.filter(p => !playerStats.has(p)).sort();
                    state.statsRanking = [...ranked, ...unranked];
                    
                    saveStateToFirestore();
                    renderStatisticsTab();
                });
            });

            const resetBtn = container.querySelector('#reset-stats-view-btn');
            if (resetBtn) {
                resetBtn.addEventListener('click', () => {
                    temporarilyHiddenPlayers.clear();
                    renderStatisticsTab();
                });
            }
            
            // REMOVED old drag/drop listeners and replaced with a single call
            initializeStatsDragAndDrop();
        }

        // --- NEW FUNCTION ---
        // Initializes SortableJS for the statistics tab
        function initializeStatsDragAndDrop() {
            const listContainer = document.getElementById("stats-list-container");
            if (!listContainer) return;

            // Find all the individual team containers within the list
            const teamContainers = listContainer.querySelectorAll('.stats-team-group');

            teamContainers.forEach(container => {
                new Sortable(container, {
                    group: 'shared-stats', // Allow dragging between team lists
                    animation: 150,
                    ghostClass: 'dragging', // Use your existing CSS for the ghost element
                    onEnd: function (evt) {
                        // This function runs after a player is dropped
                        const newRanking = [];
                        // Read the new player order directly from the DOM
                        document.querySelectorAll('#stats-list-container .player-draggable').forEach(playerDiv => {
                            newRanking.push(playerDiv.dataset.playerName);
                        });

                        // Update the state with the new order
                        state.statsRanking = newRanking;
                        saveStateToFirestore();
                        
                        // Re-render the tab to update ranks and ensure consistency
                        renderStatisticsTab();
                    }
                });
            });
        }
        
        function getDragAfterElement(container, y) {
            const draggableElements = [...container.querySelectorAll('.player-draggable:not(.dragging)')];
            return draggableElements.reduce((closest, child) => {
                const box = child.getBoundingClientRect();
                const offset = y - box.top - box.height / 2;
                if (offset < 0 && offset > closest.offset) {
                    return { offset: offset, element: child };
                } else {
                    return closest;
                }
            }, { offset: Number.NEGATIVE_INFINITY }).element;
        }

        function renderAvailabilityTab() {
            contentAvailability.innerHTML = '';
            const container = document.createElement('div');
            container.className = "bg-white p-4 sm:p-6 rounded-lg shadow-md";
            contentAvailability.appendChild(container);

            // --- Header with Title and Season Toggle ---
            const headerContainer = document.createElement('div');
            headerContainer.className = "flex flex-col sm:flex-row justify-between items-center mb-6 gap-4";
            container.appendChild(headerContainer);

            const titleContainer = document.createElement('div');
            titleContainer.className = 'text-center sm:text-left';
            headerContainer.appendChild(titleContainer);

            const title = document.createElement('h2');
            title.className = "text-2xl sm:text-3xl font-bold text-gray-800";
            title.textContent = "Verfügbarkeiten";
            titleContainer.appendChild(title);

            const subtitle = document.createElement('h3');
            subtitle.className = "text-lg font-semibold text-gray-600 mt-1";
            subtitle.textContent = availabilitySeasonView === 'herbst' ? 'Herbst-Saison 2025' : 'Frühjahrs-Saison 2026';
            titleContainer.appendChild(subtitle);

            const toggleContainer = document.createElement('div');
            toggleContainer.className = "flex items-center space-x-1 rounded-lg bg-gray-200 p-1 text-gray-600";
            toggleContainer.innerHTML = `
                <button id="season-herbst-btn" class="sort-btn w-24 px-4 py-1.5 text-sm rounded-md ${availabilitySeasonView === 'herbst' ? 'active' : ''}">Herbst</button>
                <button id="season-fruehjahr-btn" class="sort-btn w-24 px-4 py-1.5 text-sm rounded-md ${availabilitySeasonView === 'fruehjahr' ? 'active' : ''}">Frühjahr</button>
            `;
            headerContainer.appendChild(toggleContainer);

            // --- Determine weeks to show based on season and view (mobile/desktop) ---
            const weeks2025 = WEEKS.filter(w => w.startsWith('2025'));
            const weeks2026 = WEEKS.filter(w => w.startsWith('2026'));

            if (weeks2025.length < weeks2026.length) {
                weeks2025.push('2025-WK51-PH'); // Placeholder logic from original code
            }

            const weeksForSeason = availabilitySeasonView === 'herbst' ? weeks2025 : weeks2026;
            const currentSystemWeek = getWeekNumber(new Date());
            let weeksToShow;

            const isMobile = window.innerWidth < 768;

            if (isMobile) {
                // --- Mobile View Logic ---
                const currentWeekInSeasonIndex = weeksForSeason.findIndex(w => w >= currentSystemWeek);

                if (!container.dataset.mobileIndexInitialized || container.dataset.currentSeason !== availabilitySeasonView) {
                    mobileAvailabilityWeekIndex = currentWeekInSeasonIndex > -1 ? currentWeekInSeasonIndex : 0;
                    container.dataset.mobileIndexInitialized = 'true';
                    container.dataset.currentSeason = availabilitySeasonView;
                }

                weeksToShow = weeksForSeason.slice(mobileAvailabilityWeekIndex, mobileAvailabilityWeekIndex + 4);

                const mobileNav = document.createElement('div');
                mobileNav.className = 'flex justify-between items-center my-4';
                
                const prevBtn = document.createElement('button');
                prevBtn.innerHTML = '&#9664; Zurück';
                prevBtn.className = 'px-4 py-2 bg-gray-200 text-gray-800 rounded-md hover:bg-gray-300 disabled:opacity-50';
                prevBtn.disabled = mobileAvailabilityWeekIndex === 0;
                prevBtn.onclick = () => {
                    mobileAvailabilityWeekIndex = Math.max(0, mobileAvailabilityWeekIndex - 1);
                    renderAvailabilityTab();
                };

                const nextBtn = document.createElement('button');
                nextBtn.innerHTML = 'Weiter &#9654;';
                nextBtn.className = 'px-4 py-2 bg-gray-200 text-gray-800 rounded-md hover:bg-gray-300 disabled:opacity-50';
                nextBtn.disabled = mobileAvailabilityWeekIndex >= weeksForSeason.length - 4;
                nextBtn.onclick = () => {
                    mobileAvailabilityWeekIndex = Math.min(weeksForSeason.length - 4, mobileAvailabilityWeekIndex + 1);
                    renderAvailabilityTab();
                };

                mobileNav.appendChild(prevBtn);
                mobileNav.appendChild(nextBtn);
                container.appendChild(mobileNav);

            } else {
                // --- Desktop/Tablet View Logic ---
                weeksToShow = weeksForSeason;
            }

            // --- Grid Container ---
            const scrollContainer = document.createElement('div');
            scrollContainer.className = isMobile ? 'overflow-x-auto' : 'overflow-auto max-h-[70vh]';
            container.appendChild(scrollContainer);

            const grid = document.createElement('div');
            grid.className = 'inline-grid gap-x-1 gap-y-2';
            scrollContainer.appendChild(grid);

            grid.style.gridTemplateColumns = `minmax(160px, auto) repeat(${weeksToShow.length}, 40px)`;

            // --- Header Row ---
            const topLeftCell = document.createElement('div');
            topLeftCell.className = isMobile ? '' : 'sticky top-0 left-0 z-20 bg-white border-b border-r';
            grid.appendChild(topLeftCell);
            
            weeksToShow.forEach(week => {
                const isPlaceholder = week.includes('-PH');
                const weekHeader = document.createElement('div');
                weekHeader.className = `text-xs text-center font-bold text-gray-600 h-8 flex items-end justify-center ${isMobile ? '' : 'sticky top-0 z-10 bg-white border-b pb-1'}`;
                weekHeader.textContent = isPlaceholder ? `KW${week.split('-WK')[1].split('-PH')[0]}` : `KW${week.replace(/2025-WK|2026-WK/, '')}`;
                
                if (week < currentSystemWeek && !isPlaceholder) {
                    weekHeader.classList.add('opacity-50');
                }
                if (isPlaceholder) {
                    weekHeader.classList.add('opacity-30');
                }
                grid.appendChild(weekHeader);
            });

            // --- Player Rows ---
            const rankedPlayers = [...state.statsRanking];
            state.players.forEach(p => {
                if(!rankedPlayers.includes(p)) rankedPlayers.push(p);
            });
            
            const teamNames = state.teams;
            const teamSizes = [6, 6, 4, 4, 4];
            let teamIndex = 0;
            let playerThreshold = 0;

            rankedPlayers.forEach((player, index) => {
                if (index >= playerThreshold) {
                    const teamHeader = document.createElement('div');
                    teamHeader.className = 'font-semibold text-red-600 text-sm py-2 mt-2';
                    teamHeader.textContent = teamNames[teamIndex] || 'Weitere Spieler';
                    teamHeader.style.gridColumn = `1 / -1`;
                    grid.appendChild(teamHeader);

                    if(teamIndex < teamSizes.length) {
                        playerThreshold += teamSizes[teamIndex];
                        teamIndex++;
                    } else {
                        playerThreshold = Infinity;
                    }
                }

                const playerNameCell = document.createElement('div');
                playerNameCell.className = 'sticky left-0 bg-white pr-2 font-semibold text-sm text-gray-800 flex items-center border-r h-9 z-10';
                playerNameCell.textContent = player;
                grid.appendChild(playerNameCell);

                weeksToShow.forEach(week => {
                    grid.appendChild(createAvailabilityCell(player, week, currentSystemWeek));
                });
            });

            // --- Attach Event Listeners for Season Toggle ---
            document.getElementById('season-herbst-btn').addEventListener('click', () => {
                availabilitySeasonView = 'herbst';
                if(container.dataset.mobileIndexInitialized) container.dataset.mobileIndexInitialized = 'false';
                renderAvailabilityTab();
            });
            document.getElementById('season-fruehjahr-btn').addEventListener('click', () => {
                availabilitySeasonView = 'fruehjahr';
                if(container.dataset.mobileIndexInitialized) container.dataset.mobileIndexInitialized = 'false';
                renderAvailabilityTab();
            });
        }
        
        function createAvailabilityCell(player, week, currentSystemWeek) {
            const isPlaceholder = week.includes('-PH');
            if (isPlaceholder) {
                const cell = document.createElement('div');
                cell.className = 'w-9 h-9 bg-gray-200 opacity-70 rounded-sm cursor-not-allowed';
                return cell;
            }

            const isPast = week < currentSystemWeek;
            const availabilityForWeek = state.playerAvailability[week] || {};
            const status = availabilityForWeek[player] || 'available';

            const cell = document.createElement('div');
            cell.dataset.player = player;
            cell.dataset.week = week;

            let bgColor = '';
            if (isPast) {
                switch (status) {
                    case 'available': bgColor = 'bg-gray-200 opacity-70'; break;
                    case 'maybe': bgColor = 'bg-yellow-200 opacity-50'; break;
                    case 'unavailable': bgColor = 'bg-red-200 opacity-50'; break;
                }
                bgColor += ' cursor-not-allowed';
            } else {
                switch (status) {
                    case 'available': bgColor = 'bg-green-200 hover:bg-green-300'; break;
                    case 'maybe': bgColor = 'bg-yellow-200 hover:bg-yellow-300'; break;
                    case 'unavailable': bgColor = 'bg-red-200 hover:bg-red-300'; break;
                }
            }
            cell.className = `availability-cell ${bgColor} w-9 h-9`;
            
            if (!isPast) {
                cell.addEventListener('click', () => {
                    const currentStatus = state.playerAvailability[week]?.[player] || 'available';
                    let nextStatus;
                    if (currentStatus === 'available') nextStatus = 'maybe';
                    else if (currentStatus === 'maybe') nextStatus = 'unavailable';
                    else nextStatus = 'available';
                    setPlayerAvailability(player, nextStatus, week);
                });
            }

            return cell;
        }


        function renderActionButtons() {
            planActionsContainer.innerHTML = '';
            if (!currentWeek) return;
            
            // Button to share the current week's plan
            const shareBtn = document.createElement('button');
            shareBtn.className = 'px-3 py-2 bg-blue-500 text-white text-sm rounded-md hover:bg-blue-600 transition-colors flex items-center';
            shareBtn.innerHTML = `<svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12s-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367-2.684zm0 9.368a3 3 0 105.367 2.684 3 3 0 00-5.367-2.684z"></path></svg> Teilen`;
            shareBtn.addEventListener('click', showShareModal);
            planActionsContainer.appendChild(shareBtn);
        }

        
        function getPlayerStats(mode) {
             const playerGameHistory = new Map();
            for (const week in state.gamePlan) {
                for (const team in state.gamePlan[week]) {
                    const game = state.schedule.find(g => g.week === week && g.league === team);
                    if(!game) continue;

                    state.gamePlan[week][team].forEach((playerData, index) => {
                        const isSmallLeague = state.smallLeagues.includes(team);
                        const numRegular = isSmallLeague ? 4 : 6;
                        const isSubstitute = index >= numRegular;

                        if (playerData.name && playerData.score) {
                            const played = !isSubstitute || playerData.played;
                            if (played) {
                                const score = parseInt(playerData.score, 10);
                                if (!isNaN(score) && score > 0) {
                                    if (!playerGameHistory.has(playerData.name)) {
                                        playerGameHistory.set(playerData.name, []);
                                    }
                                    playerGameHistory.get(playerData.name).push({ score, date: parseDate(game.dateStr) });
                                }
                            }
                        }
                    });
                }
            }
            
            const playerStatsMap = new Map();
            for (const [name, games] of playerGameHistory.entries()) {
                games.sort((a,b) => b.date - a.date);
                let gamesToAverage = games;
                if (mode === 'last5') gamesToAverage = games.slice(0, 5);
                if (mode === 'last3') gamesToAverage = games.slice(0, 3);
                
                if (gamesToAverage.length > 0) {
                    const totalKegel = gamesToAverage.reduce((sum, game) => sum + game.score, 0);
                    playerStatsMap.set(name, {
                        average: totalKegel / gamesToAverage.length,
                        gamesPlayed: gamesToAverage.length
                    });
                }
            }
            return playerStatsMap;
        }

        function renderPlayerPool() {
             playerPoolContainer.innerHTML = '';
             if (!currentWeek) return;

             const availabilityForWeek = state.playerAvailability[currentWeek] || {};
             
             const assignedPlayers = new Set();
             if (state.gamePlan[currentWeek]) {
                  Object.values(state.gamePlan[currentWeek]).forEach(teamPlan => {
                       teamPlan.forEach(slot => {
                           if (slot.name) {
                               assignedPlayers.add(slot.name);
                           }
                       });
                  });
             }

             const container = document.createElement('div');
             container.className = "bg-gray-50 border border-gray-200 rounded-lg";
             
             let content = `
                  <button id="player-pool-toggle-btn" class="w-full text-left p-4 flex justify-between items-center">
                      <h3 class="text-lg font-semibold text-amber-600">Spieler-Pool</h3>
                      <svg class="w-5 h-5 ml-4 flex-shrink-0 transition-transform duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path></svg>
                  </button>
                  <div id="player-pool-content" class="px-4 border-t border-gray-200 collapsible-content">
                       <div class="py-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
             `;

            const teamNames = state.teams;
            const teamSizes = [6, 6, 4, 4, 4];
            let teamIndex = 0;
            let playerThreshold = 0;
            
            const rankedPlayers = [...state.statsRanking];
              state.players.forEach(p => {
                  if (!rankedPlayers.includes(p)) {
                      rankedPlayers.push(p);
                  }
              });

            for (let i = 0; i < teamNames.length + 1; i++) {
                const currentTeamName = teamNames[i] || 'Weitere Spieler';
                const start = i === 0 ? 0 : playerThreshold;
                const end = i < teamNames.length ? start + teamSizes[i] : rankedPlayers.length;
                
                const playersInGroup = rankedPlayers.slice(start, end);
                playerThreshold = end;
                
                if (playersInGroup.length === 0) continue;

                content += `<div data-team-group="${currentTeamName}">`;
                content += `<h4 class="text-md font-semibold text-red-600 mb-1 border-b">${currentTeamName}</h4>`;
                content += `<div class="flex flex-wrap gap-2 pt-2">`;

                playersInGroup.forEach(player => {
                    const isAssigned = assignedPlayers.has(player);
                    const isMaybe = availabilityForWeek[player] === 'maybe';
                    const isUnavailable = availabilityForWeek[player] === 'unavailable';
                    
                    let classes = 'player-card text-sm font-medium px-3 py-1.5 rounded-lg border-2 ';
                    if(isUnavailable) {
                        classes += 'unavailable';
                    } else if(isAssigned) {
                        classes += 'assigned';
                    } else {
                        classes += 'bg-white ';
                        classes += isMaybe ? 'maybe border-amber-400 text-amber-700' : 'border-gray-300 text-gray-700';
                    }

                    content += `<div class="${classes}" draggable="${!isAssigned && !isUnavailable}" data-player-name="${player}">${player}</div>`;
                });
                
                content += `</div></div>`;
            }


            content += '</div></div>';
            container.innerHTML = content;
            playerPoolContainer.appendChild(container);

            // Add drag listeners to player cards
            playerPoolContainer.querySelectorAll('.player-card:not(.assigned):not(.unavailable)').forEach(card => {
                card.addEventListener('dragstart', (e) => {
                    e.dataTransfer.setData('text/plain', e.target.dataset.playerName);
                    setTimeout(() => e.target.classList.add('dragging'), 0);
                });
                card.addEventListener('dragend', (e) => {
                    e.target.classList.remove('dragging');
                });
                 card.addEventListener('click', (e) => {
                      const playerName = e.currentTarget.dataset.playerName;
                      const teamName = e.currentTarget.closest('[data-team-group]').dataset.teamGroup;
                      handlePlayerCardClick(playerName, teamName);
                 });
            });


            const toggleBtn = document.getElementById('player-pool-toggle-btn');
            const contentDiv = document.getElementById('player-pool-content');
            
            toggleBtn.addEventListener('click', () => {
                const icon = toggleBtn.querySelector('svg');
                if (contentDiv.style.maxHeight && contentDiv.style.maxHeight !== '0px') {
                    contentDiv.style.maxHeight = '0px';
                    icon.style.transform = 'rotate(0deg)';
                    playerPoolIsOpen = false;
                } else {
                    contentDiv.style.maxHeight = contentDiv.scrollHeight + "px";
                    icon.style.transform = 'rotate(180deg)';
                    playerPoolIsOpen = true;
                }
            });
            
            // Restore collapse state
             if (playerPoolIsOpen) {
               contentDiv.style.maxHeight = contentDiv.scrollHeight + "px";
               toggleBtn.querySelector('svg').style.transform = 'rotate(180deg)';
             } else {
               contentDiv.style.maxHeight = '0px';
               toggleBtn.querySelector('svg').style.transform = 'rotate(0deg)';
             }
        }

        function syncPlayerPoolState() {
            if (!currentWeek) return;
            const assignedPlayers = new Set();
            if (state.gamePlan[currentWeek]) {
                Object.values(state.gamePlan[currentWeek]).forEach(teamPlan => {
                    teamPlan.forEach(slot => {
                        if (slot.name) {
                            assignedPlayers.add(slot.name);
                        }
                    });
                });
            }

            playerPoolContainer.querySelectorAll('.player-card').forEach(card => {
                const playerName = card.dataset.playerName;
                const isUnavailable = card.classList.contains('unavailable');
                if (assignedPlayers.has(playerName)) {
                    card.classList.add('assigned');
                    card.draggable = false;
                } else {
                    card.classList.remove('assigned');
                    if (!isUnavailable) {
                        card.draggable = true;
                    }
                }
            });
        }

        function updatePlayerCardState(playerName, isAssigned) {
             if (!playerName) return;
             const card = playerPoolContainer.querySelector(`.player-card[data-player-name="${playerName}"]`);
             if (card) {
                 if (isAssigned) {
                     card.classList.add('assigned');
                     card.draggable = false;
                 } else {
                     card.classList.remove('assigned');
                     card.draggable = true;
                 }
             }
        }


        // --- EVENT HANDLERS & LOGIC ---
        function handlePlayerCardClick(playerName, teamName) {
            const isSmallLeague = state.smallLeagues.includes(teamName);
            const numPlayersTotal = isSmallLeague ? 5 : 8;
            const teamPlan = state.gamePlan[currentWeek]?.[teamName] || Array(numPlayersTotal).fill({name: '', score: '', played: false});

            let firstEmptyIndex = -1;
            for (let i = 0; i < numPlayersTotal; i++) {
                if (!teamPlan[i] || !teamPlan[i].name) {
                    firstEmptyIndex = i;
                    break;
                }
            }

            if (firstEmptyIndex !== -1) {
                const inputToUpdate = document.querySelector(`.player-select[data-team="${teamName}"][data-position="${firstEmptyIndex}"]`);
                if (inputToUpdate) {
                    inputToUpdate.value = playerName;
                    saveWeek();
                    syncPlayerPoolState();
                    validatePlayerAssignments();
                }
            }
        }

        function showDeleteConfirmation(name) {
            playerNameToDelete.textContent = name;
            deleteModal.classList.remove('hidden');

            let countdown = 3;
            confirmDeleteBtn.disabled = true;
            confirmDeleteBtn.textContent = `Löschen in ${countdown}s`;

            const interval = setInterval(() => {
                countdown--;
                if (countdown > 0) {
                    confirmDeleteBtn.textContent = `Löschen in ${countdown}s`;
                } else {
                    clearInterval(interval);
                    confirmDeleteBtn.disabled = false;
                    confirmDeleteBtn.textContent = 'Jetzt Löschen';
                }
            }, 1000);

            const confirmHandler = () => {
                clearInterval(interval);
                performDelete(name);
                deleteModal.classList.add('hidden');
                confirmDeleteBtn.removeEventListener('click', confirmHandler);
            };

            const cancelHandler = () => {
                clearInterval(interval);
                deleteModal.classList.add('hidden');
                cancelDeleteBtn.removeEventListener('click', cancelHandler);
            };
            
            confirmDeleteBtn.addEventListener('click', confirmHandler, { once: true });
            cancelDeleteBtn.addEventListener('click', cancelHandler, { once: true });
        }
        
        function performDelete(name) {
            state.players = state.players.filter(p => p !== name);
            for (const week in state.gamePlan) {
                for (const team in state.gamePlan[week]) {
                    state.gamePlan[week][team] = state.gamePlan[week][team].map(p => 
                        p.name === name ? { name: '', score: '', played: false } : p
                    );
                }
            }
            state.statsRanking = state.statsRanking.filter(p => p !== name);
            saveStateToFirestore();
            renderAll(); // A full re-render is acceptable after a destructive action
        }

        function addPlayer() {
            const name = playerInput.value.trim();
            if (name && !state.players.includes(name)) {
                state.players.push(name);
                state.players.sort();
                playerInput.value = '';
                saveStateToFirestore();
                // Manually trigger only the necessary UI updates
                renderPlayers();
                renderAvailabilityTab();
            }
        }

        function addTeam() {
            const name = teamInput.value.trim();
            if (name && !state.teams.includes(name)) {
                state.teams.push(name);
                state.teams.sort();
                teamInput.value = '';
                saveConfigToFirestore(); // Triggers update via onSnapshot
            }
        }

        function deleteTeam(name) {
            // NOTE: A proper confirmation modal should be implemented here for better UX.
            state.teams = state.teams.filter(t => t !== name);
            saveConfigToFirestore(); // Triggers update via onSnapshot
        }
        
        function switchTab(tab) {
            const tabs = { plan: tabPlan, games: tabGames, stats: tabStats, availability: tabAvailability, zuschauer: tabZuschauer };
            const contents = { plan: contentPlan, games: contentGames, stats: contentStats, availability: contentAvailability, zuschauer: contentZuschauer };
            
            for (const key in tabs) {
                 tabs[key].classList.remove('active');
                 contents[key].classList.add('hidden');
            }

            tabs[tab].classList.add('active');
            contents[tab].classList.remove('hidden');

            // Also update mobile menu appearance if needed (optional)
            document.querySelectorAll('.mobile-tab-btn').forEach(btn => {
                if (btn.dataset.tab === tab) {
                    btn.classList.add('bg-gray-200', 'font-semibold');
                } else {
                    btn.classList.remove('bg-gray-200', 'font-semibold');
                }
            });
        }
        
        function selectWeek(week) {
            currentWeek = week;
            openPlanPanels.clear();
            renderAll();
        }
        
        function getPlayerRoundAssignments(excludeWeek, specificWeekPlan = null) {
            const assignments = new Map();
            
            const processWeek = (week, weekPlan) => {
                 for (const team in weekPlan) {
                     const game = state.schedule.find(g => g.week === week && g.league === team);
                     if (!game || !game.round) continue;

                     const isSmallLeague = state.smallLeagues.includes(team);
                     const numRegular = isSmallLeague ? 4 : 6;

                     weekPlan[team].forEach((playerData, index) => {
                         const isSubstitute = index >= numRegular;
                         if (playerData.name && (!isSubstitute || playerData.played)) {
                             if (!assignments.has(playerData.name)) assignments.set(playerData.name, new Set());
                             assignments.get(playerData.name).add(game.round);
                         }
                     });
                 }
            }

            if(specificWeekPlan){
                 processWeek(excludeWeek, specificWeekPlan);
            } else {
                for (const week in state.gamePlan) {
                    if (week === excludeWeek) continue;
                    processWeek(week, state.gamePlan[week]);
                }
            }
            return assignments;
        }

        function showPlayerDropdown(inputElement, dropdownElement) {
            const searchTerm = inputElement.value.toLowerCase();
            const roundType = inputElement.dataset.round;
            const availabilityForWeek = state.playerAvailability[currentWeek] || {};

            const globalAssignments = getPlayerRoundAssignments(currentWeek);
            const playersUsedGloballyInRound = new Set();
            globalAssignments.forEach((rounds, player) => {
                if (rounds.has(roundType)) {
                    playersUsedGloballyInRound.add(player);
                }
            });

            const playersUsedThisWeekInRound = new Set();
            document.querySelectorAll(`#plan-container input.player-select[data-round="${roundType}"]`).forEach(select => {
                if (select !== inputElement && select.value) {
                   const team = select.dataset.team;
                   const position = parseInt(select.dataset.position, 10);
                   const isSmallLeague = state.smallLeagues.includes(team);
                   const numRegular = isSmallLeague ? 4 : 6;
                   const isSubstitute = position >= numRegular;
                   let hasPlayed = !isSubstitute;
                   if(isSubstitute) {
                        const checkbox = document.querySelector(`.substitute-checkbox[data-team="${team}"][data-position="${position}"]`);
                        hasPlayed = checkbox && checkbox.checked;
                   }
                   if(hasPlayed) {
                       playersUsedThisWeekInRound.add(select.value);
                   }
                }
            });

            let availablePlayers = state.players.filter(player => {
                const isCurrentlySelected = player === inputElement.value;
                const usedThisWeek = playersUsedThisWeekInRound.has(player);
                const usedGlobally = playersUsedGloballyInRound.has(player);
                const matchesSearch = player.toLowerCase().includes(searchTerm);
                const isUnavailable = availabilityForWeek[player] === 'unavailable';

                return (isCurrentlySelected || (!usedThisWeek && !usedGlobally && !isUnavailable)) && matchesSearch;
            });

            availablePlayers.sort((a, b) => {
                const indexA = state.statsRanking.indexOf(a);
                const indexB = state.statsRanking.indexOf(b);
                if (indexA === -1) return 1;
                if (indexB === -1) return -1;
                return indexA - indexB;
            });

            dropdownElement.innerHTML = '';
            if (availablePlayers.length > 0) {
                availablePlayers.forEach(player => {
                    const item = document.createElement('div');
                    item.className = 'px-2 py-1 hover:bg-gray-100 cursor-pointer text-sm flex justify-between items-center';
                    
                    let playerText = player;
                    if (availabilityForWeek[player] === 'maybe') {
                        playerText += ' <span class="text-yellow-500 font-bold ml-2">?</span>';
                    }
                    item.innerHTML = playerText;
                    
                    item.addEventListener('mousedown', (e) => {
                        e.preventDefault();
                        inputElement.value = player;
                        dropdownElement.classList.add('hidden');
                        validatePlayerAssignments();
                        saveWeek(); // Autosave
                    });
                    dropdownElement.appendChild(item);
                });
                dropdownElement.classList.remove('hidden');
            } else {
                dropdownElement.classList.add('hidden');
            }
        }

        function validatePlayerAssignments() {
            const allPlayerInputs = document.querySelectorAll('#plan-container input.player-select');
            allPlayerInputs.forEach(input => input.classList.remove('error'));

            const globalAssignments = getPlayerRoundAssignments(currentWeek);
            
            const weeklyAssignments = new Map(); 
            allPlayerInputs.forEach(input => {
                const player = input.value;
                if (!player) return;

                const round = input.dataset.round;
                const team = input.dataset.team;
                const position = parseInt(input.dataset.position, 10);
                
                const isSmallLeague = state.smallLeagues.includes(team);
                const numRegular = isSmallLeague ? 4 : 6;
                const isSubstitute = position >= numRegular;
                
                let hasPlayed = !isSubstitute;
                if (isSubstitute) {
                    const checkbox = document.querySelector(`.substitute-checkbox[data-team="${team}"][data-position="${position}"]`);
                    hasPlayed = checkbox && checkbox.checked;
                }

                if (hasPlayed) {
                    if (!weeklyAssignments.has(player)) weeklyAssignments.set(player, new Map());
                    const playerRounds = weeklyAssignments.get(player);
                    if (!playerRounds.has(round)) playerRounds.set(round, []);
                    playerRounds.get(round).push(input);
                }
            });
            
            let hasError = false;
            allPlayerInputs.forEach(input => {
                const player = input.value;
                if (!player) return;

                const round = input.dataset.round;
                
                // Check against other weeks
                if (globalAssignments.has(player) && globalAssignments.get(player).has(round)) {
                    input.classList.add('error');
                    hasError = true;
                }
                
                // Check within the current week
                if (weeklyAssignments.get(player)?.get(round)?.length > 1) {
                    weeklyAssignments.get(player).get(round).forEach(s => s.classList.add('error'));
                    hasError = true;
                }
            });
            
            return !hasError;
        }

        function saveWeek() {
            if (!currentWeek) return;
            
            const newWeekPlan = state.gamePlan[currentWeek] || {};
            
            const gamesThisWeek = state.schedule.filter(g => g.week === currentWeek);
            gamesThisWeek.forEach(game => {
                 const isSmallLeague = state.smallLeagues.includes(game.league);
                 const numPlayers = isSmallLeague ? 5 : 8;
                 if (!newWeekPlan[game.league]) {
                      newWeekPlan[game.league] = Array(numPlayers).fill({name: '', score: '', played: false});
                 }
            });

            const allPlayerInputs = document.querySelectorAll(`#plan-container input.player-select`);
            allPlayerInputs.forEach(playerInput => {
                const team = playerInput.dataset.team;
                const position = parseInt(playerInput.dataset.position);
                const scoreInput = document.querySelector(`.kegel-score[data-team="${team}"][data-position="${position}"]`);
                
                const isSmallLeague = state.smallLeagues.includes(team);
                const numRegular = isSmallLeague ? 4 : 6;
                const isSubstitute = position >= numRegular;
                let played = !isSubstitute;

                if(isSubstitute) {
                    const checkbox = document.querySelector(`.substitute-checkbox[data-team="${team}"][data-position="${position}"]`);
                    played = checkbox ? checkbox.checked : false;
                }

                if (newWeekPlan[team] && newWeekPlan[team][position] !== undefined) {
                    newWeekPlan[team][position] = {
                        name: playerInput.value,
                        score: scoreInput ? scoreInput.value : '',
                        played: played
                    };
                }
            });

            state.gamePlan[currentWeek] = newWeekPlan;
            saveStateToFirestore();
            updateAllTeamHeaderCountsForCurrentWeek();
        }

        function updateAllTeamHeaderCountsForCurrentWeek() {
             if (!currentWeek) return;
             const weekPlan = state.gamePlan[currentWeek] || {};
             
             document.querySelectorAll('#plan-container [data-team-name]').forEach(teamDiv => {
                 const teamName = teamDiv.dataset.teamName;
                 const headerButton = teamDiv.querySelector('button.w-full');
                 if (!headerButton) return;

                 const isSmallLeague = state.smallLeagues.includes(teamName);
                 const numRegular = isSmallLeague ? 4 : 6;
                 const numErsatz = (isSmallLeague ? 5 : 8) - numRegular;

                 const teamPlan = weekPlan[teamName] || [];
                 const regularFilled = teamPlan.slice(0, numRegular).filter(p => p && p.name).length;
                 const ersatzFilled = teamPlan.slice(numRegular).filter(p => p && p.name).length;
                 
                 const countSpan = headerButton.querySelector('span.text-xs.sm\\:text-sm.font-medium');
                 if(countSpan){
                      countSpan.textContent = `${regularFilled}/${numRegular} & ${ersatzFilled}/${numErsatz} Ersatz`;
                 }
             });
        }
        
        function copyPreviousLineup() {
            if (!currentWeek) return;
            const currentWeekIndex = WEEKS.indexOf(currentWeek);
            if (currentWeekIndex === 0) {
                alert("Es gibt keine vorherige Woche zum Kopieren.");
                return;
            }

            const previousWeek = WEEKS[currentWeekIndex - 1];
            const previousPlan = state.gamePlan[previousWeek];

            if (!previousPlan || Object.keys(previousPlan).length === 0) {
                alert(`Keine Aufstellung für die vorherige Woche (${previousWeek}) gefunden.`);
                return;
            }
            
            const newPlanForCurrentWeek = JSON.parse(JSON.stringify(previousPlan));
            for(const team in newPlanForCurrentWeek) {
                newPlanForCurrentWeek[team].forEach(playerSlot => {
                    playerSlot.score = ''; // Reset scores
                    playerSlot.played = false; // Reset substitute played status
                });
            }

            state.gamePlan[currentWeek] = newPlanForCurrentWeek;
            
            saveStateToFirestore();
            renderGamePlanUI(); 
        }

        function showShareModal() {
            if (!currentWeek) return;

            let text = `*Aufstellung ${currentWeek.replace('-WK', '-KW')}*\n\n`;
            const weekPlan = state.gamePlan[currentWeek] || {};
            const gamesThisWeek = state.schedule.filter(g => g.week === currentWeek).sort((a,b) => parseDate(a.dateStr) - parseDate(b.dateStr));

            state.teams.forEach(teamName => {
                const game = gamesThisWeek.find(g => g.league === teamName);
                if (!game) return;

                const teamPlan = weekPlan[teamName] || [];
                const filledSlots = teamPlan.filter(p => p.name);
                if (filledSlots.length === 0) return;

                text += `*${teamName}* (${game.home_away} vs ${game.opponent})\n`;
                
                const isSmallLeague = state.smallLeagues.includes(teamName);
                const numRegular = isSmallLeague ? 4 : 6;
                
                const regulars = teamPlan.slice(0, numRegular).filter(p => p.name);
                const substitutes = teamPlan.slice(numRegular).filter(p => p.name);

                regulars.forEach((p) => {
                    text += `- ${p.name}\n`;
                });

                if (substitutes.length > 0) {
                    text += `_Ersatz:_\n`;
                    substitutes.forEach(p => {
                        text += `- ${p.name}\n`;
                    });
                }
                text += `\n`;
            });
            
            shareTextContainer.value = text.trim();
            shareModal.classList.remove('hidden');
        }

        function copyShareText() {
            shareTextContainer.select();
            document.execCommand('copy');
            copyShareTextBtn.textContent = 'Kopiert!';
            setTimeout(() => {
                copyShareTextBtn.textContent = 'Text kopieren';
            }, 2000);
        }

        function setPlayerAvailability(player, status, week) {
            if (!state.playerAvailability[week]) {
                state.playerAvailability[week] = {};
            }
            
            if (status === 'available') {
                delete state.playerAvailability[week][player];
            } else {
                state.playerAvailability[week][player] = status;
            }
            
            saveStateToFirestore();
            renderAvailabilityTab();
            if(week === currentWeek) { 
                renderPlayerPool();
            }
        }

        function renderSpectatorTab() {
            contentZuschauer.innerHTML = '';
            const container = document.createElement('div');
            container.className = "bg-white p-4 sm:p-6 rounded-lg shadow-md space-y-6";

            const title = document.createElement('h2');
            title.className = "text-2xl sm:text-3xl font-bold text-gray-800 text-center sm:text-left";
            title.textContent = "Zuschauer & Mitfahrgelegenheiten";
            container.appendChild(title);

            const today = new Date();
            today.setHours(0, 0, 0, 0);

            const upcomingGames = state.schedule
                .filter(game => parseDate(game.dateStr) >= today && game.opponent !== 'SPIELFREI')
                .sort((a,b) => parseDate(a.dateStr) - parseDate(b.dateStr));

            if (upcomingGames.length === 0) {
                container.innerHTML += `<p class="text-gray-500 text-center py-8">Keine zukünftigen Spiele geplant.</p>`;
            } else {
                upcomingGames.forEach(game => {
                    const gameId = getGameId(game);
                    const gamePlan = state.spectatorPlan[gameId] || { attending: [], needsRide: [], offersRide: {} };
                    const currentUser = "DemoUser"; // Replace with actual logged-in user logic

                    const gameCard = document.createElement('div');
                    gameCard.className = 'p-4 bg-gray-50 rounded-lg border border-gray-200';
                    
                    const isAttending = gamePlan.attending.includes(currentUser);
                    const needsRide = gamePlan.needsRide.includes(currentUser);
                    const offersRide = currentUser in gamePlan.offersRide;

                    gameCard.innerHTML = `
                        <div class="flex flex-col sm:flex-row justify-between sm:items-center mb-4">
                            <div>
                                <p class="font-bold text-red-600">${game.league} - ${game.round}</p>
                                <p class="font-semibold text-gray-800">${new Date(parseDate(game.dateStr)).toLocaleDateString('de-DE', { weekday: 'long', day: '2-digit', month: '2-digit' })}: ${game.opponent}</p>
                                <p class="text-sm text-gray-500">${game.time} @ ${game.location} (${game.home_away})</p>
                            </div>
                            <div class="flex space-x-2 mt-4 sm:mt-0" data-game-id="${gameId}">
                                <button data-action="attend" class="px-3 py-1.5 text-sm rounded-md ${isAttending && !needsRide && !offersRide ? 'bg-green-600 text-white' : 'bg-green-200 text-green-800 hover:bg-green-300'}">Ich komme</button>
                                <button data-action="need" class="px-3 py-1.5 text-sm rounded-md ${needsRide ? 'bg-yellow-500 text-white' : 'bg-yellow-200 text-yellow-800 hover:bg-yellow-300'}">Brauche</button>
                                <button data-action="offer" class="px-3 py-1.5 text-sm rounded-md ${offersRide ? 'bg-blue-600 text-white' : 'bg-blue-200 text-blue-800 hover:bg-blue-300'}">Biete</button>
                            </div>
                        </div>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                            <div>
                                <h4 class="font-semibold border-b pb-1 mb-2">Zuschauer (${gamePlan.attending.length})</h4>
                                <ul id="attending-list-${gameId}" class="space-y-1">${gamePlan.attending.map(p => `<li>${p}</li>`).join('') || '<li class="text-gray-400">Keine</li>'}</ul>
                            </div>
                            <div>
                                <h4 class="font-semibold border-b pb-1 mb-2">Benötigt Mitfahrgelegenheit (${gamePlan.needsRide.length})</h4>
                                <ul id="needs-list-${gameId}" class="space-y-1">${gamePlan.needsRide.map(p => `<li>${p}</li>`).join('') || '<li class="text-gray-400">Keine</li>'}</ul>
                            </div>
                            <div>
                                <h4 class="font-semibold border-b pb-1 mb-2">Bietet Mitfahrgelegenheit (${Object.keys(gamePlan.offersRide).length})</h4>
                                <ul id="offers-list-${gameId}" class="space-y-1">${Object.entries(gamePlan.offersRide).map(([driver, data]) => `<li>${driver} (${data.seats} Plätze)</li>`).join('') || '<li class="text-gray-400">Keine</li>'}</ul>
                            </div>
                        </div>
                    `;
                    container.appendChild(gameCard);
                });
            }

            contentZuschauer.appendChild(container);
        }


        function handleSpectatorAction(e) {
            if (!e.target.dataset.action) return;

            const action = e.target.dataset.action;
            const gameId = e.target.parentElement.dataset.gameId;
            const currentUser = "DemoUser"; // Replace with actual logged-in user logic

            if (!state.spectatorPlan[gameId]) {
                state.spectatorPlan[gameId] = { attending: [], needsRide: [], offersRide: {} };
            }
            const gamePlan = state.spectatorPlan[gameId];

            // Remove user from all lists first to handle toggling
            gamePlan.attending = gamePlan.attending.filter(p => p !== currentUser);
            gamePlan.needsRide = gamePlan.needsRide.filter(p => p !== currentUser);
            delete gamePlan.offersRide[currentUser];

            switch (action) {
                case 'attend':
                    gamePlan.attending.push(currentUser);
                    break;
                case 'need':
                    gamePlan.attending.push(currentUser);
                    gamePlan.needsRide.push(currentUser);
                    break;
                case 'offer':
                    const seats = parseInt(prompt("Wie viele freie Plätze bietest du an?", "3"), 10);
                    if (seats && seats > 0) {
                        gamePlan.attending.push(currentUser);
                        gamePlan.offersRide[currentUser] = { seats: seats };
                    }
                    break;
            }
            saveStateToFirestore();
        }


        function hideLoading() {
            loadingOverlay.style.display = 'none';
            appContainer.classList.remove('hidden');
        }

        // --- ATTACH EVENT LISTENERS ---
        addPlayerBtn.addEventListener('click', addPlayer);
        playerInput.addEventListener('keydown', (e) => e.key === 'Enter' && addPlayer());
        
        addTeamBtn.addEventListener('click', addTeam);
        teamInput.addEventListener('keydown', (e) => e.key === 'Enter' && addTeam());

        tabPlan.addEventListener('click', () => switchTab('plan'));
        tabGames.addEventListener('click', () => switchTab('games'));
        tabStats.addEventListener('click', () => switchTab('stats'));
        tabAvailability.addEventListener('click', () => switchTab('availability'));
        tabZuschauer.addEventListener('click', () => switchTab('zuschauer'));
        
        openSettingsBtn.addEventListener('click', () => settingsModal.classList.remove('hidden'));
        closeSettingsBtn.addEventListener('click', () => settingsModal.classList.add('hidden'));

        closeShareBtn.addEventListener('click', () => shareModal.classList.add('hidden'));
        copyShareTextBtn.addEventListener('click', copyShareText);

        editScheduleBtn.addEventListener('click', openScheduleEditor);
        closeScheduleBtn.addEventListener('click', closeScheduleEditor);
        saveScheduleBtn.addEventListener('click', saveScheduleChanges);
        addScheduleRowBtn.addEventListener('click', addNewScheduleRow);
        scheduleEditorContainer.addEventListener('click', handleScheduleEditorClicks);

        contentZuschauer.addEventListener('click', handleSpectatorAction);

        burgerMenuBtn.addEventListener('click', () => {
            mobileMenu.classList.toggle('hidden');
        });

        document.querySelectorAll('.mobile-tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                const tab = e.target.dataset.tab;
                switchTab(tab);
                mobileMenu.classList.add('hidden');
            });
        });

        // Debounced resize listener to switch between mobile/desktop availability view
        let resizeTimer;
        let lastIsMobileState = window.innerWidth < 768;
        window.addEventListener('resize', () => {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(() => {
                const currentIsMobileState = window.innerWidth < 768;
                // Only re-render if the view mode changes and the availability tab is active
                if (currentIsMobileState !== lastIsMobileState) {
                    lastIsMobileState = currentIsMobileState;
                    if (!contentAvailability.classList.contains('hidden')) {
                        renderAvailabilityTab();
                    }
                }
            }, 250);
        });

        // --- AUTHENTICATION & STARTUP ---
        async function main() {
            try {
                if (typeof __initial_auth_token !== 'undefined' && __initial_auth_token) {
                    await signInWithCustomToken(auth, __initial_auth_token);
                } else {
                    await signInAnonymously(auth);
                }
                userId = auth.currentUser?.uid;
                if(userId) {
                    listenToConfigChanges();
                    listenToStateChanges();
                } else {
                    console.error("Authentication failed. App cannot start.");
                    hideLoading();
                }
            } catch (error) {
                console.error("Firebase Auth Error:", error);
                hideLoading();
            }
        }

        main();

    </script>
</body>
</html>

