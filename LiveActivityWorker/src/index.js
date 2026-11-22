// N Link Live Activity backend, as a Cloudflare Worker.
//
// While a charging Live Activity runs, the app registers its APNs device
// token here. A cron trigger sends that device a silent background push
// every few minutes; the app wakes, fetches the car's status from
// Hyundai/Kia itself, and updates the Live Activity. Only the push token,
// the activity type and timestamps are stored: no vehicle or account data.
//
// Routes:
//   POST /wakeup             { pushToken, activityType }  register
//   POST /wakeup/unregister  { pushToken }                unregister
// Cron (every minute): send due wake-up pushes, expire old registrations.

// Minutes between wake-ups per activity type; anything else is rejected.
const WAKEUP_INTERVALS = { debug: 1, charging: 5 };
// Registrations end after 8 hours even if the app never unregisters.
const MAX_AGE_MS = 8 * 60 * 60 * 1000;
// APNs accepts a provider token for up to an hour; refresh before that.
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000;
// Device tokens are hex; allow some room for future length changes.
const PUSH_TOKEN_PATTERN = /^[0-9a-fA-F]{32,200}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== 'POST') {
      return json({ error: 'Not found' }, 404);
    }
    try {
      if (url.pathname === '/wakeup') return await register(request, env);
      if (url.pathname === '/wakeup/unregister') return await unregister(request, env);
      return json({ error: 'Not found' }, 404);
    } catch (error) {
      console.error('Request failed:', error);
      return json({ error: 'Internal error' }, 500);
    }
  },

  async scheduled(_event, env, ctx) {
    ctx.waitUntil(sendWakeUps(env));
  },
};

async function register(request, env) {
  const body = await readJSON(request);
  const pushToken = body?.pushToken;
  if (!isValidToken(pushToken)) {
    return json({ error: 'Missing or invalid pushToken' }, 400);
  }
  // Legacy clients omit the type; they only ever registered charging.
  const activityType = body.activityType || 'charging';
  if (!(activityType in WAKEUP_INTERVALS)) {
    return json({ error: `Unsupported activityType: ${activityType}`, supported: Object.keys(WAKEUP_INTERVALS) }, 400);
  }

  await env.DB.prepare(
    `INSERT INTO registrations (push_token, activity_type, start_time, last_push_time, wakeup_count)
     VALUES (?1, ?2, ?3, 0, 0)
     ON CONFLICT (push_token) DO UPDATE SET
       activity_type = excluded.activity_type,
       start_time = excluded.start_time,
       last_push_time = 0,
       wakeup_count = 0`
  ).bind(pushToken, activityType, Date.now()).run();

  console.log(`Registered ${pushToken.slice(0, 8)} (${activityType})`);
  return json({ success: true });
}

async function unregister(request, env) {
  const body = await readJSON(request);
  const pushToken = body?.pushToken;
  if (!isValidToken(pushToken)) {
    return json({ error: 'Missing or invalid pushToken' }, 400);
  }
  await env.DB.prepare('DELETE FROM registrations WHERE push_token = ?1').bind(pushToken).run();
  console.log(`Unregistered ${pushToken.slice(0, 8)}`);
  return json({ success: true });
}

async function sendWakeUps(env) {
  const now = Date.now();

  const expired = await env.DB.prepare('DELETE FROM registrations WHERE start_time < ?1')
    .bind(now - MAX_AGE_MS).run();

  const { results } = await env.DB.prepare('SELECT * FROM registrations').all();
  const due = results.filter((row) => {
    const intervalMs = intervalMsFor(row.activity_type);
    return !row.last_push_time || now - row.last_push_time >= intervalMs;
  });

  let sent = 0;
  if (due.length > 0) {
    const providerToken = await getProviderToken(env);
    await Promise.all(due.map(async (row) => {
      const short = row.push_token.slice(0, 8);
      try {
        const result = await sendBackgroundPush(env, providerToken, row.push_token, now, intervalMsFor(row.activity_type));
        if (result.ok) {
          sent++;
          await env.DB.prepare(
            'UPDATE registrations SET last_push_time = ?1, wakeup_count = wakeup_count + 1 WHERE push_token = ?2'
          ).bind(now, row.push_token).run();
          return;
        }
        console.error(`APNs rejected ${short}: ${result.status} ${result.reason}`);
        if (result.status === 410 || ['Unregistered', 'BadDeviceToken', 'ExpiredToken'].includes(result.reason)) {
          await env.DB.prepare('DELETE FROM registrations WHERE push_token = ?1').bind(row.push_token).run();
          console.log(`Removed invalid token ${short}`);
        }
      } catch (error) {
        console.error(`Push to ${short} failed:`, error);
      }
    }));
  }

  console.log(`${results.length} active · ${due.length} due · sent ${sent} · expired ${expired.meta?.changes ?? 0}`);
}

// MARK: - APNs

function intervalMsFor(activityType) {
  return (WAKEUP_INTERVALS[activityType] ?? 5) * 60 * 1000;
}

async function sendBackgroundPush(env, providerToken, pushToken, now, intervalMs) {
  // Keep the push alive until just before the next one is due. A 1-minute
  // expiry meant APNs discarded the wakeup whenever the phone was asleep or
  // off the network for that minute, on top of iOS deferring low-priority
  // background pushes — so most charging wakeups never arrived. iOS keeps
  // only the newest background push per app, so they can't pile up.
  const ttlSeconds = Math.max(60, intervalMs / 1000 - 10);
  const response = await fetch(`https://${env.APNS_HOST}/3/device/${pushToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${providerToken}`,
      'apns-topic': env.APNS_TOPIC,
      'apns-push-type': 'background',
      'apns-priority': '5', // Background pushes must use priority 5.
      'apns-expiration': String(Math.floor(now / 1000) + ttlSeconds),
      'content-type': 'application/json',
    },
    body: JSON.stringify({ aps: { 'content-available': 1 }, liveActivityWakeup: true }),
  });
  if (response.ok) return { ok: true, status: response.status };
  let reason = '';
  try {
    reason = (await response.json()).reason ?? '';
  } catch {
    reason = await response.text().catch(() => '');
  }
  return { ok: false, status: response.status, reason };
}

let cachedToken = null;

// ES256-signed JWT for APNs token-based auth, reused for up to 50 minutes.
async function getProviderToken(env) {
  const now = Date.now();
  if (cachedToken && now - cachedToken.issuedAt < PROVIDER_TOKEN_TTL_MS) {
    return cachedToken.value;
  }
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    throw new Error('APNs credentials are not configured');
  }
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(env.APNS_KEY),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }));
  const signingInput = `${header}.${claims}`;
  // WebCrypto returns the raw r||s signature JWS expects.
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );
  const value = `${signingInput}.${base64url(signature)}`;
  cachedToken = { value, issuedAt: now };
  return value;
}

// MARK: - Helpers

function pemToArrayBuffer(pem) {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function isValidToken(token) {
  return typeof token === 'string' && PUSH_TOKEN_PATTERN.test(token);
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
