// Bluetooth for Connect the frame (docs/pairing.md, shared/pairing.json): advertising as
// InkFrame-XXXX, LE Secure Connections with the passkey on the screen, and the service's
// four characteristics. Requests arrive here from the NimBLE task and are handled by the
// caller's loop (src/main.cpp), so joining Wi-Fi and claiming never block Bluetooth.
#pragma once
#include <ArduinoJson.h>

#include <string>

namespace ble {

// Starts advertising; every characteristic needs an encrypted, authenticated link, and
// pairing uses [passkey] (shown on the screen). [info] is the `info` value.
void start(const char* name, uint32_t passkey, const std::string& info);

// Disconnects, stops advertising and frees the stack.
void stop();

// The `info` value, for the next read (after erasing the card or linking).
void setInfo(const std::string& info);

enum class Channel : uint8_t { wifiScan, provision };

// One complete message from the app, or false if none is waiting. `tooLong` messages
// (over 1024 bytes) are dropped and reported with an empty line.
bool nextRequest(Channel& channel, std::string& line);

void notifyWifiScan(const JsonDocument& message);
void notifyStatus(const JsonDocument& message);

bool connected();

}  // namespace ble
