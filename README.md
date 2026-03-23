# 🏃 SportLog — Suivi de séances sportives

Application full-stack de suivi de performances sportives.
**Stack :** Vue 3 + TypeScript | Node.js + Express + TypeScript | PostgreSQL

---

## 📁 Structure du projet

```
sport-tracker/
├── backend/               # API REST Node.js + TypeScript
│   ├── src/
│   │   ├── db/database.ts     # Connexion PostgreSQL + schéma
│   │   ├── middleware/auth.ts  # Middleware JWT
│   │   ├── routes/
│   │   │   ├── auth.ts        # /api/auth (login, register, me)
│   │   │   └── sessions.ts    # /api/sessions (CRUD + stats)
│   │   └── index.ts           # Entrée serveur Express
│   └── .env.example
│
├── frontend/              # App Vue 3 + TypeScript
│   ├── src/
│   │   ├── api/client.ts      # Axios avec intercepteurs JWT
│   │   ├── router/index.ts    # Vue Router (4 routes)
│   │   ├── stores/
│   │   │   ├── auth.ts        # Pinia : authentification
│   │   │   └── sessions.ts    # Pinia : séances
│   │   ├── types/index.ts     # Types TypeScript partagés
│   │   ├── views/
│   │   │   ├── HomeView.vue   # Connexion / Dernière séance
│   │   │   ├── RecordView.vue # Enregistrement de séance
│   │   │   ├── HistoryView.vue# Historique filtrable
│   │   │   └── StatsView.vue  # Graphiques Chart.js
│   │   ├── App.vue            # Layout + navigation
│   │   └── style.css          # Système de design global
│   └── index.html
│
└── docker-compose.yml     # Lancement en un clic
```

---

## 🚀 Lancement rapide (Docker recommandé)

### Prérequis
- Docker & Docker Compose installés

### Démarrage
```bash
git clone <repo>
cd sport-tracker
docker-compose up --build
```

Accès :
- **Frontend :** http://localhost:5173
- **Backend :** http://localhost:3001
- **PostgreSQL :** localhost:5432

---

## 🛠 Installation manuelle (sans Docker)

### 1. PostgreSQL
Créer la base de données :
```sql
CREATE DATABASE sport_tracker;
```

### 2. Backend
```bash
cd backend
cp .env.example .env
# Éditer .env avec vos paramètres PostgreSQL et JWT_SECRET

npm install
npm run dev
```

Le serveur démarre sur `http://localhost:3001`
Les tables sont créées automatiquement au démarrage.

### 3. Frontend
```bash
cd frontend
npm install
npm run dev
```

L'app démarre sur `http://localhost:5173`

---

## 🔌 API Endpoints

### Authentification
| Méthode | Route | Description |
|---------|-------|-------------|
| POST | `/api/auth/register` | Créer un compte |
| POST | `/api/auth/login` | Se connecter |
| GET  | `/api/auth/me` | Profil + dernière séance |

### Séances (JWT requis)
| Méthode | Route | Description |
|---------|-------|-------------|
| GET  | `/api/sessions` | Toutes les séances (`?sport=cycling\|running`) |
| POST | `/api/sessions` | Créer une séance |
| DELETE | `/api/sessions/:id` | Supprimer une séance |
| GET  | `/api/sessions/stats` | Données pour graphiques (`?sport=...`) |

### Corps de requête — Créer une séance
```json
{
  "sport": "cycling",
  "duration_minutes": 60,
  "distance_km": 25.5,
  "session_date": "2024-06-01T10:00:00Z",
  "notes": "Belle sortie matinale"
}
```

---

## 📊 Fonctionnalités

### Onglet 1 — Accueil / Connexion
- Formulaire de connexion et d'inscription
- Une fois connecté : affichage de la **dernière séance** (sport, durée, distance, vitesse)

### Onglet 2 — Enregistrer
- Sélection du sport (🚴 Vélo / 🏃 Course à pied)
- Saisie de durée (minutes) et distance (km)
- **Vitesse calculée en temps réel** (distance / durée)
- Champ date/heure et notes optionnelles

### Onglet 3 — Historique
- Liste de toutes les séances avec **filtre par sport**
- Affichage : sport, date, durée, distance, **vitesse calculée**
- Suppression avec confirmation

### Onglet 4 — Statistiques
- **3 courbes** : durée, distance, vitesse dans le temps
- Filtre par sport (avec couleurs distinctes)
- Vue multi-sports avec courbes superposées

---

## 🎨 Design

- Thème sombre (dark mode natif)
- Police d'affichage : **Bebas Neue** (titres), **DM Sans** (corps)
- Couleurs sport : 🟠 Orange pour le vélo, 🔵 Cyan pour la course
- Graphiques avec Chart.js + vue-chartjs

---

## ➕ Ajouter un nouveau sport

1. **Backend** (`src/db/database.ts`) : ajouter la valeur dans le `CHECK` de la colonne `sport`
2. **Frontend** (`src/types/index.ts`) : ajouter le sport au type `Sport`
3. **Frontend** (`src/views/RecordView.vue`) : ajouter dans le tableau `sports`
4. **Frontend** (`src/style.css`) : ajouter les variables CSS de couleur
