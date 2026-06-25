var crypto = require('crypto');
var SIGNING_SECRET = "${signing_secret}";

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

  if (!request.uri.startsWith("/speaker")) {
    return request;
  }

  var token = request.querystring.token && request.querystring.token.value;
  if (!token) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  var dotIndex = token.lastIndexOf(".");
  if (dotIndex === -1) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  var payloadB64 = token.slice(0, dotIndex);
  var sigB64     = token.slice(dotIndex + 1);

  try {
    var expected = crypto.createHmac('sha256', SIGNING_SECRET)
      .update(payloadB64)
      .digest('base64url');

    if (!safeEqual(sigB64, expected)) {
      return { statusCode: 403, statusDescription: "Forbidden" };
    }

    var payload = JSON.parse(atob(toStdBase64(payloadB64)));

    if (Math.floor(Date.now() / 1000) > payload.exp) {
      return { statusCode: 403, statusDescription: "Forbidden" };
    }
  } catch (_) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  return request;
}
