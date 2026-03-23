<template>
  <div class="home-view">
    <!-- Authenticated: show last session -->
    <template v-if="auth.isAuthenticated">
      <div class="welcome-section fade-in">
        <div class="welcome-header">
          <div>
            <h1 class="page-title">Bonjour, <span class="accent">{{ auth.user?.username }}</span> 👋</h1>
            <p class="page-sub">Prêt pour une nouvelle séance ?</p>
          </div>
          <RouterLink to="/record" class="btn btn-primary">
            <span>＋</span> Nouvelle séance
          </RouterLink>
        </div>

        <div v-if="auth.lastSession" class="last-session-card card">
          <div class="last-label">DERNIÈRE SÉANCE</div>
          <div class="last-header">
            <span :class="['badge', `badge-${auth.lastSession.sport}`]">
              {{ sportIcon(auth.lastSession.sport) }} {{ sportLabel(auth.lastSession.sport) }}
            </span>
            <span class="last-date">{{ formatDate(auth.lastSession.session_date) }}</span>
          </div>
          <div class="last-metrics">
            <div class="metric">
              <span class="metric-value">{{ formatDuration(auth.lastSession.duration_minutes) }}</span>
              <span class="metric-label">Durée</span>
            </div>
            <div class="metric-sep"></div>
            <div class="metric">
              <span class="metric-value">{{ auth.lastSession.distance_km }} <small>km</small></span>
              <span class="metric-label">Distance</span>
            </div>
            <div class="metric-sep"></div>
            <div class="metric">
              <span class="metric-value">{{ auth.lastSession.speed_kmh }} <small>km/h</small></span>
              <span class="metric-label">Vitesse moy.</span>
            </div>
          </div>
          <p v-if="auth.lastSession.notes" class="last-notes">{{ auth.lastSession.notes }}</p>
        </div>

        <div v-else class="empty-state card">
          <div class="empty-icon">🏃</div>
          <p>Aucune séance enregistrée pour le moment.</p>
          <RouterLink to="/record" class="btn btn-primary" style="margin-top:1rem">Commencer maintenant</RouterLink>
        </div>
      </div>
    </template>

    <!-- Unauthenticated: Login/Register -->
    <template v-else>
      <div class="auth-page fade-in">
        <div class="auth-hero">
          <div class="hero-badge">SPORTLOG</div>
          <h1 class="hero-title">Tracke<br><span class="accent">tes performances.</span></h1>
          <p class="hero-sub">Enregistre tes séances de vélo et de course, visualise ta progression et repousse tes limites.</p>
        </div>

        <div class="auth-card card">
          <div class="auth-tabs">
            <button
              :class="['auth-tab', { active: mode === 'login' }]"
              @click="mode = 'login'"
            >Connexion</button>
            <button
              :class="['auth-tab', { active: mode === 'register' }]"
              @click="mode = 'register'"
            >Inscription</button>
          </div>

          <form class="auth-form" @submit.prevent="submit">
            <div v-if="mode === 'register'" class="form-group">
              <label class="form-label">Nom d'utilisateur</label>
              <input v-model="form.username" type="text" placeholder="ex. johndoe" required />
            </div>
            <div class="form-group">
              <label class="form-label">Email</label>
              <input v-model="form.email" type="email" placeholder="vous@example.com" required />
            </div>
            <div class="form-group">
              <label class="form-label">Mot de passe</label>
              <input v-model="form.password" type="password" placeholder="••••••••" required minlength="6" />
            </div>

            <p v-if="error" class="form-error">{{ error }}</p>

            <button type="submit" class="btn btn-primary btn-full" :disabled="loading">
              <span v-if="loading" class="btn-spinner"></span>
              {{ mode === 'login' ? 'Se connecter' : 'Créer mon compte' }}
            </button>
          </form>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import type { Sport } from '../types'

const auth = useAuthStore()
const mode = ref<'login' | 'register'>('login')
const loading = ref(false)
const error = ref('')
const form = ref({ username: '', email: '', password: '' })

