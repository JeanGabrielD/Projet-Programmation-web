<template>
  <div id="app-layout">
    <header class="app-header">
      <div class="header-inner">
        <div class="logo">
          <span class="logo-icon">⚡</span>
          <span class="logo-text">SPORTLOG</span>
        </div>

        <nav v-if="auth.isAuthenticated" class="nav-tabs">
          <RouterLink to="/" class="nav-tab">
            <span class="tab-icon">🏠</span>
            <span class="tab-label">Accueil</span>
          </RouterLink>
          <RouterLink to="/record" class="nav-tab">
            <span class="tab-icon">＋</span>
            <span class="tab-label">Enregistrer</span>
          </RouterLink>
          <RouterLink to="/history" class="nav-tab">
            <span class="tab-icon">📋</span>
            <span class="tab-label">Historique</span>
          </RouterLink>
          <RouterLink to="/stats" class="nav-tab">
            <span class="tab-icon">📈</span>
            <span class="tab-label">Statistiques</span>
          </RouterLink>
        </nav>

        <div class="header-right">
          <template v-if="auth.isAuthenticated">
            <span class="user-name">{{ auth.user?.username }}</span>
            <button class="btn btn-ghost btn-sm" @click="auth.logout(); $router.push('/')">
              Déconnexion
            </button>
          </template>
        </div>
      </div>
    </header>

    <main class="main-content">
      <RouterView v-slot="{ Component }">
        <Transition name="view" mode="out-in">
          <component :is="Component" />
        </Transition>
      </RouterView>
    </main>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { RouterView, RouterLink } from 'vue-router'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()

onMounted(async () => {
  if (auth.isAuthenticated) {
    await auth.fetchMe()
  }
})
</script>

<style scoped>
.app-header {
  position: sticky;
  top: 0;
  z-index: 100;
  background: rgba(10, 10, 15, 0.85);
  backdrop-filter: blur(16px);
  border-bottom: 1px solid var(--border);
}

.header-inner {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1.5rem;
  height: 64px;
  display: flex;
  align-items: center;
  gap: 2rem;
}

.logo {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  text-decoration: none;
  flex-shrink: 0;
}
.logo-icon { font-size: 1.2rem; }
.logo-text {
  font-family: var(--font-display);
  font-size: 1.4rem;
  letter-spacing: 0.1em;
  color: var(--accent);
}

.nav-tabs {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  flex: 1;
  justify-content: center;
}

.nav-tab {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 1rem;
  border-radius: var(--radius-sm);
  text-decoration: none;
  color: var(--text-muted);
  font-size: 0.875rem;
  font-weight: 500;
  transition: all 0.2s;
}
.nav-tab:hover { color: var(--text); background: var(--bg-input); }
.nav-tab.router-link-active {
  color: var(--accent);
  background: var(--accent-glow);
}
.tab-icon { font-size: 0.9rem; }

.header-right {
  display: flex;
  align-items: center;
  gap: 1rem;
  flex-shrink: 0;
}
.user-name {
  color: var(--text-muted);
  font-size: 0.875rem;
}

.btn-sm { padding: 0.4rem 0.9rem; font-size: 0.82rem; }

.main-content {
  flex: 1;
  max-width: 1200px;
  margin: 0 auto;
  width: 100%;
  padding: 2rem 1.5rem;
}

.view-enter-active, .view-leave-active { transition: all 0.2s ease; }
.view-enter-from { opacity: 0; transform: translateY(6px); }
.view-leave-to { opacity: 0; transform: translateY(-4px); }
</style>
