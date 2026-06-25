import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';

const SIGNING_SECRET = process.env.SIGNING_SECRET;
const CF_ORIGIN_SECRET = process.env.CF_ORIGIN_SECRET;

export async function handler(event) {
  // Reject requests that did not come through CloudFront (missing or wrong shared secret).
  // CloudFront overrides any viewer-supplied X-CF-Secret with the configured origin header
  // value, so this header cannot be forged by callers who bypass CloudFront.
  const incoming = event.headers?.['x-cf-secret'] ?? '';
  if (
    !CF_ORIGIN_SECRET ||
    incoming.length !== CF_ORIGIN_SECRET.length ||
    !timingSafeEqual(Buffer.from(incoming), Buffer.from(CF_ORIGIN_SECRET))
  ) {
    return { statusCode: 403, body: JSON.stringify({ error: 'Forbidden' }) };
  }

  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
  }

  const { src, tgt, room } = body;
  if (!src || !tgt || !room) {
    return {
      statusCode: 400,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Missing required fields: src, tgt, room' }),
    };
  }

  const roomId = randomUUID();
  const payload = Buffer.from(JSON.stringify({
    roomId,
    src,
    tgt,
    room,
    exp: Math.floor(Date.now() / 1000) + 28800, // 8h
  })).toString('base64url');

  const sig = createHmac('sha256', SIGNING_SECRET)
    .update(payload)
    .digest('base64url');

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: `${payload}.${sig}`, roomId }),
  };
}
