import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../api/client'
import type { Session, NewSession, Sport } from '../types'

export const useSessionsStore = defineStore('sessions', () => {
  const sessions = ref<Session[]>([])
  const statsData = ref<Session[]>([])
  const loading = ref(false)

  async function fetchSessions(sport?: Sport) {
    loading.value = true
    try {
      const params = sport ? { sport } : {}
      const { data } = await api.get('/sessions', { params })
      sessions.value = data
    } finally {
      loading.value = false
    }
  }

  async function fetchStats(sport?: Sport) {
    loading.value = true
    try {
      const params = sport ? { sport } : {}
      const { data } = await api.get('/sessions/stats', { params })
      statsData.value = data
    } finally {
      loading.value = false
    }
  }

  async function addSession(session: NewSession) {
    const { data } = await api.post('/sessions', session)
    sessions.value.unshift(data)
    return data
  }

  async function deleteSession(id: number) {
    await api.delete(`/sessions/${id}`)
    sessions.value = sessions.value.filter(s => s.id !== id)
  }

  return { sessions, statsData, loading, fetchSessions, fetchStats, addSession, deleteSession }
})
