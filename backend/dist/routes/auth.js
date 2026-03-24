"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const database_1 = require("../db/database");
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
// Register
router.post('/register', async (req, res) => {
    const { username, email, password } = req.body;
    if (!username || !email || !password) {
        res.status(400).json({ error: 'Tous les champs sont requis' });
        return;
    }
    try {
        const passwordHash = await bcryptjs_1.default.hash(password, 12);
        const result = await database_1.pool.query('INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email', [username, email, passwordHash]);
        const user = result.rows[0];
        const token = jsonwebtoken_1.default.sign({ userId: user.id }, process.env.JWT_SECRET || 'secret', { expiresIn: '7d' });
        res.status(201).json({ token, user: { id: user.id, username: user.username, email: user.email } });
    }
    catch (err) {
        const error = err;
        if (error.code === '23505') {
            res.status(409).json({ error: 'Nom d\'utilisateur ou email déjà utilisé' });
        }
        else {
            res.status(500).json({ error: 'Erreur serveur' });
        }
    }
});
// Login
router.post('/login', async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) {
        res.status(400).json({ error: 'Email et mot de passe requis' });
        return;
    }
    try {
        const result = await database_1.pool.query('SELECT * FROM users WHERE email = $1', [email]);
        const user = result.rows[0];
        if (!user || !(await bcryptjs_1.default.compare(password, user.password_hash))) {
            res.status(401).json({ error: 'Identifiants incorrects' });
            return;
        }
        const token = jsonwebtoken_1.default.sign({ userId: user.id }, process.env.JWT_SECRET || 'secret', { expiresIn: '7d' });
        res.json({ token, user: { id: user.id, username: user.username, email: user.email } });
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
// Get current user + last session
router.get('/me', auth_1.authMiddleware, async (req, res) => {
    try {
        const userResult = await database_1.pool.query('SELECT id, username, email, created_at FROM users WHERE id = $1', [req.userId]);
        const lastSession = await database_1.pool.query(`SELECT *, ROUND((distance_km / (duration_minutes / 60.0))::numeric, 2) AS speed_kmh
       FROM sessions WHERE user_id = $1 ORDER BY session_date DESC LIMIT 1`, [req.userId]);
        res.json({
            user: userResult.rows[0],
            lastSession: lastSession.rows[0] || null
        });
    }
    catch {
        res.status(500).json({ error: 'Erreur serveur' });
    }
});
exports.default = router;
