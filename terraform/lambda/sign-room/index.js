import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';

const SIGNING_SECRET = process.env.SIGNING_SECRET;
const SPEAKER_SESSION_ROLE_ARN = process.env.SPEAKER_SESSION_ROLE_ARN;

const stsClient = new STSClient({});

const jsonResponse = (statusCode, payload, extraHeaders = {}) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', ...extraHeaders },
  body: JSON.stringify(payload),
});

const forbidden = () => jsonResponse(403, { error: 'Forbidden' });

// Same HMAC room token verified at the CloudFront Function edge for /speaker
// and /api/session. The Lambda revalidates because the edge check alone
// cannot be trusted as the sole gate on credential-vending.
function verifyToken(token) {
  if (!token) return null;
  const dotIndex = token.lastIndexOf('.');
  if (dotIndex === -1) return null;

  const payloadB64 = token.slice(0, dotIndex);
  const sigB64 = token.slice(dotIndex + 1);
  const expected = createHmac('sha256', SIGNING_SECRET).update(payloadB64).digest('base64url');

  const sigBuf = Buffer.from(sigB64);
  const expectedBuf = Buffer.from(expected);
  if (sigBuf.length !== expectedBuf.length || !timingSafeEqual(sigBuf, expectedBuf)) return null;

  let payload;
  try {
    payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (typeof payload.exp !== 'number' || Math.floor(Date.now() / 1000) > payload.exp) return null;
  return payload;
}

// Not Authorization: OAC's "always" signing behavior overwrites that header
// with CloudFront's own SigV4 signature before the request reaches here,
// discarding anything the client sent. A custom header avoids the collision.
function roomTokenHeader(event) {
  return event.headers?.['x-room-token'] ?? null;
}

async function handleSession(event) {
  const payload = verifyToken(roomTokenHeader(event));
  if (!payload) return forbidden();

  // STS enforces a 900s floor on AssumeRole sessions. Reject rather than
  // clamp up: a granted credential must never outlive the room token's own
  // exp, or a refresh near the boundary would extend access past it.
  const remainingSeconds = payload.exp - Math.floor(Date.now() / 1000);
  if (remainingSeconds < 900) return forbidden();
  const durationSeconds = Math.min(3600, remainingSeconds);

  const sessionPolicy = JSON.stringify({
    Version: '2012-10-17',
    Statement: [
      {
        Effect: 'Allow',
        Action: ['transcribe:StartStreamTranscription', 'transcribe:StartStreamTranscriptionWebSocket'],
        Resource: '*',
      },
      { Effect: 'Allow', Action: 'translate:TranslateText', Resource: '*' },
    ],
  });

  try {
    const { Credentials } = await stsClient.send(new AssumeRoleCommand({
      RoleArn: SPEAKER_SESSION_ROLE_ARN,
      RoleSessionName: payload.roomId,
      DurationSeconds: durationSeconds,
      Policy: sessionPolicy,
    }));

    return jsonResponse(200, {
      accessKeyId: Credentials.AccessKeyId,
      secretAccessKey: Credentials.SecretAccessKey,
      sessionToken: Credentials.SessionToken,
      expiration: Credentials.Expiration,
    }, { 'Cache-Control': 'no-store' });
  } catch {
    return jsonResponse(502, { error: 'Failed to vend session credentials' });
  }
}

async function handleSignRoom(event) {
  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  const { src, tgt, room } = body;
  if (!src || !tgt || !room) {
    return jsonResponse(400, { error: 'Missing required fields: src, tgt, room' });
  }

  const roomId = randomUUID();
  const payload = Buffer.from(JSON.stringify({
    roomId,
    src,
    tgt,
    room,
    exp: Math.floor(Date.now() / 1000) + 28800, // 8h
  })).toString('base64url');

  const sig = createHmac('sha256', SIGNING_SECRET).update(payload).digest('base64url');

  return jsonResponse(200, { token: `${payload}.${sig}`, roomId });
}

// AWS_IAM Function URL auth type + OAC means only SigV4-signed requests from
// this CloudFront distribution reach here at all: no app-level shared
// secret needed to prove the caller is CloudFront.
export async function handler(event) {
  const method = event.requestContext?.http?.method;
  const path = event.requestContext?.http?.path;

  if (method === 'GET' && path === '/api/session') {
    return handleSession(event);
  }
  return handleSignRoom(event);
}
