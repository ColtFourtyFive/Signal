import cron from 'node-cron';
import { runDiscovery } from '../services/discoveryService';

export { runDiscovery };

// Schedule: every 6 hours
export function startDiscoveryJob(): void {
  cron.schedule('0 */6 * * *', () => {
    runDiscovery().catch(err =>
      console.error('[discoveryJob] Scheduled run failed:', err)
    );
  });

  console.log('[discoveryJob] Scheduled (every 6 hours)');
}
