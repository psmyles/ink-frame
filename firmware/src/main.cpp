// Ink Frame firmware: the boot state machine (PLAN.md §9.4). Every wake runs setup()
// once and ends in deep sleep; loop() is never reached.
#include <Arduino.h>
#include <esp_random.h>
#include <time.h>

#include "board/e1002.h"
#include "board/spi_bus.h"
#include "config/nvs_settings.h"
#include "core/manifest.h"
#include "core/schedule.h"
#include "display/display.h"
#include "net/ota.h"
#include "net/sync.h"
#include "net/wifi.h"
#include "power/power.h"
#include "provision/pairing_mode.h"
#include "provision/provisioning.h"
#include "provision/serial_console.h"
#include "storage/cache.h"
#include "storage/sd_card.h"
#include "util/log.h"

// Kept through deep sleep.
RTC_DATA_ATTR static int64_t rtcNextImageAt = 0;
RTC_DATA_ATTR static int64_t rtcLastAttemptAt = 0;
RTC_DATA_ATTR static uint8_t rtcFailures = 0;
RTC_DATA_ATTR static int32_t rtcSequentialIndex = -1;
RTC_DATA_ATTR static char rtcLastId[40] = {0};

#ifndef INKFRAME_CONSOLE
#define INKFRAME_CONSOLE 1  // the serial console (developer builds; README.md)
#endif
#ifndef INKFRAME_AUTO_UPDATE
#define INKFRAME_AUTO_UPDATE 0  // firmware updates from the feed (release builds; docs/ota.md)
#endif

static const uint32_t kConsoleIdleMs = 10 * 60000;
static const uint32_t kLongSleep = 7 * schedule::kDay;  // until a button

static schedule::Now now() {
  const time_t t = time(nullptr);
  tm local{};
  localtime_r(&t, &local);
  return {static_cast<int64_t>(t), local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec, wifi::timeKnown()};
}

static int64_t nextSyncAt(const Config& cfg) {
  if (rtcFailures > 0) return rtcLastAttemptAt + schedule::backoffS(cfg.settings.schedule.syncIntervalS, rtcFailures);
  return cfg.lastSyncAt + cfg.settings.schedule.syncIntervalS;
}

// Setup (PAIRING): Bluetooth with a code on the screen; sleeps until the green button if
// nobody connects the frame. Returns once linked, its photos just checked.
static void setupMode(Config& cfg, int battery) {
  if (!pairing::run(cfg, battery)) power::deepSleep(kLongSleep);
  rtcFailures = 0;
  rtcNextImageAt = 0;
  display::forgetShown();
}

// Shows the next photo; tries the others if one won't decode. False if none would.
static bool showNext(const Config& cfg, bool previous, int battery) {
  std::vector<manifest::Image> list, present;
  cache::loadManifest(list);
  for (const auto& i : list) {
    if (cache::has(i)) present.push_back(i);
  }
  if (present.empty()) {
    display::showReady();
    return true;
  }
  std::vector<std::string> newest = cache::loadNewest();
  manifest::PickState st{rtcSequentialIndex, rtcLastId};
  for (size_t tries = 0; tries < present.size(); tries++) {
    const int i = manifest::pickNext(present, newest, st, cfg.settings.sequential, previous, esp_random());
    LOGF("show: %s\n", present[i].id.c_str());
    if (display::decodePhoto(manifest::imagePath(present[i].id).c_str())) {
      cache::saveNewest(newest);
      rtcSequentialIndex = st.sequentialIndex;
      strlcpy(rtcLastId, st.lastId.c_str(), sizeof rtcLastId);
      card::unmount();  // the display has the bus to itself while it refreshes
      display::showPhoto(battery, rtcFailures > 0);
      return true;
    }
  }
  display::showError("None of the photos could be read.", "Try erasing the memory card.");
  return false;
}

