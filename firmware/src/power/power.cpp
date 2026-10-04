#include "power.h"

#include <esp_sleep.h>

#include "board/e1002.h"
#include "display/display.h"
#include "storage/sd_card.h"
#include "util/log.h"

namespace power {

int batteryPercent() {
  pinMode(BATTERY_ENABLE_PIN, OUTPUT);
  digitalWrite(BATTERY_ENABLE_PIN, HIGH);
  delay(50);
  uint32_t sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(BATTERY_ADC_PIN);
    delay(5);
  }
  digitalWrite(BATTERY_ENABLE_PIN, LOW);
  const float volts = (sum / 16 / ADC_RESOLUTION) * ADC_REFERENCE_VOLTAGE * VOLTAGE_DIVIDER_RATIO;
  int pct = static_cast<int>((volts - BATTERY_EMPTY_VOLTAGE) / (BATTERY_FULL_VOLTAGE - BATTERY_EMPTY_VOLTAGE) * 100.0f);
  pct = constrain(pct, 0, 100);
  LOGF("battery: %.2f V, %d %%\n", volts, pct);
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
