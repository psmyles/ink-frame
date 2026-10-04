#include "ota.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <Update.h>
#include <WiFiClientSecure.h>
#include <esp_ota_ops.h>
#include <freertos/FreeRTOS.h>
#include <freertos/timers.h>
#include <mbedtls/ecdsa.h>
#include <mbedtls/sha256.h>

#include <memory>

#include "net/ota_keys.h"
#include "provision/provisioning.h"
#include "util/log.h"

#ifndef INKFRAME_CONSOLE
#define INKFRAME_CONSOLE 1
#endif

// Arduino-ESP32 keeps a new firmware as soon as it starts; the trial decides instead.
extern "C" bool verifyRollbackLater() { return true; }

// The Mozilla CA bundle compiled into Arduino-ESP32's mbedTLS.
extern const uint8_t x509_crt_bundle_start[] asm("_binary_x509_crt_bundle_start");

namespace ota {

static const char* kNs = "ota";  // apart from the settings, so a factory reset keeps it
static const int64_t kCheckEveryS = 20 * 3600;
static const uint32_t kTrialMs = 10 * 60000;

// One request; plain http only to a test feed from a developer build.
class Connection {
 public:
  bool begin(const String& url) {
    http.setConnectTimeout(15000);
    http.setTimeout(30000);
    http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
    if (url.startsWith("https://")) {
      tls_.setCACertBundle(x509_crt_bundle_start);
      tls_.setTimeout(30);
      return http.begin(tls_, url);
    }
#if INKFRAME_CONSOLE
    if (url.startsWith("http://")) return http.begin(plain_, url);
#endif
    return false;
  }

 private:
  WiFiClientSecure tls_;  // before http: it's used until http is gone
  WiFiClient plain_;

 public:
  HTTPClient http;
};

static bool unhex(const std::string& s, uint8_t* out, size_t n) {
  if (s.size() != n * 2) return false;
  for (size_t i = 0; i < n; i++) {
    if (!isxdigit(s[2 * i]) || !isxdigit(s[2 * i + 1])) return false;
    out[i] = static_cast<uint8_t>(strtoul(s.substr(2 * i, 2).c_str(), nullptr, 16));
  }
  return true;
}

// ECDSA P-256 over signedText(), by one of the keys in ota_keys.h.
static bool signedByUs(const fwupdate::Release& r) {
  uint8_t sig[64], hash[32];
  if (!unhex(r.signature, sig, sizeof sig)) return false;
  const std::string text = fwupdate::signedText(r);
  mbedtls_sha256_ret(reinterpret_cast<const uint8_t*>(text.data()), text.size(), hash, 0);
  mbedtls_ecp_group grp;
  mbedtls_mpi sr, ss;
  mbedtls_ecp_group_init(&grp);
  mbedtls_mpi_init(&sr);
  mbedtls_mpi_init(&ss);
  bool ok = false;
  if (mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_SECP256R1) == 0 && mbedtls_mpi_read_binary(&sr, sig, 32) == 0 &&
      mbedtls_mpi_read_binary(&ss, sig + 32, 32) == 0) {
    for (const auto& key : kReleaseKeys) {
      mbedtls_ecp_point q;
      mbedtls_ecp_point_init(&q);
      ok = mbedtls_ecp_point_read_binary(&grp, &q, key, sizeof key) == 0 &&
           mbedtls_ecdsa_verify(&grp, hash, sizeof hash, &q, &sr, &ss) == 0;
      mbedtls_ecp_point_free(&q);
      if (ok) break;
    }
  }
  mbedtls_mpi_free(&sr);
  mbedtls_mpi_free(&ss);
  mbedtls_ecp_group_free(&grp);
  return ok;
}

// How often this version was installed here and didn't keep itself.
static int failedTries(const std::string& version) {
  Preferences p;
  p.begin(kNs, false);
  const int n = p.isKey("try") && p.getString("try") == version.c_str() ? p.getUChar("tries", 0) : 0;
  p.end();
  return n;
}

static void noteInstalled(const std::string& version) {
  const int n = failedTries(version);
  Preferences p;
  p.begin(kNs, false);
  p.putString("try", version.c_str());
  p.putUChar("tries", static_cast<uint8_t>(n + 1));
  p.end();
}

