import { createClient } from 'npm:@supabase/supabase-js@2.49.0';
import { JWT } from 'npm:google-auth-library@9.15.1';

type NotificationType = 'sosAlert' | 'safeZoneEnter' | 'safeZoneExit' | 'sharingPaused';

type NotificationPayload = {
  type: NotificationType;
  circle_id: string;
  zone_id?: string;
  zone_name?: string;
  actor_user_id?: string;
  latitude?: number;
  longitude?: number;
};

type RecipientSetting = {
  user_id: string;
  push_enabled: boolean;
  notify_sos: boolean;
  notify_safe_zone_enter: boolean;
  notify_safe_zone_exit: boolean;
  notify_sharing_paused: boolean;
};

type RecipientToken = {
  user_id: string;
  token: string;
  platform: string;
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed.' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace(/^Bearer\s+/i, '') ?? null;
  if (!token) {
    return jsonResponse({ error: 'Authorization header is required.' }, 401);
  }

  const body = (await req.json().catch(() => null)) as Partial<NotificationPayload> | null;
  if (!body || !body.type || !body.circle_id) {
    return jsonResponse({ error: 'Missing required fields: type, circle_id.' }, 400);
  }

  if (!isNotificationType(body.type)) {
    return jsonResponse({ error: 'Invalid notification type.' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!supabaseUrl || !serviceRole || !serviceAccountJson) {
    return jsonResponse({ error: 'Server configuration missing.' }, 500);
  }

  let serviceAccount: { project_id: string; client_email: string; private_key: string };
  try {
    serviceAccount = JSON.parse(serviceAccountJson);
  } catch (_) {
    return jsonResponse({ error: 'Invalid Firebase service account configuration.' }, 500);
  }

  const supabase = createClient(supabaseUrl, serviceRole);

  const { data: authenticated, error: userError } = await supabase.auth.getUser(token);
  if (userError || !authenticated.user) {
    return jsonResponse({ error: 'Unauthorized.' }, 401);
  }

  const actorUserId = authenticated.user.id;
  const actorName = authenticated.user.user_metadata?.name || actorUserId;

  const { data: membership, error: membershipError } = await supabase
    .from('circle_members')
    .select('id')
    .eq('circle_id', body.circle_id)
    .eq('user_id', actorUserId)
    .eq('is_accepted', true)
    .maybeSingle();

  if (membershipError) {
    return jsonResponse({ error: membershipError.message }, 400);
  }

  if (!membership) {
    return jsonResponse({ error: 'User is not an accepted member of the circle.' }, 403);
  }

  const { data: members, error: memberError } = await supabase
    .from('circle_members')
    .select('user_id')
    .eq('circle_id', body.circle_id)
    .eq('is_accepted', true)
    .neq('user_id', actorUserId);

  if (memberError) {
    return jsonResponse({ error: memberError.message }, 400);
  }

  if (!members || members.length === 0) {
    return jsonResponse({ sent: 0, skipped: 0, message: 'No other circle members to notify.' });
  }

  const recipientIds = members.map((member) => member.user_id).filter(Boolean);
  const [settingsRows, tokenRows, actorDisplay] = await Promise.all([
    supabase
      .from('notification_settings')
      .select('user_id, push_enabled, notify_sos, notify_safe_zone_enter, notify_safe_zone_exit, notify_sharing_paused')
      .in('user_id', recipientIds),
    supabase
      .from('notification_tokens')
      .select('user_id, token, platform')
      .in('user_id', recipientIds)
      .eq('is_active', true),
    supabase
      .from('users')
      .select('display_name')
      .eq('id', actorUserId)
      .single(),
  ]);

  if (settingsRows.error) {
    return jsonResponse({ error: settingsRows.error.message }, 400);
  }

  if (tokenRows.error) {
    return jsonResponse({ error: tokenRows.error.message }, 400);
  }

  const safeActorName = actorDisplay.data?.display_name || actorName;

  const settingsByUser = new Map<string, RecipientSetting>();
  for (const setting of settingsRows.data ?? []) {
    settingsByUser.set(setting.user_id, setting as RecipientSetting);
  }

  const activeTokenRows: RecipientToken[] = (tokenRows.data ?? []) as RecipientToken[];
  const { title, body: messageBody, eventTypeLabel } = getNotificationMessage(body.type, {
    actorName: safeActorName,
    zoneName: body.zone_name,
  });

  const tokenPayload = [] as string[];
  let skipped = 0;

  for (const row of activeTokenRows) {
    const setting = settingsByUser.get(row.user_id) ??
      ({
        user_id: row.user_id,
        push_enabled: true,
        notify_sos: true,
        notify_safe_zone_enter: true,
        notify_safe_zone_exit: true,
        notify_sharing_paused: true,
      } as RecipientSetting);

    if (!isNotificationEnabled(setting, body.type)) {
      skipped++;
      continue;
    }

    tokenPayload.push(row.token);
  }

  let sent = 0;
  const failedTokens: string[] = [];

  if (tokenPayload.length > 0) {
    const accessToken = await getFirebaseAccessToken(serviceAccount);
    const fcmEndpoint =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const pushMessage = {
      title,
      body: messageBody,
      data: {
        type: body.type,
        circle_id: body.circle_id,
        actor_user_id: actorUserId,
        actor_name: safeActorName,
        zone_id: body.zone_id ?? '',
        zone_name: body.zone_name ?? '',
        event_type_label: eventTypeLabel,
        ...(body.latitude != null ? { latitude: body.latitude.toString() } : {}),
        ...(body.longitude != null ? { longitude: body.longitude.toString() } : {}),
      },
    };

    await Promise.all(
      tokenPayload.map(async (token) => {
        const res = await fetch(fcmEndpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: pushMessage.title,
                body: pushMessage.body,
              },
              data: pushMessage.data,
              android: { priority: 'HIGH' },
              apns: { headers: { 'apns-priority': '10' } },
            },
          }),
        });

        if (!res.ok) {
          failedTokens.push(token);
          return;
        }

        sent += 1;
      }),
    );
  }

  return jsonResponse({
    success: true,
    sent,
    skipped,
    event_type: body.type,
    failed_tokens: failedTokens,
  });
});