void setup() {
  Serial.setRxBufferSize(4096);  // room for the console's `show` transfers
  Serial.begin(115200);
#ifdef INKFRAME_TEST_CRASH
  abort();  // a firmware that never starts, for trying the rollback (docs/ota.md)
#endif
  pinMode(GREEN_BUTTON, INPUT_PULLUP);
  pinMode(WHITE_BUTTON_RIGHT, INPUT_PULLUP);
  pinMode(WHITE_BUTTON_LEFT, INPUT_PULLUP);
  initSpiBus();
  LOGF("\nInk Frame %s (%s), %s\n", FW_VERSION, MODEL_ID, provisioning::name().c_str());

  Config cfg = nvs::load();
  const power::Wake wake = power::wakeReason();
  bool forced = false, wantSetup = false, previous = false, justLinked = false;

  // Green button: short press = check now; 3 s = set up again; 10 s = factory reset.
  if (wake == power::Wake::green || (wake == power::Wake::powerOn && digitalRead(GREEN_BUTTON) == LOW)) {
    const uint32_t held = power::greenHeldMs(10000);
    if (held >= 10000) {
      LOGLN("factory reset");
      card::mount();
      console::factoryReset(cfg);
      wantSetup = true;
    } else if (held >= 3000) {
      wantSetup = true;
    } else {
      forced = true;
    }
  }
  if (wake == power::Wake::white) previous = power::leftWhiteHeld();

  // A new firmware's first start: check for photos straight away, and keep it only if
  // that works (docs/ota.md).
  const bool trial = ota::beginTrial();
  if (trial) forced = true;

  const int battery = power::batteryPercent();
  card::mount();
  if (cfg.linked() && wifi::timeKnown()) setenv("TZ", cfg.settings.tzPosix.c_str(), 1), tzset();

#if INKFRAME_CONSOLE
  // A computer on the USB port (it resets the frame when it opens the port) gets a
  // moment to send a console command.
  if (wake == power::Wake::powerOn) {
    const auto out = console::run(cfg, 1500, kConsoleIdleMs, battery);
    if (out == console::Outcome::provisioned) {
      rtcFailures = 0;
      rtcNextImageAt = 0;
      justLinked = true;
    } else if (out == console::Outcome::reset) {
      wantSetup = true;
    }
  }
#endif

  if (!cfg.linked()) {
    // Removed in the app (its screen stays up): only a button sets it up again.
    if (wake == power::Wake::timer) power::deepSleep(kLongSleep);
    wantSetup = true;
  }
  if (wantSetup) {
    setupMode(cfg, battery);
    justLinked = true;  // linking checked for photos already
    forced = false;
  }

  // ── Check for new photos ──
  schedule::Now t = now();
  const bool due = forced || !t.timeKnown || t.epoch >= nextSyncAt(cfg);
  bool decided = !trial;
  if (due && cfg.hasWifi()) {
    rtcLastAttemptAt = t.epoch;
    photos::Result result = photos::Result::failed;
    // A trial gets a second go: the network worked moments ago, before the restart.
    for (int attempt = 0; attempt < (trial ? 2 : 1) && result == photos::Result::failed; attempt++) {
      if (attempt > 0) delay(10000);
      if (wifi::connect(cfg.ssid, cfg.password) == wifi::Join::ok) {
        photos::Report report;
        result = photos::sync(cfg, battery, false, report);
#if INKFRAME_AUTO_UPDATE
        if (result == photos::Result::ok && !trial && (forced || ota::due(now().epoch))) {
          const ota::Result update = ota::check(FIRMWARE_FEED_URL, battery);
          ota::markChecked(now().epoch);
          if (update.installed) {
            wifi::off();
            card::unmount();
            ESP.restart();  // into the new firmware's trial
          }
        }
#endif
      }
      wifi::off();
    }
    if (trial) {
      // Removed from its album is still a firmware that works.
      result == photos::Result::failed ? ota::giveUp() : ota::keep();
      decided = true;
    }
    if (result == photos::Result::removed) {
      card::unmount();
      display::showRemoved();
      power::deepSleep(kLongSleep);
    }
    rtcFailures = result == photos::Result::ok ? 0 : static_cast<uint8_t>(min(rtcFailures + 1, 30));
    t = now();
    if (t.timeKnown) rtcLastAttemptAt = t.epoch;
  }
  if (!decided) ota::keep();  // no Wi-Fi to try it with

  // ── Show ──
  const schedule::Settings& s = cfg.settings.schedule;
  const bool userWake = forced || justLinked || wake == power::Wake::white;
  if (card::state() != CardState::ok) {
    card::state() == CardState::missing ? display::showNoCard() : display::showCardUnreadable();
  } else {
    const bool due = rtcNextImageAt == 0 || t.epoch >= rtcNextImageAt - 30;
    const bool quiet = t.timeKnown && schedule::inQuiet(s, t.secondOfDay);
    if (userWake || (due && !quiet)) {
      showNext(cfg, previous, battery);
      rtcNextImageAt = t.epoch + s.imageIntervalS;
    } else if (due) {
      rtcNextImageAt = schedule::outOfQuiet(s, t, t.epoch + s.imageIntervalS) - s.imageIntervalS;
    }
  }

  power::deepSleep(schedule::sleepSeconds(s, t, rtcNextImageAt, nextSyncAt(cfg)));
}

void loop() {}
