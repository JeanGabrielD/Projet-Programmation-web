"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const database_1 = require("../db/database");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
router.use(auth_1.authMiddleware);
// Create session
router.post('/', async (req, res) => {
    const { sport, duration_minutes, distance_km, session_date, notes } = req.body;
    if (!sport || !duration_minutes || !distance_km) {
        res.status(400).json({ error: 'Sport, durée et distance sont requis' });
        return;
    }
    if (!['cycling', 'running'].includes(sport)) {
        res.status(400).json({ error: 'Sport invalide' });
        return;
    }
    try {
        const result = await database_1.pool.query(`INSERT INTO sessions (user_id, sport, duration_minutes, distance_km, session_date, notes)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *, ROUND((distance_km / (duration_minutes / 60.0))::numeric, 2) AS speed_kmh`, [req.userId, sport, duration_minutes, distance_km, session_date || new Date(), notes || null]);
        res.status(201).json(result.rows[0]);
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
// Get all sessions (optionally filtered by sport)
router.get('/', async (req, res) => {
    const { sport } = req.query;
    try {
        let query = `
      SELECT *, ROUND((distance_km / (duration_minutes / 60.0))::numeric, 2) AS speed_kmh
      FROM sessions WHERE user_id = $1
    `;
        const params = [req.userId];
        if (sport && ['cycling', 'running'].includes(sport)) {
            query += ' AND sport = $2';
            params.push(sport);
        }
        query += ' ORDER BY session_date DESC';
        const result = await database_1.pool.query(query, params);
        res.json(result.rows);
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
// Delete session
router.delete('/:id', async (req, res) => {
    try {
        const result = await database_1.pool.query('DELETE FROM sessions WHERE id = $1 AND user_id = $2 RETURNING id', [req.params.id, req.userId]);
        if (result.rowCount === 0) {
            res.status(404).json({ error: 'Séance introuvable' });
            return;
        }
        res.json({ message: 'Séance supprimée' });
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
// Stats per sport (for charts)
router.get('/stats', async (req, res) => {
    const { sport } = req.query;
    try {
        let query = `
      SELECT
        sport,
        session_date,
        duration_minutes,
        distance_km,
        ROUND((distance_km / (duration_minutes / 60.0))::numeric, 2) AS speed_kmh
      FROM sessions
      WHERE user_id = $1
    `;
        const params = [req.userId];
        if (sport && ['cycling', 'running'].includes(sport)) {
            query += ' AND sport = $2';
            params.push(sport);
        }
        query += ' ORDER BY session_date ASC';
        const result = await database_1.pool.query(query, params);
        res.json(result.rows);
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
exports.default = router;
