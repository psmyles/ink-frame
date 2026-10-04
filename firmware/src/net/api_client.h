// HTTPS to the frame's project (shared/api/openapi.yaml), checked against the built-in
// CA bundle: never without certificate checks.
#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

namespace api {

// JSON documents in PSRAM: a full photo list with signed URLs can be ~1 MB.
JsonDocument newDocument();

struct Response {
  int status = 0;        // HTTP status; 0 = no answer (Wi-Fi, DNS, TLS)
  String errorCode;      // error.code from the body, if any
};

// POSTs body as JSON; parses a JSON answer into out (when there is one).
Response postJson(const String& url, const JsonDocument& body, const String& bearer, JsonDocument& out);

// Streams url into path on the card, checking the size and SHA-256 on the way.
bool download(const String& url, const String& path, uint32_t bytes, const String& sha256);

}  // namespace api