// Streams the image into the other app slot, checking its size and SHA-256 on the way.
static bool flash(const fwupdate::Release& r, Result& res) {
  uint8_t want[32];
  if (!unhex(r.sha256, want, sizeof want) || r.size == 0) {
    res.status = "bad_manifest";
    return false;
  }
  Connection c;
  if (!c.begin(r.url.c_str())) {
    res.status = "bad_manifest";
    return false;
  }
  const int code = c.http.GET();
  if (code != 200) {
    LOGF("ota: image: %d\n", code);
    res.status = "download_failed";
    return false;
  }
  if (!Update.begin(r.size)) {
    LOGF("ota: %s\n", Update.errorString());
    res.status = "flash_failed";
    return false;
  }
  WiFiClient* in = c.http.getStreamPtr();
  std::unique_ptr<uint8_t[]> buf(new uint8_t[4096]);
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  mbedtls_sha256_starts_ret(&sha, 0);
  size_t got = 0;
  while (got < r.size) {
    const int n = in->readBytes(buf.get(), std::min<size_t>(4096, r.size - got));
    if (n <= 0) break;
    mbedtls_sha256_update_ret(&sha, buf.get(), n);
    if (Update.write(buf.get(), n) != static_cast<size_t>(n)) break;
    got += n;
  }
  c.http.end();
  uint8_t digest[32];
  mbedtls_sha256_finish_ret(&sha, digest);
  mbedtls_sha256_free(&sha);
  if (got != r.size) {
    LOGF("ota: got %u of %u bytes %s\n", got, r.size, Update.hasError() ? Update.errorString() : "");
    res.status = Update.hasError() ? "flash_failed" : "download_failed";
    Update.abort();
    return false;
  }
  if (memcmp(digest, want, sizeof want) != 0) {
    res.status = "bad_hash";
    Update.abort();
    return false;
  }
  if (!Update.end()) {  // checks the image, then makes it the one to start
    LOGF("ota: %s\n", Update.errorString());
    res.status = "flash_failed";
    return false;
  }
  return true;
}

Result check(const String& feedUrl, int batteryPct, bool anyRollout) {
  Result res;
  JsonDocument doc;
  {
    Connection c;
    if (!c.begin(feedUrl + "/" + MODEL_ID + "/manifest.json")) {
      res.status = "bad_feed_url";
      return res;
    }
    const int code = c.http.GET();
    if (code != 200) {
      LOGF("ota: feed: %d\n", code);
      res.status = "no_feed";
      return res;
    }
    const DeserializationError e = deserializeJson(doc, c.http.getString());
    c.http.end();
    if (e != DeserializationError::Ok) {
      res.status = "bad_manifest";
      return res;
    }
  }
  fwupdate::Release r;
  r.modelId = doc["model_id"] | "";
  r.version = doc["version"] | "";
  r.url = doc["url"] | "";
  r.size = doc["size"] | 0u;
  r.sha256 = doc["sha256"] | "";
  r.minBatteryPct = doc["min_battery_pct"] | 100;
  r.rolloutPercent = doc["rollout_percent"] | 0;
  r.signature = doc["signature"] | "";
  res.version = r.version.c_str();
  if (!signedByUs(r)) {
    res.status = "bad_signature";
    LOGF("ota: %s: bad signature\n", r.version.c_str());
    return res;
  }
  const fwupdate::Decision d = fwupdate::decide(r, FW_VERSION, MODEL_ID, provisioning::hwId().c_str(), batteryPct,
                                                failedTries(r.version), anyRollout);
  res.status = fwupdate::toString(d);
  LOGF("ota: feed has %s, running %s: %s\n", r.version.c_str(), FW_VERSION, res.status.c_str());
  if (d != fwupdate::Decision::install) return res;
  if (!flash(r, res)) {
    LOGF("ota: %s\n", res.status.c_str());
    return res;
  }
  noteInstalled(r.version);
  res.installed = true;
  res.status = "installed";
  LOGF("ota: %s installed\n", r.version.c_str());
  return res;
}

bool due(int64_t now) {
  Preferences p;
  p.begin(kNs, false);
  const int64_t last = p.getLong64("checked", 0);
  p.end();
  return now < last || now - last >= kCheckEveryS;
}

void markChecked(int64_t now) {
  Preferences p;
  p.begin(kNs, false);
  p.putLong64("checked", now);
  p.end();
}

static TimerHandle_t s_trialTimer = nullptr;

bool beginTrial() {
  esp_ota_img_states_t state;
  if (esp_ota_get_state_partition(esp_ota_get_running_partition(), &state) != ESP_OK ||
      state != ESP_OTA_IMG_PENDING_VERIFY) {
    return false;
  }
  LOGF("ota: %s is on trial\n", FW_VERSION);
  // A restart before keep() makes the bootloader go back.
  s_trialTimer = xTimerCreate("trial", pdMS_TO_TICKS(kTrialMs), pdFALSE, nullptr, [](TimerHandle_t) { esp_restart(); });
  if (s_trialTimer) xTimerStart(s_trialTimer, 0);
  return true;
}

void keep() {
  if (s_trialTimer) {
    xTimerStop(s_trialTimer, 0);
    xTimerDelete(s_trialTimer, 0);
    s_trialTimer = nullptr;
  }
  esp_ota_mark_app_valid_cancel_rollback();
  Preferences p;
  p.begin(kNs, false);
  p.remove("try");
  p.remove("tries");
  p.end();
  LOGF("ota: keeping %s\n", FW_VERSION);
}

void giveUp() {
  LOGF("ota: %s didn't work; back to the previous firmware\n", FW_VERSION);
  Serial.flush();
  esp_ota_mark_app_invalid_rollback_and_reboot();
  esp_restart();  // not reached
}

}  // namespace ota
