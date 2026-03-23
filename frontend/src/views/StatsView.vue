<template>
  <div class="stats-view fade-in">
    <div class="page-header">
      <div>
        <h1 class="page-title">Statistiques</h1>
        <p class="page-sub">Ta progression dans le temps</p>
      </div>
      <div class="filter-tabs">
        <button
          v-for="f in filters"
          :key="String(f.value)"
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

    <div v-else-if="sessions.statsData.length < 2" class="empty-state card">
      <div class="empty-icon">📈</div>
      <p>Enregistre au moins 2 séances pour voir tes statistiques.</p>
    </div>

    <div v-else class="charts-grid">
      <div class="chart-card card">
        <div class="chart-header">
          <h3 class="chart-title">⏱ Durée</h3>
          <span class="chart-unit">minutes</span>
        </div>
        <div class="chart-wrap">
          <Line :data="durationChartData" :options="chartOptions('Durée (min)')" />
        </div>
      </div>

      <div class="chart-card card">
        <div class="chart-header">
          <h3 class="chart-title">📍 Distance</h3>
          <span class="chart-unit">kilomètres</span>
        </div>
        <div class="chart-wrap">
          <Line :data="distanceChartData" :options="chartOptions('Distance (km)')" />
        </div>
      </div>

      <div class="chart-card card full-width">
        <div class="chart-header">
          <h3 class="chart-title">⚡ Vitesse moyenne</h3>
          <span class="chart-unit">km/h</span>
        </div>
        <div class="chart-wrap">
          <Line :data="speedChartData" :options="chartOptions('Vitesse (km/h)')" />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale, LinearScale, PointElement, LineElement,
  Title, Tooltip, Legend, Filler
} from 'chart.js'
import { useSessionsStore } from '../stores/sessions'
import type { Sport, Session } from '../types'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler)

const sessions = useSessionsStore()
const activeSport = ref<Sport | undefined>(undefined)

const filters = [
  { value: undefined, label: 'Tous', icon: '🏅' },
  { value: 'cycling' as Sport, label: 'Vélo', icon: '🚴' },
  { value: 'running' as Sport, label: 'Course', icon: '🏃' },
]

onMounted(() => sessions.fetchStats())

async function setFilter(sport: Sport | undefined) {
  activeSport.value = sport
  await sessions.fetchStats(sport)
}

function formatLabel(d: string) {
  return new Date(d).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' })
}

const labels = computed(() => sessions.statsData.map(s => formatLabel(s.session_date)))

function getColor(sport: Session['sport'] | undefined) {
  if (sport === 'cycling') return { line: '#f97316', fill: 'rgba(249,115,22,0.08)' }
  if (sport === 'running') return { line: '#22d3ee', fill: 'rgba(34,211,238,0.08)' }
  return { line: '#6c63ff', fill: 'rgba(108,99,255,0.08)' }
}

function buildDataset(label: string, data: number[], sport: Sport | undefined) {
  const c = getColor(sport)
  return {
    label,
    data,
    borderColor: c.line,
    backgroundColor: c.fill,
    pointBackgroundColor: c.line,
    pointRadius: 4,
    pointHoverRadius: 6,
    borderWidth: 2,
    tension: 0.3,
    fill: true,
  }
}

// Multi-sport: group by sport when no filter
function buildMultiDatasets(field: keyof Session) {
  if (activeSport.value) {
    const data = sessions.statsData.map(s => Number(s[field]))
    return [buildDataset(activeSport.value === 'cycling' ? 'Vélo' : 'Course', data, activeSport.value)]
  }
  const cycling = sessions.statsData.filter(s => s.sport === 'cycling')
  const running = sessions.statsData.filter(s => s.sport === 'running')
  const datasets = []
  if (cycling.length) datasets.push(buildDataset('Vélo 🚴', cycling.map(s => Number(s[field])), 'cycling'))
  if (running.length) datasets.push(buildDataset('Course 🏃', running.map(s => Number(s[field])), 'running'))
  return datasets
}

const durationChartData = computed(() => ({
  labels: labels.value,
  datasets: buildMultiDatasets('duration_minutes'),
}))

const distanceChartData = computed(() => ({
  labels: labels.value,
  datasets: buildMultiDatasets('distance_km'),
}))

const speedChartData = computed(() => ({
  labels: labels.value,
  datasets: buildMultiDatasets('speed_kmh'),
}))

function chartOptions(yLabel: string) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    interaction: { mode: 'index' as const, intersect: false },
    plugins: {
      legend: {
        labels: {
          color: '#6b6b80',
          font: { family: 'DM Sans', size: 12 },
          boxWidth: 12,
          usePointStyle: true,
        },
      },
      tooltip: {
        backgroundColor: '#111118',
        borderColor: '#2a2a3a',
        borderWidth: 1,
        titleColor: '#e8e8f0',
        bodyColor: '#6b6b80',
        padding: 12,
        titleFont: { family: 'DM Sans', weight: '600' as const },
        bodyFont: { family: 'DM Sans' },
      },
    },
    scales: {
      x: {
        grid: { color: '#1a1a24' },
        ticks: { color: '#6b6b80', font: { family: 'DM Sans', size: 11 } },
      },
      y: {
        grid: { color: '#1a1a24' },
        ticks: { color: '#6b6b80', font: { family: 'DM Sans', size: 11 } },
        title: {
          display: true,
          text: yLabel,
          color: '#3a3a50',
          font: { family: 'DM Sans', size: 11 },
        },
      },
    },
  }
}
</script>

<style scoped>
.stats-view { max-width: 1000px; margin: 0 auto; }
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

.charts-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.25rem;
}
.full-width { grid-column: 1 / -1; }

.chart-card { display: flex; flex-direction: column; gap: 1rem; }
.chart-header { display: flex; align-items: center; justify-content: space-between; }
.chart-title { font-size: 0.95rem; font-weight: 600; }
.chart-unit { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.08em; }
.chart-wrap { height: 220px; position: relative; }

.loading-state { display: flex; justify-content: center; padding: 4rem; }
.empty-state { text-align: center; padding: 3rem; color: var(--text-muted); }
.empty-icon { font-size: 2.5rem; margin-bottom: 0.75rem; }

@media (max-width: 640px) {
  .charts-grid { grid-template-columns: 1fr; }
  .full-width { grid-column: 1; }
}
</style>
