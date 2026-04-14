import dotenv from 'dotenv';
dotenv.config({ override: true });

import express from 'express';
import cors from 'cors';
import articlesRouter from './routes/articles';
import feedsRouter from './routes/feeds';
import intelRouter from './routes/intel';
import onboardingRouter from './routes/onboarding';
import { startFeedRefreshJob } from './jobs/feedRefreshJob';
import { startDiscoveryJob } from './jobs/discoveryJob';
import { startCentroidJob } from './jobs/centroidJob';
import { startProfileRefreshJob } from './jobs/profileRefreshJob';

const app = express();
const PORT = parseInt(process.env.PORT ?? '3001', 10);

// -------------------------------------------------------
// Middleware
// -------------------------------------------------------
app.use(cors({
  origin: '*',  // restrict in production via environment variable
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
app.use(express.json({ limit: '1mb' }));

// -------------------------------------------------------
// Health check
// -------------------------------------------------------
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
  });
});

// -------------------------------------------------------
// Routes
// -------------------------------------------------------
app.use('/api/articles', articlesRouter);
app.use('/api/feeds', feedsRouter);
app.use('/api/onboarding', onboardingRouter);
app.use('/api', intelRouter);

// -------------------------------------------------------
// 404 handler
// -------------------------------------------------------
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// -------------------------------------------------------
// Error handler
// -------------------------------------------------------
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('[server] Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// -------------------------------------------------------
// Start server + cron jobs
// -------------------------------------------------------
app.listen(PORT, () => {
  console.log(`[server] Signal backend running on port ${PORT}`);
  console.log(`[server] Environment: ${process.env.NODE_ENV ?? 'development'}`);

  // Start cron jobs
  startFeedRefreshJob();      // every 2 hours + immediate on start
  startDiscoveryJob();        // every 6 hours
  startCentroidJob();         // daily at 3am
  startProfileRefreshJob();   // every 12 hours fallback + on-demand
});

export default app;
