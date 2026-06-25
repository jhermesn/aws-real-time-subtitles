var crypto = require('crypto');
var SIGNING_SECRET = "${signing_secret}";

// Admin CIDR allowlist injected by Terraform. Only /32 (IPv4) and /128 (IPv6)
// are supported here — broader CIDRs are still enforced by WAF as a second layer.
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
// about the secret key — only about whether the token was self-consistent.
function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function handler(event) {
  var request = event.request;
  var uri = request.uri;

  // Block / and /admin* for IPs not in the allowlist. WAF also enforces /admin
  // and /api at the HTTP layer, but cannot intercept client-side React Router
  // navigations that start from GET /, so we enforce here at the edge too.
  if (uri === '/' || uri.startsWith('/admin')) {
    if (!isAdminAllowed(event.viewer.ip)) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
    return request;
  }

  if (!uri.startsWith('/speaker')) {
    return request;
  }

  var token = request.querystring.token && request.querystring.token.value;
  if (!token) {
    return { statusCode: 403, statusDescription: 'Forbidden' };
  }

  var dotIndex = token.lastIndexOf('.');
  if (dotIndex === -1) {
    return { statusCode: 403, statusDescription: 'Forbidden' };
  }

  var payloadB64 = token.slice(0, dotIndex);
  var sigB64     = token.slice(dotIndex + 1);

  try {
    var expected = crypto.createHmac('sha256', SIGNING_SECRET)
      .update(payloadB64)
      .digest('base64url');

    if (!safeEqual(sigB64, expected)) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }

    var payload = JSON.parse(atob(toStdBase64(payloadB64)));

    if (Math.floor(Date.now() / 1000) > payload.exp) {
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
  } catch (_) {
    return { statusCode: 403, statusDescription: 'Forbidden' };
  }

  return request;
}
