var crypto = require('crypto');
var SIGNING_SECRET = "${signing_secret}";

// Admin CIDR allowlist injected by Terraform. Only /32 (IPv4) and /128 (IPv6)
// are supported here; broader CIDRs are still enforced by WAF as a second layer.
var ADMIN_CIDRS = ${jsonencode(admin_ips)}.concat(${jsonencode(admin_ips_v6)});

// Normalize IPv6 groups to remove leading zeros so viewer.ip always compares
// equal to the stored CIDR regardless of zero-padding representation.
function normalizeIP(ip) {
  if (ip.indexOf(':') === -1) return ip;
  return ip.split(':').map(function(g) {
    return g ? parseInt(g, 16).toString(16) : '';
  }).join(':');
}

function isAdminAllowed(viewerIP) {
  var ip = normalizeIP(viewerIP.toLowerCase());
  for (var i = 0; i < ADMIN_CIDRS.length; i++) {
    var host = normalizeIP(ADMIN_CIDRS[i].split('/')[0].toLowerCase());
    if (ip === host) return true;
  }
  return false;
}

function toStdBase64(s) {
  var r = s.replace(/-/g, "+").replace(/_/g, "/");
  var pad = (4 - r.length % 4) % 4;
  for (var i = 0; i < pad; i++) r += "=";
  return r;
}

// crypto.timingSafeEqual is not available in CloudFront Functions JS 2.0.
// HMAC comparison is itself timing-safe because the expected value is secret
// and derived from the same key, so early-exit string comparison leaks nothing
// about the secret key, only about whether the token was self-consistent.
function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function isValidRoomToken(token) {
  if (!token) return false;

  var dotIndex = token.lastIndexOf('.');
  if (dotIndex === -1) return false;

  var payloadB64 = token.slice(0, dotIndex);
  var sigB64     = token.slice(dotIndex + 1);

  try {
    var expected = crypto.createHmac('sha256', SIGNING_SECRET)
      .update(payloadB64)
      .digest('base64url');

    if (!safeEqual(sigB64, expected)) return false;

    var payload = JSON.parse(atob(toStdBase64(payloadB64)));
    return Math.floor(Date.now() / 1000) <= payload.exp;
  } catch (_) {
    return false;
  }
}

// Not Authorization: the Lambda origin is OAC-signed (SigV4), and OAC's
// "always" signing behavior overwrites the Authorization header with its own
// signature before the request reaches Lambda, discarding anything the
// client sent there. A custom header name avoids that collision entirely.
function roomTokenHeader(request) {
  var header = request.headers['x-room-token'];
  return header && header.value;
}

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Block /, /admin*, and the rest of /api/* (everything except /api/session,
  // which is gated by room token below) for IPs not in the allowlist. This is
  // the sole edge gate for /api/sign-room (admin-only) when WAF is disabled.
  // WAF's block-protected-paths rule duplicates it as defense in depth when on.
  if (uri === '/' || uri.startsWith('/admin') || (uri.startsWith('/api') && uri !== '/api/session')) {
    if (!isAdminAllowed(event.viewer.ip)) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
    return request;
  }

  // /speaker (page load) carries the room token in the URL, unavoidable for a
  // shared link. /api/session (STS credential vending, a JS fetch) carries it
  // in an X-Room-Token header instead, so it never lands in access logs or
  // browser history. Both are reachable by attendee IPs, not just admins; the
  // token is the access control here. The Lambda revalidates /api/session's
  // token independently; never trust the edge alone.
  if (uri === '/speaker') {
    var pageToken = request.querystring.token && request.querystring.token.value;
    if (!isValidRoomToken(pageToken)) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
    return request;
  }

  if (uri === '/api/session') {
    if (!isValidRoomToken(roomTokenHeader(request))) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
    return request;
  }

  return request;
}
