export type Sport = 'cycling' | 'running'

export interface User {
  id: number
  username: string
  email: string
  created_at?: string
}

export interface Session {
  id: number
  user_id: number
  sport: Sport
  duration_minutes: number
  distance_km: number
  speed_kmh: number
  session_date: string
  notes?: string
  created_at: string
}

export interface AuthState {
  token: string | null
  user: User | null
}

export interface NewSession {
  sport: Sport
  duration_minutes: number
  distance_km: number
  session_date: string
  notes?: string
}