async function submit() {
  error.value = ''
  loading.value = true
  try {
    if (mode.value === 'login') {
      await auth.login(form.value.email, form.value.password)
    } else {
      await auth.register(form.value.username, form.value.email, form.value.password)
    }
    await auth.fetchMe()
  } catch (e: unknown) {
    const err = e as { response?: { data?: { error?: string } } }
    error.value = err.response?.data?.error || 'Une erreur est survenue'
  } finally {
    loading.value = false
  }
}

function sportLabel(sport: Sport) {
  return sport === 'cycling' ? 'Vélo' : 'Course'
}
function sportIcon(sport: Sport) {
  return sport === 'cycling' ? '🚴' : '🏃'
}
function formatDate(d: string) {
  return new Date(d).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
}
function formatDuration(min: number) {
  const h = Math.floor(min / 60)
  const m = Math.round(min % 60)
  return h > 0 ? `${h}h${String(m).padStart(2,'0')}` : `${m} min`
}
</script>

<style scoped>
.home-view { max-width: 800px; margin: 0 auto; }

/* Auth page */
.auth-page { display: grid; grid-template-columns: 1fr 1fr; gap: 4rem; align-items: center; min-height: 70vh; }
.hero-badge {
  display: inline-block;
  font-family: var(--font-display);
  font-size: 0.9rem;
  letter-spacing: 0.3em;
  color: var(--accent);
  border: 1px solid var(--accent);
  border-radius: 999px;
  padding: 0.3rem 1rem;
  margin-bottom: 1.5rem;
}
.hero-title {
  font-family: var(--font-display);
  font-size: clamp(2.5rem, 6vw, 4rem);
  line-height: 1.05;
  letter-spacing: 0.02em;
  margin-bottom: 1.2rem;
}
.accent { color: var(--accent); }
.hero-sub { color: var(--text-muted); line-height: 1.7; font-size: 1rem; }

.auth-card { max-width: 400px; }
.auth-tabs { display: flex; gap: 0; margin-bottom: 1.75rem; border-bottom: 1px solid var(--border); }
.auth-tab {
  background: none;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  font-family: var(--font-body);
  font-size: 0.9rem;
  font-weight: 500;
  padding: 0.6rem 1.25rem;
  position: relative;
  transition: color 0.2s;
}
.auth-tab.active { color: var(--text); }
.auth-tab.active::after {
  content: '';
  position: absolute;
  bottom: -1px; left: 0; right: 0;
  height: 2px;
  background: var(--accent);
  border-radius: 2px 2px 0 0;
}

.auth-form { display: flex; flex-direction: column; gap: 1.1rem; }
.btn-full { width: 100%; justify-content: center; }
.btn-spinner {
  width: 14px; height: 14px;
  border: 2px solid rgba(255,255,255,0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
  flex-shrink: 0;
}

/* Welcome */
.welcome-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  margin-bottom: 2rem;
  gap: 1rem;
  flex-wrap: wrap;
}
.page-title {
  font-family: var(--font-display);
  font-size: 2rem;
  letter-spacing: 0.02em;
  margin-bottom: 0.25rem;
}
.page-sub { color: var(--text-muted); }

.last-session-card { display: flex; flex-direction: column; gap: 1.2rem; }
.last-label { color: var(--text-dim); font-size: 0.7rem; letter-spacing: 0.15em; font-weight: 600; }
.last-header { display: flex; align-items: center; justify-content: space-between; }
.last-date { color: var(--text-muted); font-size: 0.85rem; }

.last-metrics {
  display: flex;
  align-items: center;
  gap: 2rem;
  padding: 1.2rem 0;
  border-top: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
}
.metric { display: flex; flex-direction: column; gap: 0.2rem; }
.metric-value {
  font-family: var(--font-display);
  font-size: 2rem;
  letter-spacing: 0.04em;
  line-height: 1;
}
.metric-value small { font-size: 0.9rem; color: var(--text-muted); font-family: var(--font-body); }
.metric-label { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.08em; }
.metric-sep { width: 1px; height: 40px; background: var(--border); }
.last-notes { color: var(--text-muted); font-style: italic; font-size: 0.9rem; }

.empty-state { text-align: center; padding: 3rem; color: var(--text-muted); }
.empty-icon { font-size: 2.5rem; margin-bottom: 0.75rem; }

@media (max-width: 640px) {
  .auth-page { grid-template-columns: 1fr; gap: 2rem; min-height: auto; }
}
</style>
