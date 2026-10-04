#include "ble_link.h"

#include <NimBLEDevice.h>

#include <algorithm>
#include <deque>
#include <mutex>
#include <utility>

#include "util/log.h"

namespace ble {

// shared/pairing.json
static const char* kService = "42a40001-0087-4bd2-ab9b-8b4febd5191e";
static const char* kInfo = "42a40002-0087-4bd2-ab9b-8b4febd5191e";
static const char* kWifiScan = "42a40003-0087-4bd2-ab9b-8b4febd5191e";
static const char* kProvision = "42a40004-0087-4bd2-ab9b-8b4febd5191e";
static const char* kStatus = "42a40005-0087-4bd2-ab9b-8b4febd5191e";
static const size_t kMaxMessage = 1024;

static NimBLEServer* s_server = nullptr;
static NimBLECharacteristic* s_info = nullptr;
static NimBLECharacteristic* s_wifiScan = nullptr;
static NimBLECharacteristic* s_status = nullptr;
static uint32_t s_passkey = 0;
static volatile uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;

// Filled by the NimBLE task, emptied by the main loop.
static std::mutex s_lock;
static std::deque<std::pair<Channel, std::string>> s_requests;
static std::string s_buffer[2];  // per channel, until '\n'

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo& c) override {
    s_conn = c.getConnHandle();
    LOGF("ble: connected %s\n", c.getAddress().toString().c_str());
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    s_conn = BLE_HS_CONN_HANDLE_NONE;
    std::lock_guard<std::mutex> g(s_lock);
    s_buffer[0].clear();
    s_buffer[1].clear();
    LOGF("ble: disconnected (0x%x)\n", reason);
  }
  uint32_t onPassKeyDisplay() override { return s_passkey; }
  void onAuthenticationComplete(NimBLEConnInfo& c) override {
    LOGF("ble: pairing %s\n", c.isEncrypted() && c.isAuthenticated() ? "done" : "failed");
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo&) override { LOGF("ble: MTU %u\n", mtu); }
};

// Writes come in chunks of at most MTU − 3 bytes; a message ends at '\n'.
class WriteCallbacks : public NimBLECharacteristicCallbacks {
 public:
  explicit WriteCallbacks(Channel channel) : m_channel(channel) {}

  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
    const NimBLEAttValue v = c->getValue();
    std::lock_guard<std::mutex> g(s_lock);
    std::string& buf = s_buffer[static_cast<int>(m_channel)];
    for (size_t i = 0; i < v.size(); i++) {
      const char ch = static_cast<char>(v.data()[i]);
      if (ch == '\n') {
        // Too long: an empty line, which the caller answers with bad_request.
        s_requests.emplace_back(m_channel, buf.size() > kMaxMessage ? std::string() : buf);
        buf.clear();
      } else if (buf.size() <= kMaxMessage) {
        buf += ch;
      }
    }
  }

 private:
  Channel m_channel;
};

static ServerCallbacks s_serverCallbacks;
static WriteCallbacks s_wifiScanWrites(Channel::wifiScan);
static WriteCallbacks s_provisionWrites(Channel::provision);

void start(const char* name, uint32_t passkey, const std::string& info) {
  s_passkey = passkey;
  NimBLEDevice::init(name);
  NimBLEDevice::setMTU(247);
  // LE Secure Connections with MITM: the frame shows the passkey, the phone asks for it.
  // Bonds are kept only for this session: each setup has a new code.
  NimBLEDevice::deleteAllBonds();
  NimBLEDevice::setSecurityAuth(true, true, true);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);
  NimBLEDevice::setSecurityPasskey(passkey);

  s_server = NimBLEDevice::createServer();
  s_server->setCallbacks(&s_serverCallbacks, false);
  s_server->advertiseOnDisconnect(true);

  NimBLEService* svc = s_server->createService(kService);
  s_info = svc->createCharacteristic(kInfo, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::READ_AUTHEN,
                                     kMaxMessage);
  s_wifiScan = svc->createCharacteristic(
      kWifiScan, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN | NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* provision = svc->createCharacteristic(
      kProvision, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN);
  s_status = svc->createCharacteristic(kStatus, NIMBLE_PROPERTY::NOTIFY);
  s_wifiScan->setCallbacks(&s_wifiScanWrites);
  provision->setCallbacks(&s_provisionWrites);
  setInfo(info);
  svc->start();

  // The service UUID in the advertisement, the name in the scan response: flags, a
  // 128-bit UUID and the name don't fit in 31 bytes together.
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData data;
  data.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  data.addServiceUUID(kService);
  adv->setAdvertisementData(data);
  NimBLEAdvertisementData response;
  response.setName(name);
  adv->setScanResponseData(response);
  adv->enableScanResponse(true);
  const bool ok = adv->start();
  LOGF("ble: advertising as %s: %s\n", name, ok ? "ok" : "failed");
}

void stop() {
  if (!s_server) return;
  if (s_conn != BLE_HS_CONN_HANDLE_NONE) {
    s_server->disconnect(s_conn);
    delay(200);
  }
  NimBLEDevice::getAdvertising()->stop();
  NimBLEDevice::deleteAllBonds();
  NimBLEDevice::deinit(true);
  s_server = nullptr;
  s_info = s_wifiScan = s_status = nullptr;
  s_conn = BLE_HS_CONN_HANDLE_NONE;
  std::lock_guard<std::mutex> g(s_lock);
  s_requests.clear();
  LOGLN("ble: off");
}

void setInfo(const std::string& info) {
  if (s_info) s_info->setValue(info);
}

bool nextRequest(Channel& channel, std::string& line) {
  std::lock_guard<std::mutex> g(s_lock);
  if (s_requests.empty()) return false;
  channel = s_requests.front().first;
  line = std::move(s_requests.front().second);
  s_requests.pop_front();
  return true;
}

// One message as notifications of at most MTU − 3 bytes each.
static void send(NimBLECharacteristic* c, const JsonDocument& message) {
  const uint16_t conn = s_conn;
  if (!c || conn == BLE_HS_CONN_HANDLE_NONE) return;
  std::string line;
  serializeJson(message, line);
  line += '\n';
  const size_t chunk = std::max(20, static_cast<int>(s_server->getPeerMTU(conn)) - 3);
  for (size_t at = 0; at < line.size(); at += chunk) {
    const size_t n = std::min(chunk, line.size() - at);
    // A burst can run the stack out of buffers for a moment: wait and try again.
    for (int tries = 0; !c->notify(reinterpret_cast<const uint8_t*>(line.data() + at), n, conn); tries++) {
      if (tries == 50 || s_conn != conn) return;
      delay(20);
    }
  }
}

void notifyWifiScan(const JsonDocument& message) { send(s_wifiScan, message); }
void notifyStatus(const JsonDocument& message) { send(s_status, message); }

bool connected() { return s_conn != BLE_HS_CONN_HANDLE_NONE; }

}  // namespace ble
