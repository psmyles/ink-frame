#include "api_client.h"

#include <HTTPClient.h>
#include <SD.h>
#include <WiFiClientSecure.h>
#include <esp_heap_caps.h>
#include <mbedtls/sha256.h>

#include "util/log.h"

// The Mozilla CA bundle compiled into Arduino-ESP32's mbedTLS.
extern const uint8_t x509_crt_bundle_start[] asm("_binary_x509_crt_bundle_start");

namespace api {

struct SpiRamAllocator : ArduinoJson::Allocator {
  void* allocate(size_t n) override { return heap_caps_malloc(n, MALLOC_CAP_SPIRAM); }
  void deallocate(void* p) override { heap_caps_free(p); }
  void* reallocate(void* p, size_t n) override { return heap_caps_realloc(p, n, MALLOC_CAP_SPIRAM); }
};
static SpiRamAllocator s_alloc;

JsonDocument newDocument() { return JsonDocument(&s_alloc); }

// Collects an answer in PSRAM (HTTPClient undoes chunked encoding on the way).
class Buffer : public Stream {
 public:
  explicit Buffer(size_t max) : max_(max) {}
  ~Buffer() { heap_caps_free(data_); }
  size_t write(uint8_t c) override { return write(&c, 1); }
  size_t write(const uint8_t* p, size_t n) override {
    if (len_ + n > max_) return 0;
    if (len_ + n > cap_) {
      size_t cap = cap_ ? cap_ * 2 : 16384;
      while (cap < len_ + n) cap *= 2;
      void* d = heap_caps_realloc(data_, cap, MALLOC_CAP_SPIRAM);
      if (!d) return 0;
      data_ = static_cast<uint8_t*>(d);
      cap_ = cap;
    }
    memcpy(data_ + len_, p, n);
    len_ += n;
    return n;
  }
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  const uint8_t* data() const { return data_; }
  size_t size() const { return len_; }

 private:
  uint8_t* data_ = nullptr;
  size_t len_ = 0, cap_ = 0, max_;
};

static void secure(WiFiClientSecure& c) {
  c.setCACertBundle(x509_crt_bundle_start);
  c.setTimeout(30);
}

Response postJson(const String& url, const JsonDocument& body, const String& bearer, JsonDocument& out) {
  Response r;
  WiFiClientSecure client;
  secure(client);
  HTTPClient http;
  http.setConnectTimeout(15000);
  http.setTimeout(30000);
  if (!http.begin(client, url)) return r;
  http.addHeader("Content-Type", "application/json");
  if (bearer.length()) http.addHeader("Authorization", "Bearer " + bearer);
  String payload;
  serializeJson(body, payload);
  r.status = http.POST(payload);
  payload = String();
  if (r.status <= 0) {
    LOGF("api: %s: %s\n", url.c_str(), http.errorToString(r.status).c_str());
    r.status = 0;
    http.end();
    return r;
  }
  Buffer buf(4 * 1024 * 1024);
  http.writeToStream(&buf);
  http.end();
  if (buf.size() && deserializeJson(out, buf.data(), buf.size()) == DeserializationError::Ok) {
    if (r.status >= 300) r.errorCode = out["error"]["code"] | "";
  }
  LOGF("api: %s → %d %s\n", url.substring(url.lastIndexOf('/')).c_str(), r.status, r.errorCode.c_str());
  return r;
}

// Writes to a file while hashing and counting.
class HashingFile : public Stream {
 public:
  explicit HashingFile(File& f) : f_(f) {
    mbedtls_sha256_init(&ctx_);
    mbedtls_sha256_starts(&ctx_, 0);
  }
  ~HashingFile() { mbedtls_sha256_free(&ctx_); }
  size_t write(uint8_t c) override { return write(&c, 1); }
  size_t write(const uint8_t* p, size_t n) override {
    const size_t w = f_.write(p, n);
    mbedtls_sha256_update(&ctx_, p, w);
    count += w;
    return w;
  }
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  String hex() {
    uint8_t d[32];
    mbedtls_sha256_finish(&ctx_, d);
    char s[65];
    for (int i = 0; i < 32; i++) sprintf(s + i * 2, "%02x", d[i]);
    return String(s);
  }
  size_t count = 0;

 private:
  File& f_;
  mbedtls_sha256_context ctx_;
};

bool download(const String& url, const String& path, uint32_t bytes, const String& sha256) {
  WiFiClientSecure client;
  secure(client);
  HTTPClient http;
  http.setConnectTimeout(15000);
  http.setTimeout(30000);
  if (!http.begin(client, url)) return false;
  const int status = http.GET();
  if (status != 200) {
    LOGF("download: %d\n", status);
    http.end();
    return false;
  }
  File f = SD.open(path, FILE_WRITE);
  if (!f) {
    http.end();
    return false;
  }
  HashingFile out(f);
  http.writeToStream(&out);
  http.end();
  f.close();
  const String got = out.hex();
  if (out.count != bytes || got != sha256) {
    LOGF("download: %u bytes, sha %s (expected %u, %s)\n", out.count, got.substring(0, 8).c_str(), bytes,
         sha256.substring(0, 8).c_str());
    SD.remove(path);
    return false;
  }
  return true;
}

}  // namespace api
