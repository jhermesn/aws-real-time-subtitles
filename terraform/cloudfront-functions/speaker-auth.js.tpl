// Injected by Terraform at deploy time
var SIGNING_SECRET = "${signing_secret}";

async function handler(event) {
  var request = event.request;

  if (!request.uri.startsWith("/speaker")) {
    return request;
  }

  var token = request.querystring.token && request.querystring.token.value;
  if (!token) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  var dotIndex = token.indexOf(".");
  if (dotIndex === -1) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  var payloadB64 = token.slice(0, dotIndex);
  var sigB64 = token.slice(dotIndex + 1);

  function toStdBase64(s) {
    var r = s.replace(/-/g, "+").replace(/_/g, "/");
    var pad = (4 - r.length % 4) % 4;
    for (var i = 0; i < pad; i++) r += "=";
    return r;
  }

  try {
    var encoder = new TextEncoder();
    var key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(SIGNING_SECRET),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );

    var sigStd = toStdBase64(sigB64);
    var sigBytes = Uint8Array.from(atob(sigStd), function(c) { return c.charCodeAt(0); });
    var valid = await crypto.subtle.verify("HMAC", key, sigBytes, encoder.encode(payloadB64));

    if (!valid) {
      return { statusCode: 403, statusDescription: "Forbidden" };
    }

    var payloadStd = toStdBase64(payloadB64);
    var payload = JSON.parse(atob(payloadStd));

    if (Math.floor(Date.now() / 1000) > payload.exp) {
      return { statusCode: 403, statusDescription: "Token expired" };
    }
  } catch (_) {
    return { statusCode: 403, statusDescription: "Forbidden" };
  }

  return request;
}
