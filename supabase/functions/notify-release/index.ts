import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function base64Url(value: string | Uint8Array): string {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function firebaseAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const pem = serviceAccount.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const tokenJson = await tokenResponse.json();
  if (!tokenResponse.ok) throw new Error(`Google OAuth failed: ${JSON.stringify(tokenJson)}`);
  return tokenJson.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const projectId = Deno.env.get('FCM_PROJECT_ID')!;
    const serviceAccount = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')!);
    const authorization = req.headers.get('Authorization');
    if (!authorization) return Response.json({ error: 'Sign in required' }, { status: 401, headers: corsHeaders });

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return Response.json({ error: 'Invalid session' }, { status: 401, headers: corsHeaders });

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: adminRow } = await adminClient
      .from('app_admins').select('user_id').eq('user_id', userData.user.id).maybeSingle();
    if (!adminRow) return Response.json({ error: 'Administrator permission required' }, { status: 403, headers: corsHeaders });

    const body = await req.json();
    const releaseId = String(body.release_id || '');
    if (!releaseId) return Response.json({ error: 'release_id is required' }, { status: 400, headers: corsHeaders });

    const { data: release, error: releaseError } = await adminClient
      .from('app_releases')
      .select('id,version_name,version_code,release_notes,apk_url')
      .eq('id', releaseId).eq('status', 'published').single();
    if (releaseError || !release) return Response.json({ error: 'Published release not found' }, { status: 404, headers: corsHeaders });

    const { data: devices, error: devicesError } = await adminClient
      .from('user_devices').select('id,fcm_token').eq('enabled', true);
    if (devicesError) throw devicesError;
    if (!devices?.length) {
      return Response.json({ sent: 0, message: 'No registered devices yet. Configure Firebase and device registration.' }, { headers: corsHeaders });
    }

    const accessToken = await firebaseAccessToken(serviceAccount);
    let sent = 0;
    let failed = 0;
    for (let i = 0; i < devices.length; i += 50) {
      const batch = devices.slice(i, i + 50);
      const results = await Promise.all(batch.map(async (device) => {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              notification: {
                title: 'Evora update available',
                body: `Version ${release.version_name} is ready to install.`,
              },
              data: {
                type: 'app_update',
                release_id: release.id,
                version_code: String(release.version_code),
                apk_url: release.apk_url,
              },
              android: { priority: 'high' },
            },
          }),
        });
        if (response.ok) return true;
        const detail = await response.text();
        if (detail.includes('UNREGISTERED') || detail.includes('NOT_FOUND')) {
          await adminClient.from('user_devices').update({ enabled: false }).eq('id', device.id);
        }
        return false;
      }));
      sent += results.filter(Boolean).length;
      failed += results.length - results.filter(Boolean).length;
    }
    return Response.json({ sent, failed, total: devices.length }, { headers: corsHeaders });
  } catch (error) {
    console.error(error);
    return Response.json({ error: error instanceof Error ? error.message : 'Notification failed' }, { status: 500, headers: corsHeaders });
  }
});
