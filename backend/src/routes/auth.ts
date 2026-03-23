import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool } from '../db/database';
import { authMiddleware, AuthRequest } from '../middleware/auth';

const router = Router();

// Register
router.post('/register', async (req: Request, res: Response) => {
  const { username, email, password } = req.body;
  if (!username || !email || !password) {
    res.status(400).json({ error: 'Tous les champs sont requis' });
    return;
  }
  try {
    const passwordHash = await bcrypt.hash(password, 12);
    const result = await pool.query(
      'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email',
      [username, email, passwordHash]
    );
    const user = result.rows[0];
    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET || 'secret', { expiresIn: '7d' });
    res.status(201).json({ token, user: { id: user.id, username: user.username, email: user.email } });
  } catch (err: unknown) {
    const error = err as { code?: string };
    if (error.code === '23505') {
      res.status(409).json({ error: 'Nom d\'utilisateur ou email déjà utilisé' });
    } else {
      res.status(500).json({ error: 'Erreur serveur' });
    }
  }
});

// Login
router.post('/login', async (req: Request, res: Response) => {
  const { email, password } = req.body;
  if (!email || !password) {
    res.status(400).json({ error: 'Email et mot de passe requis' });
    return;
  }
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    const user = result.rows[0];
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      res.status(401).json({ error: 'Identifiants incorrects' });
      return;
    }
    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET || 'secret', { expiresIn: '7d' });
    res.json({ token, user: { id: user.id, username: user.username, email: user.email } });
  } catch {
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Get current user + last session
router.get('/me', authMiddleware, async (req: AuthRequest, res: Response) => {
  try {
    const userResult = await pool.query(
      'SELECT id, username, email, created_at FROM users WHERE id = $1',
      [req.userId]
    );
    const lastSession = await pool.query(
      `SELECT *, ROUND((distance_km / (duration_minutes / 60.0))::numeric, 2) AS speed_kmh
       FROM sessions WHERE user_id = $1 ORDER BY session_date DESC LIMIT 1`,
      [req.userId]
    );
    res.json({
      user: userResult.rows[0],
      lastSession: lastSession.rows[0] || null
    });
  } catch {
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

export default router;
