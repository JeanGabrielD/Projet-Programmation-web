<template>
  <div class="record-view fade-in">
    <div class="page-header">
      <h1 class="page-title">Nouvelle séance</h1>
      <p class="page-sub">Enregistre ta performance du jour</p>
    </div>

    <div class="record-layout">
      <!-- Sport selector -->
      <div class="sport-selector">
        <button
          v-for="s in sports"
          :key="s.value"
          :class="['sport-btn', { active: form.sport === s.value }, `sport-btn-${s.value}`]"
          @click="form.sport = s.value"
          type="button"
        >
          <span class="sport-emoji">{{ s.icon }}</span>
          <span class="sport-name">{{ s.label }}</span>
          <span class="sport-check" v-if="form.sport === s.value">✓</span>
        </button>
      </div>

      <!-- Form -->
      <form class="record-form card" @submit.prevent="submit">
        <div class="form-grid">
          <div class="form-group">
            <label class="form-label">Durée (minutes)</label>
            <input
              v-model.number="form.duration_minutes"
              type="number"
              min="1"
              max="1440"
              step="0.5"
              placeholder="ex. 45"
              required
            />
          </div>
          <div class="form-group">
            <label class="form-label">Distance (km)</label>
            <input
              v-model.number="form.distance_km"
              type="number"
              min="0.1"
              max="1000"
              step="0.01"
              placeholder="ex. 10.5"
              required
            />
          </div>
          <div class="form-group">
            <label class="form-label">Date & heure</label>
            <input
              v-model="form.session_date"
              type="datetime-local"
              :max="maxDate"
            />
          </div>
          <div class="form-group">
            <label class="form-label">Vitesse calculée</label>
            <div class="speed-display">
              <span class="speed-value">{{ calculatedSpeed }}</span>
              <span class="speed-unit">km/h</span>
            </div>
          </div>
        </div>

        <div class="form-group">
          <label class="form-label">Notes (optionnel)</label>
          <textarea v-model="form.notes" rows="3" placeholder="Conditions météo, sensations, parcours..."></textarea>
        </div>

        <div class="form-actions">
          <button type="submit" class="btn btn-primary btn-submit" :disabled="loading || !canSubmit">
            <span v-if="loading" class="btn-spinner"></span>
            <span v-else>💾</span>
            Enregistrer la séance
          </button>
        </div>
      </form>
    </div>

    <!-- Toast -->
    <Transition name="toast">
      <div v-if="toast" :class="['toast', toast.type]">{{ toast.message }}</div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { useSessionsStore } from '../stores/sessions'
import { useAuthStore } from '../stores/auth'
import type { Sport } from '../types'

const sessions = useSessionsStore()
const auth = useAuthStore()
const loading = ref(false)
const toast = ref<{ message: string; type: 'success' | 'error' } | null>(null)

const sports = [
  { value: 'cycling' as Sport, label: 'Vélo', icon: '🚴' },
  { value: 'running' as Sport, label: 'Course à pied', icon: '🏃' },
]

const now = new Date()
const defaultDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
const maxDate = defaultDate

const form = ref({
  sport: 'cycling' as Sport,
  duration_minutes: null as number | null,
  distance_km: null as number | null,
  session_date: defaultDate,
  notes: '',
})

const calculatedSpeed = computed(() => {
  if (!form.value.duration_minutes || !form.value.distance_km) return '—'
  const speed = form.value.distance_km / (form.value.duration_minutes / 60)
  return speed.toFixed(1)
})

const canSubmit = computed(() =>
  form.value.duration_minutes && form.value.duration_minutes > 0 &&
  form.value.distance_km && form.value.distance_km > 0
)

function showToast(message: string, type: 'success' | 'error') {
  toast.value = { message, type }
  setTimeout(() => { toast.value = null }, 3500)
}

async function submit() {
  if (!canSubmit.value) return
  loading.value = true
  try {
    await sessions.addSession({
      sport: form.value.sport,
      duration_minutes: form.value.duration_minutes!,
      distance_km: form.value.distance_km!,
      session_date: new Date(form.value.session_date).toISOString(),
      notes: form.value.notes || undefined,
    })
    await auth.fetchMe()
    showToast('✅ Séance enregistrée avec succès !', 'success')
    form.value = {
      sport: 'cycling',
      duration_minutes: null,
      distance_km: null,
      session_date: defaultDate,
      notes: '',
    }
  } catch {
    showToast('❌ Erreur lors de l\'enregistrement', 'error')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.record-view { max-width: 700px; margin: 0 auto; }
.page-header { margin-bottom: 2rem; }
.page-title { font-family: var(--font-display); font-size: 2rem; letter-spacing: 0.02em; margin-bottom: 0.25rem; }
.page-sub { color: var(--text-muted); }

.record-layout { display: flex; flex-direction: column; gap: 1.5rem; }

.sport-selector { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.sport-btn {
  background: var(--bg-card);
  border: 2px solid var(--border);
  border-radius: var(--radius);
  color: var(--text-muted);
  cursor: pointer;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.5rem;
  padding: 1.75rem 1rem;
  position: relative;
  transition: all 0.2s;
}
.sport-btn:hover { border-color: var(--text-dim); color: var(--text); }
.sport-btn.sport-btn-cycling.active { border-color: var(--cycling); background: var(--cycling-glow); color: var(--cycling); }
.sport-btn.sport-btn-running.active { border-color: var(--running); background: var(--running-glow); color: var(--running); }
.sport-emoji { font-size: 2rem; }
.sport-name { font-weight: 500; font-size: 0.95rem; }
.sport-check {
  position: absolute;
  top: 0.6rem; right: 0.75rem;
  font-size: 0.75rem;
}

.record-form { display: flex; flex-direction: column; gap: 1.25rem; }
.form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.25rem; }

.speed-display {
  background: var(--bg-input);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 0.75rem 1rem;
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
}
.speed-value { font-family: var(--font-display); font-size: 1.4rem; color: var(--accent); letter-spacing: 0.05em; }
.speed-unit { color: var(--text-muted); font-size: 0.85rem; }

.form-actions { margin-top: 0.5rem; }
.btn-submit { width: 100%; justify-content: center; }

.btn-spinner {
  width: 14px; height: 14px;
  border: 2px solid rgba(255,255,255,0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
}

textarea { resize: vertical; min-height: 80px; }

.toast-enter-active, .toast-leave-active { transition: all 0.3s ease; }
.toast-enter-from, .toast-leave-to { opacity: 0; transform: translateY(10px); }

@media (max-width: 500px) {
  .form-grid { grid-template-columns: 1fr; }
}
</style>