async function getFirebaseAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const client = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const credentials = await client.authorize();
  if (!credentials.access_token) throw new Error('Firebase access token was not issued.');
  return credentials.access_token;
}

function isNotificationType(value: string): value is NotificationType {
  return value === 'sosAlert' || value === 'safeZoneEnter' || value === 'safeZoneExit' || value === 'sharingPaused';
}

function isNotificationEnabled(setting: RecipientSetting, type: NotificationType): boolean {
  if (!setting.push_enabled) return false;

  switch (type) {
    case 'sosAlert':
      return setting.notify_sos;
    case 'safeZoneEnter':
      return setting.notify_safe_zone_enter;
    case 'safeZoneExit':
      return setting.notify_safe_zone_exit;
    case 'sharingPaused':
      return setting.notify_sharing_paused;
  }
}

function getNotificationMessage(
  type: NotificationType,
  context: { actorName: string; zoneName?: string },
): {
  title: string;
  body: string;
  eventTypeLabel: string;
} {
  const actorName = context.actorName;
  switch (type) {
    case 'sosAlert':
      return {
        title: 'SOS Alert',
        body: `${actorName} has sent an SOS alert. Open the app to view details.`,
        eventTypeLabel: 'SOS alert',
      };
    case 'safeZoneEnter':
      return {
        title: 'Safe zone update',
        body: `${actorName} entered ${context.zoneName ?? 'a safe zone'}.`,
        eventTypeLabel: 'entered safe zone',
      };
    case 'safeZoneExit':
      return {
        title: 'Safe zone update',
        body: `${actorName} exited ${context.zoneName ?? 'a safe zone'}.`,
        eventTypeLabel: 'exited safe zone',
      };
    case 'sharingPaused':
      return {
        title: 'Sharing status',
        body: `${actorName} paused live sharing.`,
        eventTypeLabel: 'sharing paused',
      };
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...CORS,
    },
  });
}
