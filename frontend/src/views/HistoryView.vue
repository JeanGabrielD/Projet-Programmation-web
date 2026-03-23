<template>
  <div class="history-view fade-in">
    <div class="page-header">
      <div>
        <h1 class="page-title">Historique</h1>
        <p class="page-sub">{{ sessions.sessions.length }} séance{{ sessions.sessions.length > 1 ? 's' : '' }} enregistrée{{ sessions.sessions.length > 1 ? 's' : '' }}</p>
      </div>
      <div class="filter-tabs">
        <button
          v-for="f in filters"
          :key="f.value"
          :class="['filter-tab', { active: activeSport === f.value }]"
          @click="setFilter(f.value)"
        >
          {{ f.icon }} {{ f.label }}
        </button>
      </div>
    </div>

    <div v-if="sessions.loading" class="loading-state">
      <div class="spinner"></div>
    </div>

    <div v-else-if="sessions.sessions.length === 0" class="empty-state card">
      <div class="empty-icon">🏅</div>
      <p>Aucune séance pour ce filtre.</p>
    </div>

    <div v-else class="sessions-list">
      <div
        v-for="session in sessions.sessions"
        :key="session.id"
        class="session-row card fade-in"
      >
        <div class="session-left">
          <span :class="['badge', `badge-${session.sport}`]">
            {{ sportIcon(session.sport) }} {{ sportLabel(session.sport) }}
          </span>
          <div class="session-date">{{ formatDate(session.session_date) }}</div>
        </div>

        <div class="session-metrics">
          <div class="s-metric">
            <span class="s-val">{{ formatDuration(session.duration_minutes) }}</span>
            <span class="s-lbl">Durée</span>
          </div>
          <div class="s-metric">
            <span class="s-val">{{ session.distance_km }} <small>km</small></span>
            <span class="s-lbl">Distance</span>
          </div>
          <div class="s-metric">
            <span class="s-val speed-val">{{ session.speed_kmh }} <small>km/h</small></span>
            <span class="s-lbl">Vitesse</span>
          </div>
        </div>

        <div class="session-right">
          <p v-if="session.notes" class="session-notes">{{ session.notes }}</p>
          <button
            class="btn btn-danger"
            @click="confirmDelete(session.id)"
            :disabled="deletingId === session.id"
          >
            {{ deletingId === session.id ? '...' : '🗑' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Confirm modal -->
    <Transition name="modal">
      <div v-if="deleteId !== null" class="modal-overlay" @click.self="deleteId = null">
        <div class="modal-box card">
          <h3>Supprimer la séance ?</h3>
          <p>Cette action est irréversible.</p>
          <div class="modal-actions">
            <button class="btn btn-ghost" @click="deleteId = null">Annuler</button>
            <button class="btn btn-primary" style="background:var(--danger);box-shadow:none" @click="doDelete">Supprimer</button>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useSessionsStore } from '../stores/sessions'
import type { Sport } from '../types'

const sessions = useSessionsStore()
const activeSport = ref<Sport | undefined>(undefined)
const deleteId = ref<number | null>(null)
const deletingId = ref<number | null>(null)

const filters = [
  { value: undefined, label: 'Tous', icon: '🏅' },
  { value: 'cycling' as Sport, label: 'Vélo', icon: '🚴' },
  { value: 'running' as Sport, label: 'Course', icon: '🏃' },
]

onMounted(() => sessions.fetchSessions())

async function setFilter(sport: Sport | undefined) {
  activeSport.value = sport
  await sessions.fetchSessions(sport)
}

function confirmDelete(id: number) {
  deleteId.value = id
}

async function doDelete() {
  if (deleteId.value === null) return
  deletingId.value = deleteId.value
  deleteId.value = null
  try {
    await sessions.deleteSession(deletingId.value)
  } finally {
    deletingId.value = null
  }
}

function sportLabel(sport: Sport) { return sport === 'cycling' ? 'Vélo' : 'Course' }
function sportIcon(sport: Sport) { return sport === 'cycling' ? '🚴' : '🏃' }
function formatDate(d: string) {
  return new Date(d).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}
function formatDuration(min: number) {
  const h = Math.floor(min / 60)
  const m = Math.round(min % 60)
  return h > 0 ? `${h}h${String(m).padStart(2,'0')}` : `${m} min`
}
</script>

<style scoped>
.history-view { max-width: 900px; margin: 0 auto; }
.page-header { display: flex; align-items: flex-start; justify-content: space-between; flex-wrap: wrap; gap: 1rem; margin-bottom: 2rem; }
.page-title { font-family: var(--font-display); font-size: 2rem; letter-spacing: 0.02em; margin-bottom: 0.25rem; }
.page-sub { color: var(--text-muted); }

.filter-tabs { display: flex; gap: 0.4rem; }
.filter-tab {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 999px;
  color: var(--text-muted);
  cursor: pointer;
  font-family: var(--font-body);
  font-size: 0.82rem;
  font-weight: 500;
  padding: 0.4rem 1rem;
  transition: all 0.2s;
}
.filter-tab:hover { border-color: var(--text-muted); color: var(--text); }
.filter-tab.active { background: var(--accent-glow); border-color: var(--accent); color: var(--accent); }

.sessions-list { display: flex; flex-direction: column; gap: 0.75rem; }

.session-row {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  padding: 1.1rem 1.5rem;
  transition: border-color 0.2s;
}
.session-row:hover { border-color: var(--text-dim); }

.session-left { min-width: 140px; display: flex; flex-direction: column; gap: 0.4rem; }
.session-date { color: var(--text-muted); font-size: 0.78rem; }

.session-metrics { display: flex; gap: 2rem; flex: 1; }
.s-metric { display: flex; flex-direction: column; gap: 0.15rem; }
.s-val { font-family: var(--font-display); font-size: 1.3rem; letter-spacing: 0.04em; line-height: 1.1; }
.s-val small { font-size: 0.75rem; color: var(--text-muted); font-family: var(--font-body); }
.speed-val { color: var(--accent); }
.s-lbl { font-size: 0.7rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.08em; }

.session-right { display: flex; align-items: center; gap: 1rem; margin-left: auto; }
.session-notes { color: var(--text-muted); font-size: 0.82rem; font-style: italic; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.loading-state { display: flex; justify-content: center; padding: 4rem; }
.empty-state { text-align: center; padding: 3rem; color: var(--text-muted); }
.empty-icon { font-size: 2.5rem; margin-bottom: 0.75rem; }

/* Modal */
.modal-overlay {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.7);
  display: flex; align-items: center; justify-content: center;
  z-index: 200;
  backdrop-filter: blur(4px);
}
.modal-box { max-width: 360px; width: 90%; text-align: center; padding: 2rem; }
.modal-box h3 { font-size: 1.1rem; margin-bottom: 0.5rem; }
.modal-box p { color: var(--text-muted); font-size: 0.9rem; margin-bottom: 1.5rem; }
.modal-actions { display: flex; gap: 0.75rem; justify-content: center; }
.modal-enter-active, .modal-leave-active { transition: all 0.2s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }

@media (max-width: 600px) {
  .session-row { flex-wrap: wrap; }
  .session-metrics { gap: 1rem; }
}
</style>
