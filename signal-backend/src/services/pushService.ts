import apn from '@parse/node-apn';
import { supabaseAdmin } from '../db/supabase';

// Lazy-init APNs provider
let _provider: apn.Provider | null = null;

function getProvider(): apn.Provider | null {
  if (_provider) return _provider;

  const key = process.env.APNS_KEY;
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;

  if (!key || !keyId || !teamId) {
    console.warn('[pushService] APNS_KEY, APNS_KEY_ID, or APNS_TEAM_ID not set — push disabled');
    return null;
  }

  _provider = new apn.Provider({
    token: {
      key,
      keyId,
      teamId,
    },
    production: process.env.NODE_ENV === 'production',
  });

  return _provider;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

export async function sendPushNotification(payload: PushPayload): Promise<void> {
  const provider = getProvider();
  if (!provider) return;

  const bundleId = process.env.APNS_BUNDLE_ID;
  if (!bundleId) {
    console.warn('[pushService] APNS_BUNDLE_ID not set — push disabled');
    return;
  }

  const { data: tokens } = await supabaseAdmin
    .from('push_tokens')
    .select('token');

  if (!tokens?.length) {
    console.log('[pushService] No registered push tokens');
    return;
  }

  const notification = new apn.Notification();
  notification.alert = { title: payload.title, body: payload.body };
  notification.sound = 'default';
  notification.topic = bundleId;
  if (payload.data) {
    notification.payload = payload.data;
  }

  const deviceTokens = tokens.map(t => t.token);
  const result = await provider.send(notification, deviceTokens);

  if (result.failed.length > 0) {
    console.warn(`[pushService] ${result.failed.length} push(es) failed`);
    // Remove invalid tokens
    for (const failure of result.failed) {
      if (failure.response?.reason === 'BadDeviceToken' || failure.response?.reason === 'Unregistered') {
        await supabaseAdmin
          .from('push_tokens')
          .delete()
          .eq('token', failure.device);
      }
    }
  }

  console.log(`[pushService] Sent to ${result.sent.length}/${deviceTokens.length} devices`);
}
