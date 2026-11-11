#include "power.h"

#include <esp_sleep.h>

#include "board/e1002.h"
#include "core/battery.h"
#include "display/display.h"
#include "storage/sd_card.h"
#include "util/log.h"

namespace power {

int batteryPercent() {
  pinMode(BATTERY_ENABLE_PIN, OUTPUT);
  digitalWrite(BATTERY_ENABLE_PIN, HIGH);
  analogSetPinAttenuation(BATTERY_ADC_PIN, ADC_11db);  // up to ~3.1 V; the pin sees ~2.1
  delay(50);
  // analogReadMilliVolts applies this chip's factory ADC calibration (eFuse). The raw
  // count × 3.3 V / 4095 that the reference used skips it and read low on the E1002: a
  // full battery showed 74 %.
  uint32_t sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogReadMilliVolts(BATTERY_ADC_PIN);
    delay(5);
  }
  digitalWrite(BATTERY_ENABLE_PIN, LOW);
  const int mv = static_cast<int>(sum / 16 * BATTERY_DIVIDER_RATIO);
  const int pct = battery::percentFromMillivolts(mv);
  LOGF("battery: %d mV, %d %%\n", mv, pct);
  return pct;
}

Wake wakeReason() {
  switch (esp_sleep_get_wakeup_cause()) {
    case ESP_SLEEP_WAKEUP_TIMER:
      return Wake::timer;
    case ESP_SLEEP_WAKEUP_EXT0:
      return Wake::green;
    case ESP_SLEEP_WAKEUP_EXT1:
      return Wake::white;
    default:
      return Wake::powerOn;
  }
}

bool leftWhiteHeld() {
  delay(10);
  return digitalRead(WHITE_BUTTON_LEFT) == LOW && digitalRead(WHITE_BUTTON_RIGHT) != LOW;
}

uint32_t greenHeldMs(uint32_t limitMs) {
  const uint32_t t0 = millis();
  while (digitalRead(GREEN_BUTTON) == LOW && millis() - t0 < limitMs) delay(10);
  return millis() - t0;
}

void deepSleep(uint32_t seconds) {
  LOGF("sleeping %lu s\n", static_cast<unsigned long>(seconds));
  Serial.flush();
  card::unmount();
  display::sleep();
  esp_sleep_enable_timer_wakeup(static_cast<uint64_t>(seconds) * 1000000ULL);
  esp_sleep_enable_ext0_wakeup(static_cast<gpio_num_t>(GREEN_BUTTON), LOW);
  esp_sleep_enable_ext1_wakeup((1ULL << WHITE_BUTTON_RIGHT) | (1ULL << WHITE_BUTTON_LEFT), ESP_EXT1_WAKEUP_ANY_LOW);
  esp_deep_sleep_start();
}

}  // namespace power
