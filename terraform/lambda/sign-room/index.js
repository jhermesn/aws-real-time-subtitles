import { createHmac, randomUUID } from 'node:crypto';

const SIGNING_SECRET = process.env.SIGNING_SECRET;

export async function handler(event) {
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
