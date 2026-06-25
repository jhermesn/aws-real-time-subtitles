var crypto = require('crypto');
var SIGNING_SECRET = "${signing_secret}";

function toStdBase64(s) {
  var r = s.replace(/-/g, "+").replace(/_/g, "/");
  var pad = (4 - r.length % 4) % 4;
  for (var i = 0; i < pad; i++) r += "=";
  return r;
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

    if (sigB64.length !== expected.length ||
        !crypto.timingSafeEqual(Buffer.from(sigB64), Buffer.from(expected))) {
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
