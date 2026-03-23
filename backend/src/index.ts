import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { initDatabase } from './db/database';
import authRoutes from './routes/auth';
import sessionRoutes from './routes/sessions';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

// En prod, FRONTEND_URL peut contenir plusieurs origines séparées par des virgules
// ex: https://d1234abcd.cloudfront.net,https://mondomaine.com
const allowedOrigins = (process.env.FRONTEND_URL || 'http://localhost:5173').split(',');
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) callback(null, true);
    else callback(new Error('CORS bloque cette origine : ' + origin));
  },
  credentials: true,
}));

app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/sessions', sessionRoutes);

app.get('/api/health', (_, res) => res.json({ status: 'ok' }));

async function start() {
  await initDatabase();
  app.listen(PORT, () => {
    console.log('Backend running on port ' + PORT);
  });
}

start().catch(console.error);
